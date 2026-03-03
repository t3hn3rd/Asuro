{
    Driver->Storage->StorageManager - Physical storage device registry.

    Manages registration of physical storage devices (AHCI, IDE, USB, etc.)
    and provides a global device list plus raw MBR read/write.
    Device drivers call register_device() when they discover a new device.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit storagemanager;

interface

uses
    lists,
    lmemorymanager,
    MBR,
    storagetypes,
    tracer,
    util;

var
    storageDevices : PDList;

procedure init();
procedure register_device(device : PStorage_Device);
function get_device_list() : PDList;
function get_device_count() : uint32;
function get_device(index : uint32) : PStorage_Device;
function controller_type_2_string(controllerType : TControllerType) : pchar;
function read_mbr(device : PStorage_Device) : PMaster_Boot_Record;
procedure write_mbr(device : PStorage_Device; mbr : PMaster_Boot_Record);

{ Block I/O helpers — prefer the async path (interrupt-driven wait) when
  available, falling back to the legacy sync callback for non-AHCI devices.
  These are meant as a transitional bridge; callers should migrate to the
  async hooks with their own completion callbacks over time. }
procedure storage_read(device : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32);
procedure storage_write(device : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32);

implementation

procedure init();
begin
    push_trace('StorageManager.init');
    storageDevices := DL_New(sizeof(TStorage_Device));
end;

procedure register_device(device : PStorage_Device);
begin
    push_trace('StorageManager.register_device');
    DL_Add(storageDevices);
    DL_Set(storageDevices, DL_Size(storageDevices) - 1, puint32(device));
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
begin
    push_trace('StorageManager.read_mbr');
    read_mbr := PMaster_Boot_Record(kalloc(sizeof(TMaster_Boot_Record)));
    storage_read(device, 0, 1, puint32(read_mbr));
end;

procedure write_mbr(device : PStorage_Device; mbr : PMaster_Boot_Record);
begin
    push_trace('StorageManager.write_mbr');
    if not device^.writable then exit;
    storage_write(device, 0, 1, puint32(mbr));
end;

{ Completion callback for storage_read/storage_write — sets flag so hlt loop exits }
procedure storage_sync_done(success : boolean; userdata : puint32);
begin
    userdata^ := 1;
end;

procedure storage_read(device : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32);
var
    done : uint32;
begin
    if device^.readCallbackAsync <> nil then begin
        done := 0;
        device^.readCallbackAsync(device, addr, sectors, buffer, @storage_sync_done, @done);
        asm sti end;
        while done = 0 do begin
            asm hlt end;  { sleep until next interrupt }
            { Fallback: if the hardware IRQ was not delivered through the PIC,
              poll the driver inline so the completion fires. }
            if (done = 0) and (device^.pollCallback <> nil) then
                device^.pollCallback();
        end;
    end else if device^.readCallback <> nil then
        device^.readCallback(device, addr, sectors, buffer);
end;

procedure storage_write(device : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32);
var
    done : uint32;
begin
    if device^.writeCallbackAsync <> nil then begin
        done := 0;
        device^.writeCallbackAsync(device, addr, sectors, buffer, @storage_sync_done, @done);
        asm sti end;
        while done = 0 do begin
            asm hlt end;  { sleep until next interrupt }
            if (done = 0) and (device^.pollCallback <> nil) then
                device^.pollCallback();
        end;
    end else if device^.writeCallback <> nil then
        device^.writeCallback(device, addr, sectors, buffer);
end;

end.
