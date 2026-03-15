//  Copyright 2021 Aaron Hance  
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

    Phase 2 I/O model:
    - submit_io enqueues a TIORequest into the device's per-device CFIFO,
      dispatches to hardware, and sleeps the calling task (proc_await).
    - complete_io is called from ISR/completion context, wakes the caller.
    - storage_read / storage_write are thin wrappers that build a stack-local
      TIORequest, call submit_io, and return the resulting TError.
    - Legacy sync/async callbacks are still supported as fallback for drivers
      not yet migrated to the TDriverDispatch interface.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit driver.storage.mgr;

interface

uses
    boot.mgr,
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
    core.util, arch.x86.util;

var
    storageDevices : PDList;
    nextDeviceId   : uint32;

{ BIOS drive byte from arch.x86.multiboot — set once during core.version init before any
  device drivers run.  $80=first HDD, $81=second HDD, $9F/other=CD-ROM. }
    bootDriveByte  : uint8;
    hdCount        : uint32;    { non-ATAPI devices registered so far }
    atapiCount     : uint32;    { ATAPI devices registered so far }

procedure init();
procedure set_boot_drive_byte(driveByte : uint8);
function  get_boot_drive_byte() : uint8;
procedure register_device(device : PStorage_Device);
function get_device_list() : PDList;
function get_device_count() : uint32;
function get_device(index : uint32) : PStorage_Device;
function controller_type_2_string(controllerType : TControllerType) : pchar;
function read_mbr(device : PStorage_Device) : PMaster_Boot_Record;
procedure write_mbr(device : PStorage_Device; mbr : PMaster_Boot_Record);

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

{ Legacy wrappers — procedure signatures matching the old API.
  Forward to the new functions, silently discard errors.
  TODO: migrate all callers and remove these. }
procedure storage_read_legacy(device : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32);
procedure storage_write_legacy(device : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32);

implementation

uses
    driver.storage.vol.mgr;

{ Internal: dequeue head of device queue and dispatch to driver hardware }
procedure dispatch_next(device : PStorage_Device); forward;

