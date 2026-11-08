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

{
    Driver->Storage->StorageManager - Physical storage device registry + I/O dispatch.

    Manages registration of physical storage devices (driver.storage.ctl.ahci, driver.storage.ctl.ide, driver.bus.usb, etc.)
    and provides the submit_io / complete_io request-based I/O path.
    Device drivers call register_device() when they discover a new device.

    Request-based I/O model:
    - submit_io enqueues a TIORequest into the device's per-device CFIFO,
      dispatches to hardware, and returns without waiting for completion.
    - complete_io delivers callbacks from the driver's completion context.
    - storage_read / storage_write are thin wrappers that build a stack-local
      TIORequest, call submit_io_wait, and return the resulting TError.
    - Drivers must provide the TDriverDispatch interface; there is no legacy
      callback fallback.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit driver.storage.mgr;

interface

uses
    arch.platform.process,
    core.ds.cfifo,
    core.ds.types,
    driver.storage.iorequest,
    core.ds.lists,
    memory.heap,
    driver.storage.vol.mbr,
    proc.mgr,
    proc.types,
    driver.storage.types,
    io.syslog,
    debug.tracer,
    core.util, arch.platform.cpu;

var
    storageDevices : PDList;
    nextDeviceId   : uint32;

{ BIOS drive byte from arch.x86.multiboot — set once during core.version init before any
  device drivers run.  $80=first HDD, $81=second HDD, $9F/other=CD-ROM. }
    bootDriveByte  : uint8;
    hdCount        : uint32;    { non-ATAPI devices registered so far }
    atapiCount     : uint32;    { ATAPI devices registered so far }

procedure storage_get_stats(device : PStorage_Device; var stats : TStorageStats);
procedure init();
procedure set_boot_drive_byte(driveByte : uint8);
function  get_boot_drive_byte() : uint8;
procedure register_device(device : PStorage_Device);
function get_device_list() : PDList;
function get_device_count() : uint32;
function get_device(index : uint32) : PStorage_Device;
function controller_type_2_string(controllerType : TControllerType) : pchar;
function read_mbr(device : PStorage_Device) : PMaster_Boot_Record;
function write_mbr(device : PStorage_Device; mbr : PMaster_Boot_Record) : TError;

{ Return pointer to cached mbr data (nil if not cached).
  Caller must NOT free the returned pointer. }
function get_cached_mbr(device : PStorage_Device) : PMaster_Boot_Record;

{ Async mbr write — updates cache and issues non-blocking write.
  Callback fires from ISR context when write completes. }
procedure write_mbr_async(device : PStorage_Device; mbr : PMaster_Boot_Record;
                          callback : TIOCallback; callbackData : pointer);

{ === I/O dispatch API === }

{ Non-blocking: enqueue request into the device CFIFO and dispatch.
  Returns eNone if the request was successfully enqueued.
  Completion will arrive via the request's Callback (async) or by
  waking request^.Caller (blocking).  Caller must set up Callback or
  Caller/UserData BEFORE calling this. }
function submit_io(request : PIORequest) : TError;

{ Blocking wrapper: sets up caller context, calls submit_io, then
  hlt-loops until complete_io wakes us.  MUST only be called from
  normal task context (interrupts enabled). }
function submit_io_wait(request : PIORequest) : TError;

{ Called from ISR / completion context to finalise a request.
  Invokes Callback if set (async path) and/or wakes Caller (blocking path). }
procedure complete_io(request : PIORequest; success : boolean; error : TError);

{ Blocking I/O helpers — task context only.
  Build a TIORequest, submit_io_wait, return error. }
function storage_read(device : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32) : TError;
function storage_write(device : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32) : TError;

{ Async I/O helpers — safe from any context (ISR or task).
  Enqueue I/O request and return immediately.  Callback fires from
  ISR context when the operation completes. }
function storage_read_async(device : PStorage_Device; addr : uint32; sectors : uint32;
                            buffer : puint32; callback : TIOCallback; callbackData : pointer) : TError;
function storage_write_async(device : PStorage_Device; addr : uint32; sectors : uint32;
                             buffer : puint32; callback : TIOCallback; callbackData : pointer) : TError;

implementation

uses
    driver.storage.vol.mgr;

{ Internal: dequeue head of device queue and dispatch to driver hardware }
procedure dispatch_next(device : PStorage_Device); forward;

type
    PDeviceSlot = ^PStorage_Device;
    PRequestSlot = ^PIORequest;
    { Used by submit_io_wait: callback writes result here then sets Done=1.
      Process is parked in psAwaiting while Done=0; ISR sets psReady + Done=1.
      Done is read through a pointer so FPC cannot cache it (Lesson #6). }
    TSyncWaitData = record
        Done    : uint32;         { 0 = in flight, 1 = complete }
        Error   : TError;
        Process : PProcessContext; { process to wake from ISR context }
    end;
    PSyncWaitData = ^TSyncWaitData;

    { Async MBR-write wrapper. Keeps a sector-sized DMA buffer alive until the
      hardware completion fires, then frees it before forwarding the user's callback. }
    TMBRWriteAsyncData = record
        Buffer       : pointer;
        Device       : PStorage_Device;
        UserCallback : TIOCallback;
        UserData     : pointer;
    end;
    PMBRWriteAsyncData = ^TMBRWriteAsyncData;

{ Callback fired from ISR context by complete_io.
  Sets the error, wakes the parked process, then sets Done=1 so the
  pointer-dereferenced spin in submit_io_wait can exit.  Safe with IF=0. }
procedure sync_io_callback(error : TError; userdata : pointer);
var
    wait : PSyncWaitData;
begin
    if userdata = nil then exit;
    wait := PSyncWaitData(userdata);
    wait^.Error := error;
    if wait^.Process <> nil then
        wait^.Process^.State := psReady;
    { Write Done last — submit_io_wait spins on this and must see State=psReady
      before it exits the loop (ISR ordering on x86 is program order). }
    puint32(@wait^.Done)^ := 1;
end;

function alloc_mbr_io_buffer(device : PStorage_Device; mbr : PMaster_Boot_Record) : puint32;
var
    bufSz : uint32;
    buf   : puint32;
begin
    alloc_mbr_io_buffer := nil;
    if (device = nil) or (mbr = nil) then exit;

    bufSz := device^.sectorSize;
    if bufSz < sizeof(TMaster_Boot_Record) then
        bufSz := sizeof(TMaster_Boot_Record);

    buf := puint32(kalloc(bufSz));
    if buf = nil then exit;

    memset(PtrUInt(buf), 0, bufSz);
    memcpy(PtrUInt(mbr), PtrUInt(buf), sizeof(TMaster_Boot_Record));
    alloc_mbr_io_buffer := buf;
end;

function claim_mbr(device : PStorage_Device) : boolean;
var
    irqFlags: PtrUInt;
    flags : uint32;
begin
    irqFlags := arch.platform.cpu.lock;
    claim_mbr := not device^.mbrWriteBusy;
    if claim_mbr then device^.mbrWriteBusy := true;
    arch.platform.cpu.unlock(irqFlags);
end;

procedure publish_mbr(device : PStorage_Device; buffer : pointer);
var old : pointer;
begin
    { The DMA buffer becomes the cache only after a successful write. }
    old := device^.cachedMBR;
    device^.cachedMBR := buffer;
    if old <> nil then kfree(old);
end;

procedure mbr_write_async_callback(error : TError; userdata : pointer);
var ctx : PMBRWriteAsyncData;
begin
    ctx := PMBRWriteAsyncData(userdata);
    if ctx = nil then exit;
    if error = eNone then publish_mbr(ctx^.Device, ctx^.Buffer)
    else kfree(ctx^.Buffer);
    ctx^.Device^.mbrWriteBusy := false;
    if ctx^.UserCallback <> nil then ctx^.UserCallback(error, ctx^.UserData);
    kfree(void(ctx));
end;

procedure storage_get_stats(device : PStorage_Device; var stats : TStorageStats);
var
    savedIRQ: PtrUInt;
begin
    savedIRQ := arch.platform.cpu.lock;
    if device <> nil then stats := device^.Stats
    else memset(PtrUInt(@stats),0,sizeof(stats));
    arch.platform.cpu.unlock(savedIRQ);
end;

procedure init();
begin
    push_trace('driver.storage.mgr.init');
    storageDevices := DL_New(sizeof(PStorage_Device));
    nextDeviceId   := 0;
    bootDriveByte  := $FF;  { $FF = unknown/uninitialised }
    hdCount        := 0;
    atapiCount     := 0;
end;

procedure set_boot_drive_byte(driveByte : uint8);
begin
    bootDriveByte := driveByte;
    io.syslog.log('STRMGR', 'Boot drive BIOS byte = 0x');
    io.syslog.writehexln(driveByte);
end;

function get_boot_drive_byte() : uint8;
begin
    get_boot_drive_byte := bootDriveByte;
end;

procedure register_device(device : PStorage_Device);
var
    storedDev : PStorage_Device;
    slot : PDeviceSlot;
    irqFlags : PtrUInt;
begin
    push_trace('driver.storage.mgr.register_device');
    if device = nil then exit;
    storedDev := PStorage_Device(kalloc(sizeof(TStorage_Device)));
    if storedDev = nil then exit;
    memcpy(PtrUInt(device), PtrUInt(storedDev), sizeof(TStorage_Device));
    device := storedDev;

    { Initialise new Phase 2 fields }
    device^.removed := false;
    device^.requestQueue := CFIFO_New(SizeOf(PIORequest), 128);
    if device^.requestQueue = nil then begin
        kfree(void(device));
        exit;
    end;
    memset(PtrUInt(@device^.Stats),0,sizeof(TStorageStats));
    device^.activeCount := 0;
    device^.dispatching := false;
    if device^.maxActive = 0 then device^.maxActive := 1;
    device^.cachedMBR := nil;
    device^.metadataBusy := false;
    device^.mbrWriteBusy := false;
    device^.isBootDevice := false;
    { dispatchRead/dispatchWrite: left as-is — driver sets them before
      calling register_device. memset(0) guarantees nil for unmigrated drivers. }

    { Volumes and queued requests retain this address across registry growth. }
    irqFlags := arch.platform.cpu.lock;
    slot := PDeviceSlot(DL_Add(storageDevices));
    if slot <> nil then begin
        storedDev^.id := nextDeviceId;
        inc(nextDeviceId);
        slot^ := storedDev;
    end;
    arch.platform.cpu.unlock(irqFlags);
    if slot = nil then begin
        CFIFO_Free(device^.requestQueue);
        kfree(void(device));
        exit;
    end;

    { Identify whether this is the boot device using the BIOS drive byte.
      BIOS numbers HDDs from $80 upward; the nth HDD is $80 + (n-1).
      ATAPI/CD-ROM devices are NOT in the $80-range HDD sequence, so if
      bootDriveByte does not match any HDD we have seen, the first ATAPI
      device is marked as the boot device (covers standard ISO boot). }
    if (storedDev^.controller = ControllerATAPI) or
       (storedDev^.controller = ControllerAHCI_ATAPI) then begin
        { ATAPI device: boot if the drive byte is outside the known HDD range }
        if bootDriveByte < ($80 + hdCount) then begin
            { drive byte refers to an HDD — this ATAPI is not the boot device }
        end else if atapiCount = 0 then begin
            { first ATAPI and boot byte is not a known HDD → this is the boot drive }
            storedDev^.isBootDevice := true;
            io.syslog.logln('STRMGR', 'Boot device identified (ATAPI/ISO).');
        end;
        atapiCount := atapiCount + 1;
    end else begin
        { Non-ATAPI (HDD): boot if BIOS drive byte matches $80 + index }
        if bootDriveByte = ($80 + hdCount) then begin
            storedDev^.isBootDevice := true;
            io.syslog.logln('STRMGR', 'Boot device identified (HDD).');
        end;
        hdCount := hdCount + 1;
    end;

    { Discover partitions and register volumes automatically }
    if storedDev^.maxSectorCount > 0 then
        driver.storage.vol.mgr.discover_volumes(storedDev);
end;

function get_device_list() : PDList;
begin
    get_device_list := storageDevices;
end;

function get_device_count() : uint32;
begin
    get_device_count := DL_Size(storageDevices);
end;

function get_device(index : uint32) : PStorage_Device;
var
    irqFlags : PtrUInt;
begin
    irqFlags := arch.platform.cpu.lock;
    if index < DL_Size(storageDevices) then
        get_device := PDeviceSlot(DL_Get(storageDevices, index))^
    else
        get_device := nil;
    arch.platform.cpu.unlock(irqFlags);
end;

function controller_type_2_string(controllerType : TControllerType) : pchar;
begin
    case controllerType of
        ControllerATA:          controller_type_2_string := 'ATA';
        ControllerATAPI:        controller_type_2_string := 'ATAPI';
        ControllerUSB:          controller_type_2_string := 'USB';
        ControllerAHCI:         controller_type_2_string := 'AHCI';
        ControllerAHCI_ATAPI:   controller_type_2_string := 'AHCI_ATAPI';
        ControllerNVMe:         controller_type_2_string := 'NVMe';
        ControllerNET:          controller_type_2_string := 'NET';
        ControllerRAM:          controller_type_2_string := 'RAM';
        ControllerSCSI:         controller_type_2_string := 'SCSI';
    end;
end;

function read_mbr(device : PStorage_Device) : PMaster_Boot_Record;
var
    err    : TError;
    bufSz  : uint32;
    buf    : puint32;
    cache  : puint32;
begin
    push_trace('driver.storage.mgr.read_mbr');
    { Allocate at least one full sector so DMA does not overrun
      the buffer on devices with large sectors (e.g. 2048-byte ATAPI). }
    bufSz := device^.sectorSize;
    if bufSz < sizeof(TMaster_Boot_Record) then
        bufSz := sizeof(TMaster_Boot_Record);
    buf := puint32(kalloc(bufSz));
    read_mbr := PMaster_Boot_Record(buf);
    err := storage_read(device, 0, 1, buf);
    if err <> eNone then begin
        kfree(void(buf));
        read_mbr := nil;
    end else begin
        { Update cache with a copy }
        if device^.cachedMBR <> nil then
            kfree(device^.cachedMBR);
        cache := puint32(kalloc(sizeof(TMaster_Boot_Record)));
        if cache <> nil then
            memcpy(PtrUInt(buf), PtrUInt(cache), sizeof(TMaster_Boot_Record));
        device^.cachedMBR := pointer(cache);
    end;
end;

function write_mbr(device : PStorage_Device; mbr : PMaster_Boot_Record) : TError;
var buf : puint32;
begin
    write_mbr := eInvalidArgument;
    if (device = nil) or (mbr = nil) then exit;
    if not device^.writable then begin write_mbr := eReadOnly; exit; end;
    if not claim_mbr(device) then begin write_mbr := eFileInUse; exit; end;
    { Snapshot first: mbr may alias device^.cachedMBR. }
    buf := alloc_mbr_io_buffer(device, mbr);
    if buf = nil then write_mbr := eOutOfMemory
    else begin
        write_mbr := storage_write(device, 0, 1, buf);
        if write_mbr = eNone then publish_mbr(device, buf) else kfree(buf);
    end;
    device^.mbrWriteBusy := false;
end;

function get_cached_mbr(device : PStorage_Device) : PMaster_Boot_Record;
begin
    if device = nil then begin get_cached_mbr := nil; exit; end;
    get_cached_mbr := PMaster_Boot_Record(device^.cachedMBR);
end;

procedure write_mbr_async(device : PStorage_Device; mbr : PMaster_Boot_Record;
                          callback : TIOCallback; callbackData : pointer);
var ctx : PMBRWriteAsyncData; buf : puint32; err : TError;
begin
    err := eNone;
    if (device = nil) or (mbr = nil) then err := eInvalidArgument
    else if not device^.writable then err := eReadOnly
    else if not claim_mbr(device) then err := eFileInUse;
    if err <> eNone then begin
        if callback <> nil then callback(err, callbackData);
        exit;
    end;
    buf := alloc_mbr_io_buffer(device, mbr);
    if buf = nil then begin
        device^.mbrWriteBusy := false;
        if callback <> nil then callback(eOutOfMemory, callbackData);
        exit;
    end;
    ctx := PMBRWriteAsyncData(kalloc(sizeof(TMBRWriteAsyncData)));
    if ctx = nil then begin
        kfree(buf); device^.mbrWriteBusy := false;
        if callback <> nil then callback(eOutOfMemory, callbackData);
        exit;
    end;
    ctx^.Buffer := buf; ctx^.Device := device;
    ctx^.UserCallback := callback; ctx^.UserData := callbackData;
    err := storage_write_async(device, 0, 1, buf, @mbr_write_async_callback, ctx);
    if err <> eNone then mbr_write_async_callback(err, ctx);
end;

{ ========================================================================== }
{                    Phase 2: Request-Based I/O Path                         }
{ ========================================================================== }

{ Internal: dequeue head of device queue and dispatch to hardware.
  Called with interrupts disabled (CLI context) or from ISR context. }
procedure dispatch_next(device : PStorage_Device);
var
    heapReq, nextReq, tail : PIORequest;
    peek : pointer;
    merged, bytes, ticks : uint32;
begin
    if device^.dispatching then exit;
    device^.dispatching := true;
    { Dispatch queued requests up to maxActive hardware slots }
    while device^.activeCount < device^.maxActive do begin
        if not CFIFO_Dequeue(device^.requestQueue, @heapReq) then break;  { queue empty }
        if heapReq = nil then
            break;

        { Merge only consecutive FIFO entries with consecutive DMA buffers.
          Bound both command size and completion fan-out; never reorder writes. }
        tail := heapReq; merged := 1;
        while (merged < 32) and (device^.mergeMaxSectors > 0) and
              (device^.sectorSize > 0) do begin
            peek := CFIFO_Peek(device^.requestQueue);
            if peek = nil then break;
            nextReq := PRequestSlot(peek)^;
            if nextReq = nil then break;
            if (nextReq^.Device <> device) or (nextReq^.RequestType <> heapReq^.RequestType) then break;
            if heapReq^.SectorCount > device^.mergeMaxSectors then break;
            if nextReq^.SectorCount > device^.mergeMaxSectors-heapReq^.SectorCount then break;
            if heapReq^.SectorCount > ($FFFFFFFF div device^.sectorSize) then break;
            bytes := heapReq^.SectorCount*device^.sectorSize;
            if (heapReq^.LBA > $FFFFFFFF-heapReq^.SectorCount) or
               (PtrUInt(heapReq^.Buffer) > High(PtrUInt)-bytes) then break;
            if (nextReq^.LBA <> heapReq^.LBA+heapReq^.SectorCount) or
               (PtrUInt(nextReq^.Buffer) <> PtrUInt(heapReq^.Buffer)+bytes) then break;
            if not CFIFO_Dequeue(device^.requestQueue,@nextReq) then break;
            tail^.MergeNext := nextReq; tail := nextReq;
            Inc(heapReq^.SectorCount,nextReq^.SectorCount); Inc(merged);
            Inc(device^.Stats.Merged);
        end;
        ticks := arch.platform.process.timerTicks;
        tail := heapReq;
        while tail <> nil do begin
            tail^.DispatchTick := ticks; tail^.State := iosDispatched;
            bytes := ticks-tail^.QueuedTick;
            Inc(device^.Stats.QueueTicks,bytes);
            if bytes > device^.Stats.MaxQueueTicks then device^.Stats.MaxQueueTicks := bytes;
            tail := tail^.MergeNext;
        end;
        Inc(device^.Stats.Commands);
        device^.activeCount := device^.activeCount + 1;
        if device^.activeCount > device^.Stats.ActivePeak then device^.Stats.ActivePeak := device^.activeCount;

        case heapReq^.RequestType of
            ioRead: begin
                if device^.dispatchRead <> nil then
                    device^.dispatchRead(device, heapReq)
                else begin
                    complete_io(heapReq, false, eDeviceNotFound);
                end;
            end;
            ioWrite: begin
                if device^.dispatchWrite <> nil then
                    device^.dispatchWrite(device, heapReq)
                else
                    complete_io(heapReq, false, eDeviceNotFound);
            end;
        end;
    end;
    device^.dispatching := false;
end;

function submit_io(request : PIORequest) : TError;
var
    irqFlags: PtrUInt;

    device  : PStorage_Device;
    heapReq : PIORequest;
    flags : uint32;
begin
    { Pre-checks — fail fast before touching the queue }
    if request = nil then begin submit_io := eInvalidArgument; exit; end;
    if request^.Device = nil then begin submit_io := eDeviceNotFound; exit; end;
    if request^.Buffer = nil then begin submit_io := eInvalidArgument; exit; end;
    if request^.SectorCount = 0 then begin submit_io := eInvalidArgument; exit; end;

    device := request^.Device;
    if device^.removed then begin submit_io := eDeviceRemoved; exit; end;

    { Device must have dispatch interface }
    if (device^.dispatchRead = nil) and (device^.dispatchWrite = nil) then begin
        submit_io := eDeviceNotFound;
        exit;
    end;

    request^.State := iosPending;
    request^.Error := eNone;

    { Copy once into the pooled request arena so the driver/ISR path never
      depends on a caller-owned stack record. The queue stores pointers to
      these owned requests; complete_io returns them to the pool. }
    heapReq := ioreq_copy(request);
    if heapReq = nil then begin
        submit_io := eOutOfMemory;
        exit;
    end;

    { Enqueue and attempt dispatch — must be ISR-safe and bounded.
      Reject once the fixed queue is full instead of growing with CLI held. }
    irqFlags := arch.platform.cpu.lock;
    if CFIFO_Size(device^.requestQueue) >= CFIFO_Capacity(device^.requestQueue) then begin
        Inc(device^.Stats.QueueFull);
        arch.platform.cpu.unlock(irqFlags);
        ioreq_free(heapReq);
        submit_io := eQueueFull;
        exit;
    end;
    heapReq^.QueuedTick := arch.platform.process.timerTicks;
    Inc(device^.Stats.Submitted);
    if request^.SectorCount <= 8 then Inc(device^.Stats.SmallRequests)
    else if request^.SectorCount <= 256 then Inc(device^.Stats.MediumRequests)
    else Inc(device^.Stats.LargeRequests);
    CFIFO_Enqueue(device^.requestQueue, @heapReq);
    if CFIFO_Size(device^.requestQueue) > device^.Stats.QueuePeak then
        device^.Stats.QueuePeak := CFIFO_Size(device^.requestQueue);
    dispatch_next(device);
    arch.platform.cpu.unlock(irqFlags);

    submit_io := eNone;
end;

{ Blocking wrapper — submit the request then park the calling process until
  the driver.storage.ctl.ahci ISR fires the completion callback.

  The process is placed in psAwaiting so the scheduler skips it entirely.
  sync_io_callback sets State := psReady then Done := 1.  We spin on Done
  through a pointer (Lesson #6 — prevents FPC from caching the value in a
  register across the hlt instruction). }
function submit_io_wait(request : PIORequest) : TError;
var
    savedIRQ: PtrUInt;

    wait : TSyncWaitData;
    err  : TError;
begin
    wait.Done    := 0;
    wait.Error   := eNone;
    wait.Process := CurrentProcess;

    request^.Callback     := @sync_io_callback;
    request^.CallbackData := @wait;
    request^.Caller       := nil;
    request^.UserData     := nil;

    err := submit_io(request);
    if err <> eNone then begin
        submit_io_wait := err;
        exit;
    end;

    { Race-free park: disable interrupts while checking Done and setting
      psAwaiting so the callback cannot fire in the narrow window between
      the Done=0 check and the state write — which would otherwise lose
      the wake signal and leave the process parked forever. }
    savedIRQ := arch.platform.cpu.lock;
    if puint32(@wait.Done)^ = 0 then begin
        if CurrentProcess <> nil then
            CurrentProcess^.State := psAwaiting;
    end;
    arch.platform.cpu.unlock(savedIRQ);

    { Spin on Done via pointer — mandatory per Lesson #6.  FPC would cache
      the value in a register without the indirection, causing an infinite
      loop even after the ISR sets Done=1.  HLT yields the CPU each iteration
      so we do not burn cycles; the next interrupt (driver.storage.ctl.ahci or timer) wakes us. }
    while puint32(@wait.Done)^ = 0 do
        arch.platform.cpu.idle;

    submit_io_wait := wait.Error;
end;

procedure complete_io(request : PIORequest; success : boolean; error : TError);
var
    irqFlags: PtrUInt;
    device : PStorage_Device; next : PIORequest; ticks, flags : uint32;
    wasDispatching : boolean;
begin
    if request = nil then exit;
    device := request^.Device;
    irqFlags := arch.platform.cpu.lock;
    wasDispatching := false;
    if device <> nil then begin
        wasDispatching := device^.dispatching;
        device^.dispatching := true; { callbacks cannot dispatch inside merged fan-out }
        if device^.activeCount > 0 then Dec(device^.activeCount);
        ticks := arch.platform.process.timerTicks-request^.DispatchTick;
        Inc(device^.Stats.ServiceTicks,ticks);
        if ticks > device^.Stats.MaxServiceTicks then device^.Stats.MaxServiceTicks := ticks;
    end;
    while request <> nil do begin
        next := request^.MergeNext;
        if success then begin request^.State := iosComplete; request^.Error := eNone; end
        else begin request^.State := iosError; request^.Error := error; end;
        if device <> nil then begin
            Inc(device^.Stats.Completed);
            if not success then Inc(device^.Stats.Failed)
            else if request^.RequestType = ioRead then Inc(device^.Stats.ReadSectors,request^.OriginalSectors)
            else Inc(device^.Stats.WriteSectors,request^.OriginalSectors);
        end;
        if request^.Callback <> nil then request^.Callback(request^.Error,request^.CallbackData);
        ioreq_free(request); request := next;
    end;
    if device <> nil then begin
        device^.dispatching := wasDispatching;
        dispatch_next(device);
    end;
    arch.platform.cpu.unlock(irqFlags);
end;

{ ========================================================================== }
{                     Public storage_read / storage_write                    }
{ ========================================================================== }

{ Blocking — task context only }
function storage_read(device : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32) : TError;
var
    req : TIORequest;
begin
    if device = nil then begin storage_read := eDeviceNotFound; exit; end;
    if buffer = nil then begin storage_read := eInvalidArgument; exit; end;
    if sectors = 0 then begin storage_read := eInvalidArgument; exit; end;

    req.RequestType  := ioRead;
    req.State        := iosPending;
    req.Device       := device;
    req.LBA          := addr;
    req.SectorCount  := sectors;
    req.Buffer       := pointer(buffer);
    req.ByteCount    := 0;
    req.Error        := eNone;
    req.Caller       := nil;
    req.UserData     := nil;
    req.Callback     := nil;
    req.CallbackData := nil;

    storage_read := submit_io_wait(@req);
end;

{ Blocking — task context only }
function storage_write(device : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32) : TError;
var
    req : TIORequest;
begin
    if device = nil then begin storage_write := eDeviceNotFound; exit; end;
    if buffer = nil then begin storage_write := eInvalidArgument; exit; end;
    if sectors = 0 then begin storage_write := eInvalidArgument; exit; end;

    req.RequestType  := ioWrite;
    req.State        := iosPending;
    req.Device       := device;
    req.LBA          := addr;
    req.SectorCount  := sectors;
    req.Buffer       := pointer(buffer);
    req.ByteCount    := 0;
    req.Error        := eNone;
    req.Caller       := nil;
    req.UserData     := nil;
    req.Callback     := nil;
    req.CallbackData := nil;

    storage_write := submit_io_wait(@req);
end;

{ ========================================================================== }
{                   Async storage_read / storage_write                       }
{ ========================================================================== }

{ Non-blocking — safe from ISR or task context.  Callback fires from ISR. }
function storage_read_async(device : PStorage_Device; addr : uint32; sectors : uint32;
                            buffer : puint32; callback : TIOCallback; callbackData : pointer) : TError;
var
    req : TIORequest;
begin
    if device = nil then begin storage_read_async := eDeviceNotFound; exit; end;
    if buffer = nil then begin storage_read_async := eInvalidArgument; exit; end;
    if sectors = 0 then begin storage_read_async := eInvalidArgument; exit; end;

    req.RequestType  := ioRead;
    req.State        := iosPending;
    req.Device       := device;
    req.LBA          := addr;
    req.SectorCount  := sectors;
    req.Buffer       := pointer(buffer);
    req.ByteCount    := 0;
    req.Error        := eNone;
    req.Caller       := nil;
    req.UserData     := nil;
    req.Callback     := callback;
    req.CallbackData := callbackData;

    storage_read_async := submit_io(@req);
end;

{ Non-blocking — safe from ISR or task context.  Callback fires from ISR. }
function storage_write_async(device : PStorage_Device; addr : uint32; sectors : uint32;
                             buffer : puint32; callback : TIOCallback; callbackData : pointer) : TError;
var
    req : TIORequest;
begin
    if device = nil then begin storage_write_async := eDeviceNotFound; exit; end;
    if buffer = nil then begin storage_write_async := eInvalidArgument; exit; end;
    if sectors = 0 then begin storage_write_async := eInvalidArgument; exit; end;

    req.RequestType  := ioWrite;
    req.State        := iosPending;
    req.Device       := device;
    req.LBA          := addr;
    req.SectorCount  := sectors;
    req.Buffer       := pointer(buffer);
    req.ByteCount    := 0;
    req.Error        := eNone;
    req.Caller       := nil;
    req.UserData     := nil;
    req.Callback     := callback;
    req.CallbackData := callbackData;

    storage_write_async := submit_io(@req);
end;

end.
