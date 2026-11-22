//  Copyright 2021 Aaron Hance
//  Copyright 2026 Aaron Hance
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

{ USB Mass Storage: SCSI transparent commands over Bulk-Only Transport.
  LUN 0, one interface, READ/WRITE(10), 512..4096 byte sectors.
  Per-device BOT state machines advance in deferred task context.
  No caller buffer is ever DMA-visible; timeout retains DMA ownership.
  Protocol reference: https://www.usb.org/sites/default/files/usbmassbulk_10.pdf }
{
    @author(Aaron Hance <ah@aaronhance.me>)
}
unit driver.storage.ctl.usb;

interface
procedure init;
procedure UnitTest;

implementation

uses boot.mgr, driver.mgr, memory.heap, driver.storage.types,
     driver.storage.mgr, driver.bus.usb.core, driver.bus.usb.types,
     proc.mgr, proc.types, arch.x86.bda, arch.x86.isr.tmr0,
     core.util, arch.x86.util, io.syslog, io.stdio, core.strings,
     driver.storage.vfs, driver.storage.vol.mgr, core.ds.lists,
     driver.storage.iorequest;

const
    CBW_SIGNATURE = $43425355;
    CSW_SIGNATURE = $53425355;
    BUFFER_SIZE = 65536;
    MAX_COMMAND_BYTES = 1024 * 1024;
    MAX_SECTOR_SIZE = 4096;
    TRANSFER_TICKS = (PIT_INPUT_HZ div PIT_DIVISOR) * 5;

type
    TCBW = packed record
        Signature, Tag, DataLength : uint32;
        Flags, Lun, CommandLength : uint8;
        Command : array[0..15] of uint8;
    end;
    TCSW = packed record
        Signature, Tag, Residue : uint32;
        Status : uint8;
    end;
    PCSW = ^TCSW;
    PMSDevice = ^TMSDevice;
    TMSDevice = record
        Next : PMSDevice;
        Original : PUSBDevice;
        USB : PUSBDevice; { Private snapshot survives physical disconnect. }
        Disk : PStorage_Device; { Canonical manager record, retained as tombstone. }
        InEP, OutEP : PUSBEndpoint;
        ControlEP : TUSBEndpoint;
        Transfer : TUSBTransfer;
        Buffer : pointer; { Page aligned, private DMA scratch, also used for control. }
        BufferCapacity : uint32;
        CBW : TCBW;
        CSW : TCSW;
        Request : PIORequest;
        Tag : uint32;
        Phase : (bpIdle, bpCBW, bpData, bpCSW, bpClearData, bpClearCSW,
                 bpReset, bpResetIn, bpResetOut, bpDone);
        RequestPhase : (rpIdle, rpData, rpFlush, rpSenseData, rpSenseFlush);
        Started, DataOffset, RequestOffset, ChunkBytes : uint32;
        TransportResult : uint8;
        CSWRetried : boolean;
        SubmittedToggle : uint8;
        Offline, Ready, InFlight, Attaching, VolumesDetached : boolean;
        SyncUnsupported : boolean;
    end;

var
    Devices : PMSDevice;
    Worker : PProcessContext;
    AttachBusy : boolean;
    MaintenanceNeeded, WatchdogDue : boolean;
    WatchdogTicks : uint32;

{ Publication and parking use the same IRQ exclusion to avoid lost wakeups. }
procedure wake_worker;
var flags : uint32;
begin
    asm pushfd; cli; pop flags end;
    if Worker <> nil then begin
        if Worker^.State = psAwaiting then
            Worker^.State := psReady;
    end;
    if (flags and $200) <> 0 then asm sti end;
end;

procedure finish_attach(c : PMSDevice);
begin
    c^.Attaching := false;
    wake_worker;
end;

{ 0 = park, 1 = drain requests, 2 = retry pending teardown/DMA. Caller holds CLI. }
function worker_action(first : PMSDevice) : uint8;
var c : PMSDevice;
begin
    worker_action := 0;
    c := first;
    while c <> nil do begin
        if c^.Ready and (c^.Request <> nil) then begin
            if c^.Offline or not c^.InFlight or
               not (PUSBTransfer(@c^.Transfer)^.Status in [tsNotStarted, tsInProgress]) then begin
                worker_action := 1;
                exit;
            end;
            worker_action := 2;
        end;
        if c^.Offline and not c^.Attaching and
           (c^.InFlight or (c^.Ready and
            ((not c^.VolumesDetached) or (c^.Buffer <> nil) or (c^.Original = nil)))) then
            worker_action := 2;
        c := c^.Next;
    end;
end;

{ O(1) IRQ work. No controller calls, list traversal or storage callbacks here. }
procedure watchdog(data : void);
begin
    inc(WatchdogTicks);
    if WatchdogTicks < (PIT_INPUT_HZ div PIT_DIVISOR) div 100 then exit;
    WatchdogTicks := 0;
    if MaintenanceNeeded then begin
        WatchdogDue := true;
        wake_worker;
    end;
end;

function be32(p : puint8) : uint32;
begin
    be32 := (uint32(p[0]) shl 24) or (uint32(p[1]) shl 16) or
            (uint32(p[2]) shl 8) or uint32(p[3]);
end;

procedure put32(p : puint8; value : uint32);
begin
    p[0] := value shr 24; p[1] := value shr 16;
    p[2] := value shr 8; p[3] := value;
end;

function valid_capacity(last, size : uint32) : boolean;
begin
    valid_capacity := (last <> $FFFFFFFF) and (size >= 512) and
                      (size <= MAX_SECTOR_SIZE) and ((size and (size - 1)) = 0);
end;

function valid_csw(csw : PCSW; tag, requested, actual : uint32) : boolean;
begin
    valid_csw := (csw^.Signature = CSW_SIGNATURE) and (csw^.Tag = tag) and
                 (csw^.Status <= 2) and (csw^.Residue <= requested) and
                 (actual = sizeof(TCSW));
end;

function transfer_pending(c : PMSDevice) : boolean;
var s : TUSBTransferStatus;
begin
    { Read status afresh: completion may have been delivered by an ISR. }
    s := PUSBTransfer(@c^.Transfer)^.Status;
    transfer_pending := c^.InFlight and ((s = tsInProgress) or (s = tsNotStarted));
end;

procedure poll_controller(c : PMSDevice);
var flags : uint32;
begin
    { Poll and its descriptor cleanup must not be preempted by another poll. }
    asm pushfd; cli; pop flags end;
    if c^.USB^.HC^.fnPoll <> nil then c^.USB^.HC^.fnPoll(c^.USB^.HC);
    if (flags and $200) <> 0 then asm sti end;
end;

function run_transfer(c : PMSDevice) : TUSBTransferStatus;
var started, spins, flags : uint32; submitted : boolean;
begin
    run_transfer := tsTimeout;
    if c^.Offline then exit;
    c^.Transfer.Status := tsNotStarted;
    c^.Transfer.ActualLen := 0;
    c^.Transfer.HCPriv := nil;
    c^.InFlight := true;
    { fnSubmit can configure xHCI endpoints and wait for command completion;
      never call it under the storage manager's IRQ-disabled dispatch lock. }
    asm pushfd; pop flags end;
    if c^.USB^.HC^.HCType <> USB_HC_XHCI then asm cli end;
    if c^.Offline then submitted := false
    else submitted := c^.USB^.HC^.fnSubmit(c^.USB^.HC, @c^.Transfer);
    if (flags and $200) <> 0 then asm sti end;
    if not submitted then begin
        c^.InFlight := false;
        exit;
    end;
    started := puint32(@Counters.c32)^;
    spins := 0;
    while transfer_pending(c) do begin
        poll_controller(c);
        if not transfer_pending(c) then break;
        inc(spins);
        if (c^.Original = nil) or
           (uint32(puint32(@Counters.c32)^ - started) >= TRANSFER_TICKS) or
           (spins >= 10000000) then begin
            { No HC cancellation contract exists yet. Fail closed and retain the
              private transfer/buffers until completion; NEVER free live DMA. }
            c^.Offline := true;
            if c^.Disk <> nil then c^.Disk^.removed := true;
            io.syslog.logln('USBMSC', 'Transfer timed out/disconnected; device offline, DMA quarantined.');
            exit;
        end;
        asm pushfd; pop flags end;
        if (flags and $200) <> 0 then asm hlt end;
    end;
    c^.InFlight := false;
    run_transfer := c^.Transfer.Status;
end;

function control(c : PMSDevice; kind, request : uint8; index, length : uint16) : TUSBTransferStatus;
begin
    c^.Transfer.Device := c^.USB;
    c^.Transfer.Endpoint := @c^.ControlEP;
    c^.Transfer.Direction := dirSetup;
    c^.Transfer.PipeType := ptControl;
    c^.Transfer.Buffer := c^.Buffer;
    c^.Transfer.BufferLen := length;
    c^.Transfer.Setup := make_setup_packet(kind, request, 0, index, length);
    control := run_transfer(c);
end;

procedure command(c : PMSDevice; opcode, length : uint8; bytes : uint32; input : boolean);
begin
    memset(uint32(@c^.CBW), 0, sizeof(TCBW));
    inc(c^.Tag);
    c^.CBW.Signature := CBW_SIGNATURE;
    c^.CBW.Tag := c^.Tag;
    c^.CBW.DataLength := bytes;
    if input then c^.CBW.Flags := $80;
    c^.CBW.CommandLength := length;
    c^.CBW.Command[0] := opcode;
end;

{ Submission never waits for transfer completion. The private transfer and
  DMA buffer remain owned by this device until the HC reports completion. }
procedure submit_stage(c : PMSDevice);
var flags : uint32; accepted : boolean;
begin
    c^.Transfer.Status := tsNotStarted;
    c^.Transfer.ActualLen := 0;
    c^.Transfer.HCPriv := nil;
    c^.Started := puint32(@Counters.c32)^;
    c^.InFlight := true;
    asm pushfd; pop flags end;
    if c^.USB^.HC^.HCType <> USB_HC_XHCI then asm cli end;
    accepted := false;
    if not c^.Offline then accepted := c^.USB^.HC^.fnSubmit(c^.USB^.HC, @c^.Transfer);
    if (flags and $200) <> 0 then asm sti end;
    if not accepted then begin
        c^.InFlight := false;
        c^.Transfer.Status := tsTimeout;
    end;
end;

procedure submit_bulk(c : PMSDevice; ep : PUSBEndpoint; buffer : pointer; count : uint32);
begin
    c^.Transfer.Device := c^.USB;
    c^.Transfer.Endpoint := ep;
    c^.SubmittedToggle := ep^.Toggle;
    c^.Transfer.Direction := ep^.Direction;
    c^.Transfer.PipeType := ptBulk;
    c^.Transfer.Buffer := buffer;
    c^.Transfer.BufferLen := count;
    submit_stage(c);
end;

procedure submit_control(c : PMSDevice; kind, request : uint8; index : uint16);
begin
    c^.Transfer.Device := c^.USB;
    c^.Transfer.Endpoint := @c^.ControlEP;
    c^.Transfer.Direction := dirSetup;
    c^.Transfer.PipeType := ptControl;
    c^.Transfer.Buffer := c^.Buffer;
    c^.Transfer.BufferLen := 0;
    c^.Transfer.Setup := make_setup_packet(kind, request, 0, index, 0);
    submit_stage(c);
end;

procedure bot_done(c : PMSDevice; resultCode : uint8);
begin
    c^.TransportResult := resultCode;
    c^.Phase := bpDone;
end;

procedure bot_recover(c : PMSDevice);
begin
    if c^.Offline then begin
        bot_done(c, 2);
        exit;
    end;
    c^.Phase := bpReset;
    submit_control(c, $21, $FF, c^.USB^.InterfaceNumber);
end;

procedure bot_clear(c : PMSDevice; ep : PUSBEndpoint);
var address : uint16;
begin
    address := ep^.Address;
    if ep^.Direction = dirIn then address := address or $80;
    submit_control(c, $02, USB_REQ_CLEAR_FEATURE, address);
end;

procedure bot_status(c : PMSDevice);
begin
    memset(uint32(@c^.CSW), 0, sizeof(TCSW));
    c^.Phase := bpCSW;
    submit_bulk(c, c^.InEP, @c^.CSW, sizeof(TCSW));
end;

procedure bot_data(c : PMSDevice);
var ep : PUSBEndpoint; count, limit : uint32; buffer : pointer;
begin
    if c^.DataOffset = c^.CBW.DataLength then begin
        bot_status(c);
        exit;
    end;
    ep := c^.OutEP;
    if c^.CBW.Flags = $80 then ep := c^.InEP;
    count := c^.CBW.DataLength - c^.DataOffset;
    if c^.RequestPhase = rpData then begin
        buffer := c^.Buffer;
        if count > c^.BufferCapacity then count := c^.BufferCapacity;
    end else
        buffer := pointer(uint32(c^.Buffer) + c^.DataOffset);
    limit := 4096; { Conservative default for controllers without a limit hook. }
    if c^.USB^.HC^.fnBulkLimit <> nil then
        limit := c^.USB^.HC^.fnBulkLimit(c^.USB^.HC, ep, buffer, count);
    if count > limit then count := limit;
    if count = 0 then begin
        bot_recover(c);
        exit;
    end;
    if (c^.RequestPhase = rpData) and (ep = c^.OutEP) then
        memcpy(uint32(c^.Request^.Buffer) + c^.RequestOffset + c^.DataOffset,
               uint32(buffer), count);
    c^.Phase := bpData;
    submit_bulk(c, ep, buffer, count);
end;

procedure bot_start(c : PMSDevice);
begin
    c^.DataOffset := 0;
    c^.CSWRetried := false;
    c^.TransportResult := 2;
    if c^.Offline or (c^.CBW.DataLength > MAX_COMMAND_BYTES) or
       ((c^.RequestPhase <> rpData) and (c^.CBW.DataLength > BUFFER_SIZE)) then begin
        bot_done(c, 2);
        exit;
    end;
    c^.Phase := bpCBW;
    submit_bulk(c, c^.OutEP, @c^.CBW, sizeof(TCBW));
end;

{ Advance exactly one completed stage. Never wait or recurse on inline completion. }
procedure bot_step(c : PMSDevice);
var status : TUSBTransferStatus; actual, packets : uint32; ep : PUSBEndpoint;
begin
    if c^.Phase in [bpIdle, bpDone] then exit;
    if c^.Offline or (c^.Original = nil) or
       (transfer_pending(c) and (uint32(puint32(@Counters.c32)^ - c^.Started) >= TRANSFER_TICKS)) then begin
        c^.Offline := true;
        if c^.Disk <> nil then c^.Disk^.removed := true;
        { Do not clear InFlight: a timeout has not cancelled DMA. }
        bot_done(c, 2);
        exit;
    end;
    if transfer_pending(c) then exit;
    c^.InFlight := false;
    status := c^.Transfer.Status;
    actual := c^.Transfer.ActualLen;
    ep := c^.Transfer.Endpoint;
    if (status = tsSuccess) and (c^.Transfer.PipeType = ptBulk) and (ep^.MaxPacket > 0) then begin
        packets := actual div ep^.MaxPacket;
        if ((actual mod ep^.MaxPacket) <> 0) or (actual < c^.Transfer.BufferLen) or
           (c^.Transfer.BufferLen = 0) then inc(packets);
        ep^.Toggle := c^.SubmittedToggle xor (packets and 1);
    end;
    case c^.Phase of
        bpCBW: begin
            if (status <> tsSuccess) or (actual <> sizeof(TCBW)) then bot_recover(c)
            else bot_data(c);
        end;
        bpData: begin
            if status = tsStall then begin
                c^.Phase := bpClearData;
                bot_clear(c, ep);
            end else if (status <> tsSuccess) or (actual > c^.Transfer.BufferLen) then bot_recover(c)
            else begin
                if (c^.RequestPhase = rpData) and (ep = c^.InEP) and (actual <> 0) then
                    memcpy(uint32(c^.Buffer),
                           uint32(c^.Request^.Buffer) + c^.RequestOffset + c^.DataOffset, actual);
                inc(c^.DataOffset, actual);
                if actual < c^.Transfer.BufferLen then bot_status(c)
                else bot_data(c);
            end;
        end;
        bpCSW: begin
            if (status = tsStall) and not c^.CSWRetried then begin
                c^.CSWRetried := true;
                c^.Phase := bpClearCSW;
                bot_clear(c, c^.InEP);
            end else if (status <> tsSuccess) or
                not valid_csw(@c^.CSW, c^.CBW.Tag, c^.CBW.DataLength, actual) then bot_recover(c)
            else if c^.CSW.Status = 2 then bot_recover(c)
            else if c^.CSW.Status = 1 then bot_done(c, 1)
            else if c^.CSW.Residue <> c^.CBW.DataLength - c^.DataOffset then bot_recover(c)
            else bot_done(c, 0);
        end;
        bpClearData, bpClearCSW: begin
            if (status <> tsSuccess) or (c^.USB^.HC^.HCType = USB_HC_XHCI) then bot_recover(c)
            else begin
                if (c^.Phase = bpClearCSW) or (c^.CBW.Flags = $80) then c^.InEP^.Toggle := 0
                else c^.OutEP^.Toggle := 0;
                bot_status(c);
            end;
        end;
        bpReset: begin
            if status <> tsSuccess then begin
                c^.Offline := true;
                bot_done(c, 2);
            end else begin
                c^.Phase := bpResetIn;
                bot_clear(c, c^.InEP);
            end;
        end;
        bpResetIn: begin
            if (status <> tsSuccess) or (c^.USB^.HC^.HCType = USB_HC_XHCI) then begin
                c^.Offline := true;
                bot_done(c, 2);
            end else begin
                c^.InEP^.Toggle := 0;
                c^.Phase := bpResetOut;
                bot_clear(c, c^.OutEP);
            end;
        end;
        bpResetOut: begin
            if status <> tsSuccess then c^.Offline := true
            else c^.OutEP^.Toggle := 0;
            bot_done(c, 2);
        end;
    end;
end;

{ Probe-only synchronous adapter over the same state machine. It runs in the
  attachment task, never in the shared storage completion worker. }
function transport(c : PMSDevice; var transferred : uint32) : uint8;
begin
    bot_start(c);
    while c^.Phase <> bpDone do begin
        if transfer_pending(c) then poll_controller(c);
        bot_step(c);
        if transfer_pending(c) and (c^.Phase <> bpDone) then asm hlt end;
    end;
    transferred := c^.DataOffset;
    transport := c^.TransportResult;
end;

function decode_sense(c : PMSDevice; actual : uint32) : TError;
begin
    decode_sense := eIOError;
    if actual < 14 then exit;
    if (puint8(c^.Buffer)[0] and $7E) <> $70 then exit;
    io.syslog.log('USBMSC', 'SCSI sense key='); io.syslog.writeint(puint8(c^.Buffer)[2] and $0F);
    io.syslog.writestring(' ASC='); io.syslog.writeint(puint8(c^.Buffer)[12]);
    io.syslog.writestring(' ASCQ='); io.syslog.writeintln(puint8(c^.Buffer)[13]);
    case puint8(c^.Buffer)[2] and $0F of
        2: decode_sense := eDeviceNotReady;
        3: decode_sense := eBadSector;
        5: decode_sense := eNotSupported;
        6: decode_sense := eDeviceNotReady;
        7: decode_sense := eReadOnly;
    end;
end;

function sense(c : PMSDevice) : TError;
var actual : uint32;
begin
    sense := eIOError;
    command(c, $03, 6, 18, true);
    c^.CBW.Command[4] := 18;
    memset(uint32(c^.Buffer), 0, 18);
    if transport(c, actual) <> 0 then exit;
    sense := decode_sense(c, actual);
end;

function execute(c : PMSDevice; required : uint32) : TError;
var actual : uint32; resultCode, opcode : uint8;
begin
    opcode := c^.CBW.Command[0];
    resultCode := transport(c, actual);
    execute := eIOError;
    if resultCode = 1 then execute := sense(c)
    else if (resultCode = 0) and (actual = required) then execute := eNone;
    if c^.Offline then execute := eIOTimeout;
    if c^.Original = nil then execute := eDeviceRemoved;
    if execute <> eNone then begin
        io.syslog.log('USBMSC', 'Command failed: opcode='); io.syslog.writeint(opcode);
        io.syslog.writestring(' error='); io.syslog.writeintln(ord(execute));
    end;
end;

function sync_cache(c : PMSDevice) : TError;
begin
    sync_cache := eNone;
    if c^.SyncUnsupported then exit;
    command(c, $35, 10, 0, false);
    sync_cache := execute(c, 0);
    { Some removable flash devices reject SYNCHRONIZE CACHE with ILLEGAL
      REQUEST despite accepting WRITE(10). This optional command must not turn
      an acknowledged data write into a zero-byte failure. Other errors remain
      failures; do not retry or suppress an unsuccessful WRITE(10). }
    if sync_cache = eNotSupported then begin
        c^.SyncUnsupported := true;
        io.syslog.logln('USBMSC', 'SYNCHRONIZE CACHE unsupported; using device write completion.');
        sync_cache := eNone;
    end;
end;

function probe(c : PMSDevice; var sectors, sectorSize : uint32) : boolean;
var status : TUSBTransferStatus; attempt : uint32; error : TError;
begin
    probe := false;
    puint8(c^.Buffer)^ := 0;
    status := control(c, $A1, $FE, c^.USB^.InterfaceNumber, 1);
    { A STALL is explicitly allowed for a single-LUN device. }
    if (status <> tsSuccess) and (status <> tsStall) then exit;
    if status = tsSuccess then begin
        if (c^.Transfer.ActualLen <> 1) or (puint8(c^.Buffer)^ > 15) then exit;
        if puint8(c^.Buffer)^ <> 0 then
            io.syslog.logln('USBMSC', 'Multiple LUNs reported; exposing LUN 0 only.');
    end;
    command(c, $12, 6, 36, true);
    c^.CBW.Command[4] := 36;
    if execute(c, 36) <> eNone then exit;
    if (puint8(c^.Buffer)[0] and $1F) <> 0 then exit; { Direct-access disks only. }
    error := eDeviceNotReady;
    for attempt := 1 to 5 do begin
        command(c, $00, 6, 0, false);
        error := execute(c, 0);
        if error <> eDeviceNotReady then break;
        psleep((PIT_INPUT_HZ div PIT_DIVISOR) div 5);
    end;
    if error <> eNone then exit;
    command(c, $25, 10, 8, true);
    if execute(c, 8) <> eNone then exit;
    sectors := be32(puint8(c^.Buffer));
    sectorSize := be32(puint8(uint32(c^.Buffer) + 4));
    if not valid_capacity(sectors, sectorSize) then exit;
    inc(sectors);
    probe := true;
end;

function valid_request(d : PStorage_Device; r : PIORequest) : boolean;
begin
    valid_request := false;
    if (r^.Buffer = nil) or (r^.SectorCount = 0) or (d^.sectorSize = 0) then exit;
    if r^.LBA >= d^.maxSectorCount then exit;
    if r^.SectorCount > d^.maxSectorCount - r^.LBA then exit;
    if r^.SectorCount > $FFFFFFFF div d^.sectorSize then exit;
    if uint32(r^.Buffer) > $FFFFFFFF - r^.SectorCount * d^.sectorSize then exit;
    valid_request := true;
end;

procedure dispatch(d : PStorage_Device; r : PIORequest);
var c : PMSDevice;
begin
    { Called with interrupts masked: publish work only, no USB calls/waits. }
    if d^.removed or (d^.controllerId0 = 0) then begin
        driver.storage.mgr.complete_io(r, false, eDeviceRemoved); exit;
    end;
    c := PMSDevice(d^.controllerId0);
    if c^.Offline or (c^.Original = nil) then begin
        driver.storage.mgr.complete_io(r, false, eDeviceRemoved); exit;
    end;
    if not valid_request(d, r) then begin
        driver.storage.mgr.complete_io(r, false, eInvalidArgument); exit;
    end;
    if (r^.RequestType = ioWrite) and not d^.writable then begin
        driver.storage.mgr.complete_io(r, false, eReadOnly); exit;
    end;
    if c^.Request <> nil then begin
        driver.storage.mgr.complete_io(r, false, eQueueFull); exit;
    end;
    c^.Disk := d;
    c^.RequestOffset := 0;
    c^.RequestPhase := rpIdle;
    c^.Request := r;
    wake_worker;
end;

procedure finish_request(c : PMSDevice; error : TError);
var r : PIORequest;
begin
    r := c^.Request;
    if error = eReadOnly then c^.Disk^.writable := false;
    r^.ByteCount := c^.RequestOffset;
    c^.Request := nil;
    c^.RequestPhase := rpIdle;
    { Detach before callbacks: completion can immediately dispatch the next request. }
    driver.storage.mgr.complete_io(r, error = eNone, error);
end;

{ Grow the private DMA window only when the controller can submit a larger
  chain. Keep the old buffer available on allocation failure. No transfer is
  outstanding when a new SCSI command is prepared. }
procedure prepare_dma_window(c : PMSDevice; bytes : uint32);
var capacity : uint32; buffer : pointer;
begin
    if bytes <= c^.BufferCapacity then exit;
    capacity := c^.USB^.HC^.BulkWindowBytes;
    if capacity > bytes then capacity := bytes;
    if capacity <= c^.BufferCapacity then exit;
    buffer := kalloc_aligned(capacity, 4096);
    if buffer = nil then exit;
    kfree_aligned(c^.Buffer);
    c^.Buffer := buffer;
    c^.BufferCapacity := capacity;
end;

procedure process_request(c : PMSDevice);
var r : PIORequest; blocks : uint32; error : TError; wasFlush : boolean;
begin
    r := c^.Request;
    if r = nil then exit;
    if c^.Offline or (c^.Original = nil) then begin
        error := eIOTimeout;
        if c^.Original = nil then error := eDeviceRemoved;
        finish_request(c, error);
        exit;
    end;
    if c^.RequestPhase = rpIdle then begin
        if c^.RequestOffset = r^.SectorCount * c^.Disk^.sectorSize then begin
            if (r^.RequestType = ioWrite) and not c^.SyncUnsupported then begin
                command(c, $35, 10, 0, false);
                c^.RequestPhase := rpFlush;
                bot_start(c);
            end else finish_request(c, eNone);
            exit;
        end;
        blocks := r^.SectorCount - c^.RequestOffset div c^.Disk^.sectorSize;
        if blocks > MAX_COMMAND_BYTES div c^.Disk^.sectorSize then
            blocks := MAX_COMMAND_BYTES div c^.Disk^.sectorSize;
        c^.ChunkBytes := blocks * c^.Disk^.sectorSize;
        prepare_dma_window(c, c^.ChunkBytes);
        if r^.RequestType = ioRead then command(c, $28, 10, c^.ChunkBytes, true)
        else command(c, $2A, 10, c^.ChunkBytes, false);
        put32(@c^.CBW.Command[2], r^.LBA + c^.RequestOffset div c^.Disk^.sectorSize);
        c^.CBW.Command[7] := blocks shr 8;
        c^.CBW.Command[8] := blocks;
        c^.RequestPhase := rpData;
        bot_start(c);
        exit;
    end;
    bot_step(c);
    if c^.Phase <> bpDone then exit;
    error := eIOError;
    if c^.Offline then error := eIOTimeout;
    if c^.Original = nil then error := eDeviceRemoved;
    if c^.TransportResult = 2 then begin
        finish_request(c, error);
        exit;
    end;
    if c^.RequestPhase in [rpSenseData, rpSenseFlush] then begin
        if c^.TransportResult = 0 then error := decode_sense(c, c^.DataOffset);
        if (c^.RequestPhase = rpSenseFlush) and (error = eNotSupported) then begin
            c^.SyncUnsupported := true;
            error := eNone;
        end;
        finish_request(c, error);
        exit;
    end;
    if c^.TransportResult = 1 then begin
        wasFlush := c^.RequestPhase = rpFlush;
        command(c, $03, 6, 18, true);
        c^.CBW.Command[4] := 18;
        c^.RequestPhase := rpSenseData;
        if wasFlush then c^.RequestPhase := rpSenseFlush;
        bot_start(c);
        exit;
    end;
    if c^.RequestPhase = rpFlush then begin
        finish_request(c, eNone);
        exit;
    end;
    if c^.DataOffset <> c^.ChunkBytes then begin
        finish_request(c, eIOError);
        exit;
    end;
    inc(c^.RequestOffset, c^.ChunkBytes);
    c^.RequestPhase := rpIdle;
end;

procedure disconnect(dev : PUSBDevice);
var c : PMSDevice; flags : uint32;
begin
    asm pushfd; cli; pop flags end;
    c := Devices;
    while c <> nil do begin
        if c^.Original = dev then begin
            c^.Original := nil;
            c^.Offline := true;
            if c^.Disk <> nil then c^.Disk^.removed := true;
            break;
        end;
        c := c^.Next;
    end;
    if (flags and $200) <> 0 then asm sti end;
    wake_worker;
    io.syslog.logln('USBMSC', 'Disk disconnected; further I/O rejected.');
end;

function detach_volumes(c : PMSDevice) : boolean;
var i : uint32; v : PStorage_Volume;
begin
    detach_volumes := true;
    if c^.Disk = nil then exit;
    if c^.Disk^.metadataBusy or (c^.Disk^.activeCount <> 0) then begin
        detach_volumes := false; exit;
    end;
    if c^.Disk^.volumes = nil then exit;
    i := 0;
    while i < DL_Size(c^.Disk^.volumes) do begin
        v := PStorage_Volume(puint32(DL_Get(c^.Disk^.volumes, i))^);
        if (v <> nil) and ((v^.lifecycleFlags and STORAGE_VOLUME_FLAG_MOUNTED) <> 0) then begin
            if driver.storage.vol.mgr.volume_is_busy(v) then detach_volumes := false
            else if not driver.storage.vfs.InvalidateVolume(v) then detach_volumes := false;
        end;
        inc(i);
    end;
end;

procedure worker_loop(ctx : PProcessContext);
var c, next, prev, scan : PMSDevice; flags : uint32; action : uint8; serviceDue : boolean;
begin
    while true do begin
        asm pushfd; cli; pop flags end;
        serviceDue := WatchdogDue;
        WatchdogDue := false;
        if (flags and $200) <> 0 then asm sti end;
        c := Devices;
        while c <> nil do begin
            next := c^.Next;
            if serviceDue and c^.InFlight and not c^.Attaching then poll_controller(c);
            if c^.Ready then process_request(c);
            if c^.Offline and c^.InFlight and not c^.Attaching then begin
                if not transfer_pending(c) then c^.InFlight := false;
            end;
            if c^.Offline and not c^.InFlight and (c^.Request = nil) and
               c^.Ready and not c^.Attaching then begin
                if c^.Disk <> nil then c^.Disk^.removed := true;
                if not c^.VolumesDetached then c^.VolumesDetached := detach_volumes(c);
                if c^.Buffer <> nil then begin
                    kfree_aligned(c^.Buffer); c^.Buffer := nil;
                end;
                if (c^.Original = nil) and c^.VolumesDetached then begin
                    { Keep the manager's removed-device/volume tombstones stable;
                      release every class-driver allocation once DMA is finished. }
                    asm pushfd; cli; pop flags end;
                    prev := nil; scan := Devices;
                    while (scan <> nil) and (scan <> c) do begin prev := scan; scan := scan^.Next; end;
                    if prev = nil then Devices := c^.Next else prev^.Next := c^.Next;
                    if c^.Disk <> nil then c^.Disk^.controllerId0 := 0;
                    if (flags and $200) <> 0 then asm sti end;
                    kfree(void(c^.USB)); kfree_aligned(c);
                end;
            end;
            c := next;
        end;
        asm pushfd; cli; pop flags end;
        action := worker_action(Devices);
        MaintenanceNeeded := action <> 0;
        if action <> 1 then ctx^.State := psAwaiting;
        if (flags and $200) <> 0 then asm sti end;
        if action <> 1 then proc.mgr.proc_yield;
    end;
end;

procedure attach_worker(ctx : PProcessContext);
var c : PMSDevice; d : PStorage_Device; sectors, sectorSize, i, flags : uint32;
    claimed : boolean;
begin
    c := PMSDevice(ctx^.Local);
    { xHCI command submission and manager registration are not reentrant. }
    repeat
        asm pushfd; cli; pop flags end;
        claimed := not AttachBusy;
        if claimed then AttachBusy := true;
        if (flags and $200) <> 0 then asm sti end;
        if not claimed then proc.mgr.proc_sleep_ms(1);
    until claimed;
    d := PStorage_Device(kalloc(sizeof(TStorage_Device)));
    if d = nil then begin
        c^.Offline := true; c^.Ready := true; finish_attach(c); AttachBusy := false; exit;
    end;
    if not probe(c, sectors, sectorSize) then begin
        c^.Offline := true; c^.Ready := true;
        kfree(void(d));
        finish_attach(c); AttachBusy := false;
        io.syslog.logln('USBMSC', 'Probe failed or unsupported disk geometry.');
        exit;
    end;
    memset(uint32(d), 0, sizeof(TStorage_Device));
    d^.volumes := DL_New(sizeof(pointer));
    if d^.volumes = nil then begin
        kfree(void(d)); c^.Offline := true; c^.Ready := true; finish_attach(c); AttachBusy := false; exit;
    end;
    d^.controller := ControllerUSB;
    d^.controllerId0 := uint32(c);
    d^.writable := true;
    d^.sectorSize := sectorSize;
    d^.maxSectorCount := sectors;
    d^.maxActive := 1;
    d^.mergeMaxSectors := MAX_COMMAND_BYTES div sectorSize;
    d^.dispatchRead := @dispatch; d^.dispatchWrite := @dispatch;
    c^.Ready := true;
    driver.storage.mgr.register_device(d);
    { Manager copies the record; never keep the temporary descriptor. }
    i := 0;
    while i < driver.storage.mgr.get_device_count do begin
        if driver.storage.mgr.get_device(i)^.controllerId0 = uint32(c) then begin
            c^.Disk := driver.storage.mgr.get_device(i); break;
        end;
        inc(i);
    end;
    kfree(void(d));
    finish_attach(c); AttachBusy := false;
    io.syslog.logln('USBMSC', 'LUN 0 registered with storage manager.');

end;

function load(ptr : void) : boolean;
var dev : PUSBDevice; c : PMSDevice;
    i, flags : uint32;
begin
    load := false;
    dev := PUSBDevice(ptr);
    if (dev = nil) or (Worker = nil) then exit;
    if (dev^.HC = nil) or (dev^.HC^.fnSubmit = nil) then exit;
    { Core currently binds the first interface and flattens alternate settings.
      Reject ambiguous endpoint sets rather than talking to the wrong pipe. }
    if (dev^.InterfaceCount <> 1) or (dev^.NumEndpoints <> 2) or
       (dev^.Speed = USB_SPEED_LOW) then exit;
    if dev^.HC^.HCType = USB_HC_UHCI then begin
        io.syslog.logln('USBMSC', 'UHCI storage requires HC queue/cleanup support.'); exit;
    end;
    c := PMSDevice(kalloc_aligned(sizeof(TMSDevice), 4096));
    if c = nil then exit;
    memset(uint32(c), 0, sizeof(TMSDevice));
    c^.USB := PUSBDevice(kalloc(sizeof(TUSBDevice)));
    c^.BufferCapacity := BUFFER_SIZE;
    c^.Buffer := kalloc_aligned(BUFFER_SIZE, BUFFER_SIZE);
    if (c^.USB = nil) or (c^.Buffer = nil) then begin
        if c^.USB <> nil then kfree(void(c^.USB));
        kfree_aligned(c^.Buffer); kfree_aligned(c); exit;
    end;
    memcpy(uint32(dev), uint32(c^.USB), sizeof(TUSBDevice));
    c^.Original := dev;
    c^.Attaching := true;
    for i := 0 to 1 do begin
        if (c^.USB^.Endpoints[i].PipeType = ptBulk) and
           (c^.USB^.Endpoints[i].Address <> 0) and
           (c^.USB^.Endpoints[i].MaxPacket > 0) and
           (c^.USB^.Endpoints[i].MaxPacket <= 1024) then begin
            if c^.USB^.Endpoints[i].Direction = dirIn then c^.InEP := @c^.USB^.Endpoints[i]
            else c^.OutEP := @c^.USB^.Endpoints[i];
        end;
    end;
    if (c^.InEP = nil) or (c^.OutEP = nil) then begin
        kfree_aligned(c^.Buffer); kfree(void(c^.USB)); kfree_aligned(c); exit;
    end;
    c^.ControlEP.PipeType := ptControl;
    c^.ControlEP.Direction := dirSetup;
    c^.ControlEP.MaxPacket := dev^.MaxPacket0;
    { Publish before probing so disconnect can invalidate the private context. }
    asm pushfd; cli; pop flags end;
    c^.Next := Devices; Devices := c;
    dev^.fnDisconnect := @disconnect;
    if (flags and $200) <> 0 then asm sti end;
    { The scheduler starts only after boot.mgr.run. Probe and register from
      a task so partition discovery can wait for the persistent I/O worker. }
    if proc.mgr.create('usb.attach', @attach_worker, void(c), 1) = nil then begin
        c^.Offline := true; c^.Ready := true; finish_attach(c); exit;
    end;
    load := true;
end;

{ Memory-only host controller used by UnitTest; never touches a real disk. }
type
    PMock = ^TMock;
    TMock = record
        HC : TUSBHCDriver;
        USB : TUSBDevice;
        Disk : TStorage_Device;
        Request : TIORequest;
        C : TMSDevice;
        Stage, Fault, Controls, DataBytes, DataCalls, Commands, Limit : uint32;
        Process : TProcessContext;
        SenseKey : uint8;
        GoodWrite, GoodRecovery, Hold : boolean;
        TestRequest : PIORequest;
        Completions, CompletedBytes : uint32;
        CompletedError : TError;
    end;

function mock_limit(hc : PUSBHCDriver; ep : PUSBEndpoint; buffer : pointer; length : uint32) : uint32;
begin
    mock_limit := PMock(hc^.PrivData)^.Limit;
    if mock_limit = 0 then mock_limit := BUFFER_SIZE;
end;

function mock_submit(hc : PUSBHCDriver; t : PUSBTransfer) : boolean;
var m : PMock; csw : PCSW; i : uint32;
begin
    m := PMock(hc^.PrivData);
    mock_submit := true;
    t^.Status := tsSuccess;
    t^.ActualLen := t^.BufferLen;
    if m^.Hold then begin
        t^.Status := tsInProgress;
        t^.ActualLen := 0;
        exit;
    end;
    if t^.PipeType = ptControl then begin
        if t^.Setup.bRequest = $FE then begin puint8(t^.Buffer)^ := 0; exit; end;
        case m^.Controls of
            0: m^.GoodRecovery := (t^.Setup.bRequest = $FF) and (t^.Setup.wIndex = 3);
            1: m^.GoodRecovery := m^.GoodRecovery and (t^.Setup.bRequest = 1) and (t^.Setup.wIndex = $81);
            2: m^.GoodRecovery := m^.GoodRecovery and (t^.Setup.bRequest = 1) and (t^.Setup.wIndex = 2);
        end;
        inc(m^.Controls);
        exit;
    end;
    case m^.Stage of
        0: begin
            inc(m^.Commands);
            m^.Stage := 2;
            m^.DataBytes := 0;
            if m^.C.CBW.DataLength <> 0 then m^.Stage := 1;
            if m^.Fault = 6 then begin t^.ActualLen := 30; m^.Stage := 0; end;
        end;
        1: begin
            inc(m^.DataCalls);
            if m^.C.CBW.Flags = $80 then begin
                memset(uint32(t^.Buffer), $A5, t^.BufferLen);
                case m^.C.CBW.Command[0] of
                    $12: puint8(t^.Buffer)[0] := 0;
                    $25: begin put32(puint8(t^.Buffer), 8191); put32(puint8(uint32(t^.Buffer)+4), 512); end;
                    $03: begin memset(uint32(t^.Buffer),0,t^.BufferLen); puint8(t^.Buffer)[0]:=$70;
                        if m^.SenseKey = 0 then puint8(t^.Buffer)[2]:=7 else puint8(t^.Buffer)[2]:=m^.SenseKey; end;
                end;
            end else begin
                m^.GoodWrite := true;
                if t^.BufferLen > 0 then for i := 0 to t^.BufferLen-1 do
                    if puint8(t^.Buffer)[i] <> $5A then m^.GoodWrite := false;
            end;
            if m^.Fault = 4 then t^.ActualLen := t^.BufferLen div 2;
            inc(m^.DataBytes, t^.ActualLen);
            if (m^.DataBytes = m^.C.CBW.DataLength) or
               (t^.ActualLen < t^.BufferLen) then m^.Stage := 2;
        end;
        2: begin
            if m^.Fault = 5 then begin m^.Fault := 0; t^.Status := tsStall; t^.ActualLen := 0; exit; end;
            csw := PCSW(t^.Buffer);
            csw^.Signature := CSW_SIGNATURE; csw^.Tag := m^.C.CBW.Tag;
            csw^.Residue := m^.C.CBW.DataLength - m^.DataBytes;
            csw^.Status := 0;
            case m^.Fault of
                1: inc(csw^.Tag);
                2: csw^.Status := 2;
                3: begin csw^.Status := 1; m^.Fault := 0; end;
                7: inc(csw^.Residue);
                8: t^.ActualLen := 12;
            end;
            m^.Stage := 0;
        end;
    end;
end;

procedure init_mock(m : PMock);
begin
        memset(uint32(m), 0, sizeof(TMock));
        m^.HC.fnSubmit := @mock_submit; m^.HC.HCType := USB_HC_EHCI; m^.HC.PrivData := m;
        m^.USB.HC := @m^.HC; m^.USB.InterfaceNumber := 3;
        m^.USB.Endpoints[0].Address := 1; m^.USB.Endpoints[0].Direction := dirIn;
        m^.USB.Endpoints[1].Address := 2; m^.USB.Endpoints[1].Direction := dirOut;
        m^.USB.Endpoints[0].MaxPacket := 512; m^.USB.Endpoints[1].MaxPacket := 512;
        m^.C.USB := @m^.USB; m^.C.Original := @m^.USB;
        m^.C.InEP := @m^.USB.Endpoints[0]; m^.C.OutEP := @m^.USB.Endpoints[1];
        m^.C.BufferCapacity := BUFFER_SIZE;
        m^.C.Buffer := kalloc_aligned(BUFFER_SIZE, BUFFER_SIZE);
        m^.HC.fnBulkLimit := @mock_limit;
end;

procedure mock_complete(error : TError; data : pointer);
var m : PMock;
begin
    m := PMock(data);
    inc(m^.Completions);
    m^.CompletedError := error;
    m^.CompletedBytes := m^.TestRequest^.ByteCount;
end;

procedure UnitTest;
var passed, failed, actual, sectors, size, flags, steps : uint32; buffer : pointer; other : PMock; savedWorker : PProcessContext; csw : TCSW; bytes : array[0..3] of uint8; m : PMock;
    procedure Assert(ok : boolean; name : pchar);
    begin
        if ok then inc(passed) else begin
            inc(failed); io.syslog.logln('USBMSC FAIL', name);
        end;
    end;
begin
    passed := 0; failed := 0;
    Assert(sizeof(TCBW) = 31, 'CBW wire size');
    Assert(sizeof(TCSW) = 13, 'CSW wire size');
    put32(@bytes[0], $12345678);
    Assert((bytes[0] = $12) and (bytes[3] = $78), 'SCSI byte order');
    Assert(be32(@bytes[0]) = $12345678, 'capacity byte order');
    Assert(valid_capacity(0, 512), 'single sector');
    Assert(valid_capacity($FFFFFFFE, 4096), 'largest representable sector count');
    Assert(not valid_capacity($FFFFFFFF, 512), 'reject READ CAPACITY(16) sentinel');
    Assert(not valid_capacity(1, 0), 'reject zero block size');
    Assert(not valid_capacity(1, 513), 'reject non-power-of-two block size');
    Assert(not valid_capacity(1, 8192), 'reject oversized block size');
    csw.Signature := CSW_SIGNATURE; csw.Tag := 7; csw.Residue := 0; csw.Status := 0;
    Assert(valid_csw(@csw, 7, 512, 13), 'valid CSW');
    Assert(not valid_csw(@csw, 8, 512, 13), 'reject stale tag');
    Assert(not valid_csw(@csw, 7, 512, 12), 'reject short CSW');
    csw.Residue := 513;
    Assert(not valid_csw(@csw, 7, 512, 13), 'reject excessive residue');
    csw.Residue := 0; csw.Status := 3;
    Assert(not valid_csw(@csw, 7, 512, 13), 'reject reserved status');
    csw.Status := 0; csw.Signature := 0;
    Assert(not valid_csw(@csw, 7, 512, 13), 'reject signature');
    m := PMock(kalloc(sizeof(TMock)));
    Assert(m <> nil, 'mock allocation');
    if m <> nil then begin
        init_mock(m);
        Assert(m^.C.Buffer <> nil, 'mock DMA scratch allocation');
        if m^.C.Buffer <> nil then begin
            Assert((uint32(m^.C.Buffer) and (BUFFER_SIZE - 1)) = 0, '64 KiB DMA alignment');
            Assert(worker_action(@m^.C) = 0, 'idle worker can park');
            m^.C.Ready := true;
            m^.C.Request := @m^.Request;
            Assert(worker_action(@m^.C) = 1, 'queued request prevents parking');
            m^.C.Request := nil;
            m^.C.Offline := true;
            Assert(worker_action(@m^.C) = 2, 'disconnect cleanup keeps polling');
            m^.C.Offline := false;
            m^.Disk.sectorSize := 512;
            m^.Disk.maxSectorCount := 8192;
            m^.Disk.controllerId0 := uint32(@m^.C);
            m^.Request.Buffer := m^.C.Buffer;
            m^.Request.SectorCount := 1;
            asm pushfd; cli; pop flags end;
            savedWorker := Worker;
            Worker := @m^.Process;
            m^.Process.State := psAwaiting;
            dispatch(@m^.Disk, @m^.Request);
            Worker := savedWorker;
            if (flags and $200) <> 0 then asm sti end;
            Assert((m^.Process.State = psReady) and (m^.C.Request = @m^.Request),
                   'submission publishes request and wakes parked worker');
            m^.C.Request := nil;
            m^.Commands := 0;
            m^.DataCalls := 0;
            command(@m^.C, $28, 10, BUFFER_SIZE, true);
            Assert(execute(@m^.C, BUFFER_SIZE) = eNone, '64 KiB read');
            Assert((m^.Commands = 1) and (m^.DataCalls = 1) and
                   (puint8(m^.C.Buffer)[BUFFER_SIZE - 1] = $A5), 'one command and data stage for 64 KiB');
            m^.Limit := 32768;
            m^.DataCalls := 0;
            command(@m^.C, $28, 10, BUFFER_SIZE, true);
            Assert((execute(@m^.C, BUFFER_SIZE) = eNone) and (m^.DataCalls = 2),
                   'bounded data stages retain one SCSI command');
            m^.Limit := BUFFER_SIZE;
            memset(uint32(m^.C.Buffer), $5A, BUFFER_SIZE);
            command(@m^.C, $2A, 10, BUFFER_SIZE, false);
            Assert((execute(@m^.C, BUFFER_SIZE) = eNone) and m^.GoodWrite, '64 KiB write data preserved');
            Assert(probe(@m^.C, sectors, size) and (sectors = 8192) and (size = 512), 'probe SCSI disk');
            command(@m^.C, $28, 10, 512, true);
            Assert((execute(@m^.C,512) = eNone) and (puint8(m^.C.Buffer)[511] = $A5), 'read data phase');
            command(@m^.C, $2A, 10, 512, false); memset(uint32(m^.C.Buffer),$5A,512);
            Assert((execute(@m^.C,512) = eNone) and m^.GoodWrite, 'write data phase');
            m^.Fault := 3; command(@m^.C, $2A, 10, 512, false);
            Assert(execute(@m^.C,512) = eReadOnly, 'command failure requests sense');
            m^.Fault := 4; command(@m^.C, $28, 10, 512, true);
            Assert(execute(@m^.C,512) = eIOError, 'short read is not full success');
            m^.Fault := 5; command(@m^.C, $28, 10, 512, true);
            Assert(execute(@m^.C,512) = eNone, 'CSW stall cleared and retried');
            m^.Fault := 1; m^.Controls := 0; command(@m^.C, $28, 10, 512, true);
            Assert((transport(@m^.C,actual) = 2) and (m^.Controls = 3) and m^.GoodRecovery, 'bad tag triggers ordered reset recovery');
            m^.Fault := 2; m^.Controls := 0; command(@m^.C, $28, 10, 512, true);
            Assert((transport(@m^.C,actual) = 2) and m^.GoodRecovery, 'phase error reset recovery');
            m^.Fault := 6; m^.Controls := 0; command(@m^.C, $28, 10, 512, true);
            Assert((transport(@m^.C,actual) = 2) and m^.GoodRecovery, 'short CBW reset recovery');
            m^.Fault := 7; command(@m^.C, $28, 10, 512, true);
            Assert(transport(@m^.C,actual) = 2, 'inconsistent CSW residue rejected');
            m^.Fault := 8; command(@m^.C, $28, 10, 512, true);
            Assert(transport(@m^.C,actual) = 2, 'short CSW rejected');
            m^.Fault := 0; command(@m^.C, $35, 10, 0, false);
            Assert(execute(@m^.C,0) = eNone, 'cache synchronization without data stage');
            m^.Fault := 3; m^.SenseKey := 3;
            Assert(sync_cache(@m^.C) = eBadSector, 'flush media errors propagate');
            Assert(not m^.C.SyncUnsupported, 'media error does not disable flush');
            m^.Fault := 3; m^.SenseKey := 5;
            Assert(sync_cache(@m^.C) = eNone, 'unsupported flush accepts completed write');
            sectors := m^.C.Tag;
            Assert((sync_cache(@m^.C) = eNone) and (m^.C.Tag = sectors), 'unsupported flush is not repeatedly submitted');
            m^.Fault := 3; command(@m^.C, $2A, 10, 512, false);
            Assert(execute(@m^.C,512) = eNotSupported, 'unsupported data write remains a failure');
            m^.Fault := 0; m^.SenseKey := 0;
            m^.Disk.sectorSize := 512; m^.Disk.maxSectorCount := 8192;
            m^.Request.Buffer := m^.C.Buffer; m^.Request.LBA := 8191; m^.Request.SectorCount := 1;
            Assert(valid_request(@m^.Disk,@m^.Request), 'last sector valid');
            m^.Request.SectorCount := 2;
            Assert(not valid_request(@m^.Disk,@m^.Request), 'cross-end request rejected');
            m^.Request.SectorCount := 0;
            Assert(not valid_request(@m^.Disk,@m^.Request), 'zero-sector request rejected');
            m^.Request.LBA := $FFFFFFFE; m^.Request.SectorCount := 4;
            Assert(not valid_request(@m^.Disk,@m^.Request), 'wrapped LBA rejected');
            m^.Request.LBA := 0; m^.Request.SectorCount := 1; m^.Request.Buffer := pointer($FFFFFF00);
            Assert(not valid_request(@m^.Disk,@m^.Request), 'wrapped buffer rejected');
            { Delayed device A must not prevent device B from finishing. }
            other := PMock(kalloc(sizeof(TMock)));
            Assert(other <> nil, 'second device fixture');
            if other <> nil then begin
                init_mock(other);
                Assert(other^.C.Buffer <> nil, 'second device DMA buffer');
                if other^.C.Buffer <> nil then begin
                    m^.Hold := true;
                    command(@m^.C, $28, 10, 512, true);
                    bot_start(@m^.C);
                    bot_step(@m^.C);
                    Assert((m^.C.Phase = bpCBW) and m^.C.InFlight, 'pending stage returns without waiting');
                    command(@other^.C, $28, 10, 512, true);
                    Assert(execute(@other^.C, 512) = eNone, 'second disk completes while first waits');
                    Assert(m^.C.InFlight, 'second disk does not disturb first DMA ownership');
                    m^.C.Started := puint32(@Counters.c32)^ - TRANSFER_TICKS;
                    bot_step(@m^.C);
                    Assert((m^.C.Phase = bpDone) and m^.C.Offline and m^.C.InFlight,
                           'timeout retains in-flight transfer and private DMA');
                    m^.C.Transfer.Status := tsSuccess; { Simulated late hardware retirement. }
                    m^.C.InFlight := false;
                    m^.C.Offline := false;
                    m^.Hold := false;
                    m^.C.Original := @m^.USB;
                    kfree_aligned(other^.C.Buffer);
                end;
                kfree(void(other));
            end;
            { Drive the actual request pump with inline completions and a tail chunk. }
            buffer := kalloc(BUFFER_SIZE + 512);
            Assert(buffer <> nil, 'request buffer');
            if buffer <> nil then begin
                m^.Disk.sectorSize := 512;
                m^.C.Disk := @m^.Disk;
                m^.C.RequestOffset := 0;
                m^.C.RequestPhase := rpIdle;
                m^.Completions := 0;
                m^.Commands := 0;
                m^.DataCalls := 0;
                m^.HC.BulkWindowBytes := MAX_COMMAND_BYTES;
                m^.Limit := MAX_COMMAND_BYTES;
                m^.TestRequest := ioreq_alloc(ioRead, nil, 0, (BUFFER_SIZE div 512) + 1, buffer);
                Assert(m^.TestRequest <> nil, 'pooled request fixture');
                if m^.TestRequest <> nil then begin
                    m^.TestRequest^.Callback := @mock_complete;
                    m^.TestRequest^.CallbackData := m;
                    m^.C.Request := m^.TestRequest;
                    steps := 0;
                    while (m^.C.Request <> nil) and (steps < 32) do begin
                        process_request(@m^.C);
                        inc(steps);
                    end;
                    Assert((m^.Completions = 1) and (m^.CompletedError = eNone) and
                           (m^.CompletedBytes = BUFFER_SIZE + 512), 'request completes once across 64 KiB boundary');
                    Assert(m^.DataCalls = 1, 'controller accepted the full data phase');
                    Assert((m^.Commands = 1) and (puint8(buffer)[0] = $A5) and
                           (puint8(buffer)[BUFFER_SIZE + 511] = $A5),
                           'tail copied under the same SCSI command');
                    if m^.C.Request <> nil then begin
                        ioreq_free(m^.C.Request);
                        m^.C.Request := nil;
                    end;
                end;
                kfree(buffer);
            end;
            kfree_aligned(m^.C.Buffer);
        end;
        kfree(void(m));
    end;
    io.syslog.log('USBMSC', 'Tests passed: '); io.syslog.writeint(passed);
    io.syslog.writestring(' failed: '); io.syslog.writeintln(failed);
end;

procedure test_command(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin
    UnitTest;
    io.stdio.bufWriteStrLn(stdout_buf, 'USB mass storage protocol tests written to serial log.');
end;

procedure init;
var id : TDeviceIdentifier;
begin
    io.stdio.registerCommand('USBMSCTEST', @test_command, 'Test USB mass storage protocol without disk I/O');
    Worker := proc.mgr.create('usb.storage', @worker_loop, nil, 1);
    if Worker = nil then exit;
    register_completion_hook(@wake_worker);
    arch.x86.isr.tmr0.hook(uint32(@watchdog));
    id.Bus := biUSB; id.id0 := idANY; id.id1 := $FFFFFFFF;
    id.id2 := $08; id.id3 := $06; id.id4 := $50; id.ex := nil;
    driver.mgr.register_driver('USB Mass Storage', @id, @load);
end;

initialization
    boot.mgr.registerBoot('driver.storage.ctl.usb', @init, 'USB Mass Storage Driver', BOOT_MGR_BARRIER_DEVICE);
end.
