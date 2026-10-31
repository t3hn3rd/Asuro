{ USB Mass Storage: SCSI transparent commands over Bulk-Only Transport.
  LUN 0, one interface, READ/WRITE(10), 512..4096 byte sectors.
  A persistent worker owns all storage I/O. No caller buffer is ever DMA-visible.
  Protocol reference: https://www.usb.org/sites/default/files/usbmassbulk_10.pdf }
unit driver.storage.ctl.usb;

interface
procedure init;
procedure UnitTest;

implementation

uses boot.mgr, driver.mgr, memory.heap, driver.storage.types,
     driver.storage.mgr, driver.bus.usb.core, driver.bus.usb.types,
     proc.mgr, proc.types, arch.x86.bda, arch.x86.isr.tmr0,
     core.util, arch.x86.util, io.syslog, io.stdio, core.strings,
     driver.storage.vfs, driver.storage.vol.mgr, core.ds.lists;

const
    CBW_SIGNATURE = $43425355;
    CSW_SIGNATURE = $53425355;
    BUFFER_SIZE = 4096;
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
        CBW : TCBW;
        CSW : TCSW;
        Request : PIORequest;
        Tag : uint32;
        Offline, Ready, InFlight, Attaching, VolumesDetached : boolean;
    end;

var
    Devices : PMSDevice;
    Worker : PProcessContext;
    AttachBusy : boolean;

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
                      (size <= BUFFER_SIZE) and ((size and (size - 1)) = 0);
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
           (puint32(@Counters.c32)^ - started >= TRANSFER_TICKS) or
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

function bulk(c : PMSDevice; ep : PUSBEndpoint; buffer : pointer;
              length : uint32; var actual : uint32) : TUSBTransferStatus;
var toggle, packets : uint32; status : TUSBTransferStatus;
begin
    toggle := ep^.Toggle;
    c^.Transfer.Device := c^.USB;
    c^.Transfer.Endpoint := ep;
    c^.Transfer.Direction := ep^.Direction;
    c^.Transfer.PipeType := ptBulk;
    c^.Transfer.Buffer := buffer;
    c^.Transfer.BufferLen := length;
    status := run_transfer(c);
    actual := c^.Transfer.ActualLen;
    if (status = tsSuccess) and (ep^.MaxPacket > 0) then begin
        packets := actual div ep^.MaxPacket;
        if ((actual mod ep^.MaxPacket) <> 0) or (actual < length) or (length = 0) then inc(packets);
        ep^.Toggle := toggle xor (packets and 1);
    end;
    bulk := status;
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

function clear_halt(c : PMSDevice; ep : PUSBEndpoint) : boolean;
var address : uint16;
begin
    address := ep^.Address;
    if ep^.Direction = dirIn then address := address or $80;
    clear_halt := control(c, $02, USB_REQ_CLEAR_FEATURE, address, 0) = tsSuccess;
    if clear_halt then ep^.Toggle := 0;
    { xHCI also needs Reset Endpoint/Set TR Dequeue after a halted ring.
      Until the HC exposes that operation, fail closed instead of reusing it. }
    if c^.USB^.HC^.HCType = USB_HC_XHCI then clear_halt := false;
end;

procedure recover(c : PMSDevice);
var ok : boolean;
begin
    if c^.Offline then exit;
    ok := control(c, $21, $FF, c^.USB^.InterfaceNumber, 0) = tsSuccess;
    if ok then ok := clear_halt(c, c^.InEP);
    if ok then ok := clear_halt(c, c^.OutEP);
    if not ok then c^.Offline := true;
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

{ 0=passed, 1=SCSI command failed (request sense), 2=transport failure.
  Only one CBW/data/CSW sequence may be in flight on an interface. }
function transport(c : PMSDevice; var transferred : uint32) : uint8;
var status : TUSBTransferStatus;
    actual, offset, count : uint32;
    ep : PUSBEndpoint;
begin
    transport := 2; transferred := 0;
    if c^.CBW.DataLength > BUFFER_SIZE then exit;
    status := bulk(c, c^.OutEP, @c^.CBW, sizeof(TCBW), actual);
    if (status <> tsSuccess) or (actual <> sizeof(TCBW)) then begin recover(c); exit; end;
    if c^.CBW.Flags = $80 then ep := c^.InEP else ep := c^.OutEP;
    offset := 0;
    while offset < c^.CBW.DataLength do begin
        count := c^.CBW.DataLength - offset;
        { One bounded data transfer per command, at most one page of DMA. }
        status := bulk(c, ep, pointer(uint32(c^.Buffer) + offset), count, actual);
        if status = tsStall then begin
            if not clear_halt(c, ep) then begin recover(c); exit; end;
            break;
        end;
        if (status <> tsSuccess) or (actual > count) then begin recover(c); exit; end;
        inc(offset, actual);
        if actual < count then break;
    end;
    transferred := offset;
    memset(uint32(@c^.CSW), 0, sizeof(TCSW));
    status := bulk(c, c^.InEP, @c^.CSW, sizeof(TCSW), actual);
    if status = tsStall then begin
        if clear_halt(c, c^.InEP) then
            status := bulk(c, c^.InEP, @c^.CSW, sizeof(TCSW), actual);
    end;
    if (status <> tsSuccess) or not valid_csw(@c^.CSW, c^.CBW.Tag, c^.CBW.DataLength, actual) then begin
        recover(c); exit;
    end;
    if c^.CSW.Status = 2 then begin recover(c); exit; end;
    if c^.CSW.Status = 1 then begin transport := 1; exit; end;
    if (c^.CSW.Residue <> c^.CBW.DataLength - offset) then begin recover(c); exit; end;
    transport := 0;
end;

function sense(c : PMSDevice) : TError;
var actual : uint32;
begin
    sense := eIOError;
    command(c, $03, 6, 18, true);
    c^.CBW.Command[4] := 18;
    memset(uint32(c^.Buffer), 0, 18);
    if transport(c, actual) <> 0 then exit;
    if actual < 14 then exit;
    if (puint8(c^.Buffer)[0] and $7E) <> $70 then exit;
    case puint8(c^.Buffer)[2] and $0F of
        2: sense := eDeviceNotReady;
        3: sense := eBadSector;
        5: sense := eNotSupported;
        6: sense := eDeviceNotReady;
        7: sense := eReadOnly;
    end;
end;

function execute(c : PMSDevice; required : uint32) : TError;
var actual : uint32; resultCode : uint8;
begin
    resultCode := transport(c, actual);
    execute := eIOError;
    if resultCode = 1 then execute := sense(c)
    else if (resultCode = 0) and (actual = required) then execute := eNone;
    if c^.Offline then execute := eIOTimeout;
    if c^.Original = nil then execute := eDeviceRemoved;
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
    c^.Request := r;
end;

procedure process_request(c : PMSDevice);
var r : PIORequest; offset, blocks, bytes, doneBlocks : uint32;
    error : TError;
begin
    r := c^.Request;
    if r = nil then exit;
    error := eNone; doneBlocks := 0; offset := 0;
    if c^.Offline or (c^.Original = nil) then error := eDeviceRemoved;
    while (doneBlocks < r^.SectorCount) and (error = eNone) do begin
        blocks := r^.SectorCount - doneBlocks;
        if blocks > BUFFER_SIZE div c^.Disk^.sectorSize then
            blocks := BUFFER_SIZE div c^.Disk^.sectorSize;
        bytes := blocks * c^.Disk^.sectorSize;
        if r^.RequestType = ioRead then command(c, $28, 10, bytes, true)
        else begin
            command(c, $2A, 10, bytes, false);
            memcpy(uint32(r^.Buffer) + offset, uint32(c^.Buffer), bytes);
        end;
        put32(@c^.CBW.Command[2], r^.LBA + doneBlocks);
        c^.CBW.Command[7] := blocks shr 8;
        c^.CBW.Command[8] := blocks;
        error := execute(c, bytes);
        if error = eNone then begin
            if r^.RequestType = ioRead then
                memcpy(uint32(c^.Buffer), uint32(r^.Buffer) + offset, bytes);
            inc(doneBlocks, blocks); inc(offset, bytes);
        end;
    end;
    { Complete writes only after the device has committed its cache. }
    if (error = eNone) and (r^.RequestType = ioWrite) then begin
        command(c, $35, 10, 0, false);
        error := execute(c, 0);
    end;
    if error = eReadOnly then c^.Disk^.writable := false;
    r^.ByteCount := offset;
    c^.Request := nil;
    driver.storage.mgr.complete_io(r, error = eNone, error);
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
var c, next, prev, scan : PMSDevice; flags : uint32;
begin
    while true do begin
        c := Devices;
        while c <> nil do begin
            next := c^.Next;
            if c^.Ready then process_request(c);
            if c^.Offline and c^.InFlight and not c^.Attaching then begin
                poll_controller(c);
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
        proc.mgr.proc_sleep_ms(1);
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
        c^.Offline := true; c^.Ready := true; c^.Attaching := false; AttachBusy := false; exit;
    end;
    if not probe(c, sectors, sectorSize) then begin
        c^.Offline := true; c^.Ready := true;
        kfree(void(d));
        c^.Attaching := false; AttachBusy := false;
        io.syslog.logln('USBMSC', 'Probe failed or unsupported disk geometry.');
        exit;
    end;
    memset(uint32(d), 0, sizeof(TStorage_Device));
    d^.volumes := DL_New(sizeof(pointer));
    if d^.volumes = nil then begin
        kfree(void(d)); c^.Offline := true; c^.Ready := true; c^.Attaching := false; AttachBusy := false; exit;
    end;
    d^.controller := ControllerUSB;
    d^.controllerId0 := uint32(c);
    d^.writable := true;
    d^.sectorSize := sectorSize;
    d^.maxSectorCount := sectors;
    d^.maxActive := 1;
    d^.mergeMaxSectors := BUFFER_SIZE div sectorSize;
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
    c^.Attaching := false; AttachBusy := false;
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
    c^.Buffer := kalloc_aligned(BUFFER_SIZE, 4096);
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
        c^.Offline := true; c^.Ready := true; c^.Attaching := false; exit;
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
        Stage, Fault, Controls, DataBytes : uint32;
        GoodWrite, GoodRecovery : boolean;
    end;

function mock_submit(hc : PUSBHCDriver; t : PUSBTransfer) : boolean;
var m : PMock; csw : PCSW; i : uint32;
begin
    m := PMock(hc^.PrivData);
    mock_submit := true;
    t^.Status := tsSuccess; t^.ActualLen := t^.BufferLen;
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
            m^.Stage := 2;
            m^.DataBytes := 0;
            if m^.C.CBW.DataLength <> 0 then m^.Stage := 1;
            if m^.Fault = 6 then begin t^.ActualLen := 30; m^.Stage := 0; end;
        end;
        1: begin
            if m^.C.CBW.Flags = $80 then begin
                memset(uint32(t^.Buffer), $A5, t^.BufferLen);
                case m^.C.CBW.Command[0] of
                    $12: puint8(t^.Buffer)[0] := 0;
                    $25: begin put32(puint8(t^.Buffer), 8191); put32(puint8(uint32(t^.Buffer)+4), 512); end;
                    $03: begin memset(uint32(t^.Buffer),0,t^.BufferLen); puint8(t^.Buffer)[0]:=$70; puint8(t^.Buffer)[2]:=7; end;
                end;
            end else begin
                m^.GoodWrite := true;
                if t^.BufferLen > 0 then for i := 0 to t^.BufferLen-1 do
                    if puint8(t^.Buffer)[i] <> $5A then m^.GoodWrite := false;
            end;
            if m^.Fault = 4 then t^.ActualLen := t^.BufferLen div 2;
            m^.DataBytes := t^.ActualLen;
            m^.Stage := 2;
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

procedure UnitTest;
var passed, failed, actual, sectors, size : uint32; csw : TCSW; bytes : array[0..3] of uint8; m : PMock;
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
        memset(uint32(m), 0, sizeof(TMock));
        m^.HC.fnSubmit := @mock_submit; m^.HC.HCType := USB_HC_EHCI; m^.HC.PrivData := m;
        m^.USB.HC := @m^.HC; m^.USB.InterfaceNumber := 3;
        m^.USB.Endpoints[0].Address := 1; m^.USB.Endpoints[0].Direction := dirIn;
        m^.USB.Endpoints[1].Address := 2; m^.USB.Endpoints[1].Direction := dirOut;
        m^.USB.Endpoints[0].MaxPacket := 512; m^.USB.Endpoints[1].MaxPacket := 512;
        m^.C.USB := @m^.USB; m^.C.Original := @m^.USB;
        m^.C.InEP := @m^.USB.Endpoints[0]; m^.C.OutEP := @m^.USB.Endpoints[1];
        m^.C.Buffer := kalloc_aligned(BUFFER_SIZE, 4096);
        Assert(m^.C.Buffer <> nil, 'mock DMA scratch allocation');
        if m^.C.Buffer <> nil then begin
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
    id.Bus := biUSB; id.id0 := idANY; id.id1 := $FFFFFFFF;
    id.id2 := $08; id.id3 := $06; id.id4 := $50; id.ex := nil;
    driver.mgr.register_driver('USB Mass Storage', @id, @load);
end;

initialization
    boot.mgr.registerBoot('driver.storage.ctl.usb', @init, 'USB Mass Storage Driver', BOOT_MGR_BARRIER_DEVICE);
end.