type
    { Used by submit_io_wait: callback writes result here then sets Done=1.
      Process is parked in psAwaiting while Done=0; ISR sets psReady + Done=1.
      Done is read through a pointer so FPC cannot cache it (Lesson #6). }
    TSyncWaitData = record
        Done    : uint32;         { 0 = in flight, 1 = complete }
        Error   : TError;
        Process : PProcessContext; { process to wake from ISR context }
    end;
    PSyncWaitData = ^TSyncWaitData;

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

procedure init();
begin
    push_trace('driver.storage.mgr.init');
    storageDevices := DL_New(sizeof(TStorage_Device));
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
begin
    push_trace('driver.storage.mgr.register_device');
    device^.id := nextDeviceId;
    nextDeviceId := nextDeviceId + 1;

    { Initialise new Phase 2 fields }
    device^.removed := false;
    device^.requestQueue := CFIFO_New(SizeOf(TIORequest), 32);
    device^.activeCount := 0;
    if device^.maxActive = 0 then device^.maxActive := 1;
    device^.cachedMBR := nil;
    device^.isBootDevice := false;
    { dispatchRead/dispatchWrite: left as-is — driver sets them before
      calling register_device. memset(0) guarantees nil for unmigrated drivers. }

    DL_Add(storageDevices);
    DL_Set(storageDevices, DL_Size(storageDevices) - 1, puint32(device));

    { Get pointer to the DList copy so volumes reference the canonical device }
    storedDev := PStorage_Device(DL_Get(storageDevices, DL_Size(storageDevices) - 1));

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
begin
    if index < DL_Size(storageDevices) then
        get_device := PStorage_Device(DL_Get(storageDevices, index))
    else
        get_device := nil;
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
            memcpy(uint32(buf), uint32(cache), sizeof(TMaster_Boot_Record));
        device^.cachedMBR := pointer(cache);
    end;
end;

procedure write_mbr(device : PStorage_Device; mbr : PMaster_Boot_Record);
var
    cache : puint32;
begin
    push_trace('driver.storage.mgr.write_mbr');
    if not device^.writable then exit;
    { Update cache }
    if device^.cachedMBR <> nil then
        kfree(device^.cachedMBR);
    cache := puint32(kalloc(sizeof(TMaster_Boot_Record)));
    if cache <> nil then
        memcpy(uint32(mbr), uint32(cache), sizeof(TMaster_Boot_Record));
    device^.cachedMBR := pointer(cache);
    storage_write(device, 0, 1, puint32(mbr));
end;

function get_cached_mbr(device : PStorage_Device) : PMaster_Boot_Record;
begin
    if device = nil then begin get_cached_mbr := nil; exit; end;
    get_cached_mbr := PMaster_Boot_Record(device^.cachedMBR);
end;

procedure write_mbr_async(device : PStorage_Device; mbr : PMaster_Boot_Record;
                          callback : TIOCallback; callbackData : pointer);
var
    cache : puint32;
begin
    push_trace('driver.storage.mgr.write_mbr_async');
    if not device^.writable then begin
        if callback <> nil then callback(eReadOnly, callbackData);
        exit;
    end;
    { Update cache }
    if device^.cachedMBR <> nil then
        kfree(device^.cachedMBR);
    cache := puint32(kalloc(sizeof(TMaster_Boot_Record)));
    if cache <> nil then
        memcpy(uint32(mbr), uint32(cache), sizeof(TMaster_Boot_Record));
    device^.cachedMBR := pointer(cache);
    storage_write_async(device, 0, 1, puint32(mbr), callback, callbackData);
end;

{ ========================================================================== }
{                    Phase 2: Request-Based I/O Path                         }
{ ========================================================================== }

{ Internal: dequeue head of device queue and dispatch to hardware.
  Called with interrupts disabled (CLI context) or from ISR context. }
procedure dispatch_next(device : PStorage_Device);
var
    reqBuf  : TIORequest;
    heapReq : PIORequest;
begin
    { Dispatch queued requests up to maxActive hardware slots }
    while device^.activeCount < device^.maxActive do begin
        if not CFIFO_Dequeue(device^.requestQueue, @reqBuf) then break;  { queue empty }

        { Heap copy for ISR safety — driver completion may fire on any stack }
        heapReq := ioreq_copy(@reqBuf);
        if heapReq = nil then begin
        { Out of memory — notify caller via callback }
            if reqBuf.Callback <> nil then
                reqBuf.Callback(eOutOfMemory, reqBuf.CallbackData);
            break;
        end;

        device^.activeCount := device^.activeCount + 1;
        heapReq^.State := iosDispatched;

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
end;

function submit_io(request : PIORequest) : TError;
var
    device : PStorage_Device;
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

    { Enqueue and attempt dispatch — must be ISR-safe }
    asm pushf; cli end;
    CFIFO_Enqueue(device^.requestQueue, @request^);
    dispatch_next(device);
    asm popf end;

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
    asm pushf; cli end;
    if puint32(@wait.Done)^ = 0 then begin
        if CurrentProcess <> nil then
            CurrentProcess^.State := psAwaiting;
    end;
    asm popf end;

    { Spin on Done via pointer — mandatory per Lesson #6.  FPC would cache
      the value in a register without the indirection, causing an infinite
      loop even after the ISR sets Done=1.  HLT yields the CPU each iteration
      so we do not burn cycles; the next interrupt (driver.storage.ctl.ahci or timer) wakes us. }
    while puint32(@wait.Done)^ = 0 do
        asm hlt end;

    submit_io_wait := wait.Error;
end;

procedure complete_io(request : PIORequest; success : boolean; error : TError);
var
    device : PStorage_Device;
begin
    if request = nil then exit;

    device := request^.Device;

    if success then begin
        request^.State := iosComplete;
        request^.Error := eNone;
    end else begin
        request^.State := iosError;
        request^.Error := error;
    end;

    { Decrement active count on the device }
    if device <> nil then
        if device^.activeCount > 0 then
            device^.activeCount := device^.activeCount - 1;

    { Invoke completion callback (sync path uses sync_io_callback, async path uses caller's callback) }
    if request^.Callback <> nil then
        request^.Callback(request^.Error, request^.CallbackData);

    { Free the heap copy of the request }
    ioreq_free(request);

    { Dispatch next queued request for this device }
    if device <> nil then
        dispatch_next(device);
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

{ Legacy procedure wrappers — drop-in replacements for old callers }
procedure storage_read_legacy(device : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32);
begin
    storage_read(device, addr, sectors, buffer);
end;

procedure storage_write_legacy(device : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32);
begin
    storage_write(device, addr, sectors, buffer);
end;

initialization
    boot.mgr.registerBoot('driver.storage.mgr', @init, 'Storage Manager', 'driver.storage.vfs');

end.
