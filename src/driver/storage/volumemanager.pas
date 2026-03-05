{
    Driver->Storage->VolumeManager - Partition and volume management.

    Owns the partition table and volume list. All partition operations
    (add, remove, init) go through here so the in-memory volume list
    is always in sync with what is on disk.

    @author(Aaron Hance <ah@aaronhance.me>)
}

unit volumemanager;

interface

uses
    syslog,
    filesystemmanager,
    lists,
    lmemorymanager,
    MBR,
    storagemanager,
    storagetypes,
    strings,
    stdio,
    tracer,
    util;

var
    volumes : PDList;

{ --- Lifecycle --- }
procedure init();

{ --- Volume queries --- }
function get_volume_list() : PDList;
function get_volume_count() : uint32;
function get_volume(index : uint32) : PStorage_Volume;

{ --- Volume registration (used by FS detect callbacks) --- }
procedure register_volume(device : PStorage_Device; volume : PStorage_Volume);
procedure create_volume_from_partition(device : PStorage_Device; sectorStart : uint32; sectorCount : uint32);

{ --- Partition operations (read/write MBR + update volume list) --- }
function get_partition(device : PStorage_Device; index : uint32) : TPartition_table;
procedure add_partition(device : PStorage_Device; slot : uint32; partition : TPartition_table);
procedure remove_partition(device : PStorage_Device; slot : uint32);
procedure init_disk(device : PStorage_Device);
procedure discover_volumes(device : PStorage_Device);
function find_free_space(device : PStorage_Device; needed : uint32) : uint32;
function find_free_slot(device : PStorage_Device) : sint32;
function get_free_sector_count(device : PStorage_Device) : uint32;

{ --- Filesystem operations --- }
function format_volume(device : PStorage_Device; volIndex : uint32; filesystemName : pchar; config : puint32) : boolean;
procedure delete_volume(volume : PStorage_Volume);

implementation

{ ===================== helpers ===================== }

{ Create a TStorage_Volume from a partition entry and register it }
procedure create_volume_from_partition(device : PStorage_Device; sectorStart : uint32; sectorCount : uint32);
var
    volume : PStorage_Volume;
begin
    volume := PStorage_Volume(kalloc(sizeof(TStorage_Volume)));
    if volume = nil then exit;
    volume^.device       := device;
    volume^.sectorStart  := sectorStart;
    volume^.sectorCount  := sectorCount;
    volume^.sectorSize   := device^.sectorSize;
    volume^.freeSectors  := 0;
    volume^.filesystem   := nil;
    volume^.isBootDrive  := false;
    filesystemmanager.probe_volume(volume);
    register_volume(device, volume);
end;

{ Remove from both global and device volume lists, then free }
procedure remove_volume_by_start(device : PStorage_Device; sectorStart : uint32);
var
    i    : uint32;
    v    : PStorage_Volume;
    found : PStorage_Volume;
begin
    found := nil;
    if device = nil then exit;

    { Remove from device list first (before we free the volume) }
    if device^.volumes <> nil then begin
        i := 0;
        while i < DL_Size(device^.volumes) do begin
            v := PStorage_Volume(Void(DL_Get(device^.volumes, i))^);
            if v^.sectorStart = sectorStart then begin
                DL_Delete(device^.volumes, i);
                break;
            end else
                i := i + 1;
        end;
    end;

    { Remove from global list and free }
    i := 0;
    while i < DL_Size(volumes) do begin
        v := PStorage_Volume(Void(DL_Get(volumes, i))^);
        if (v^.device = device) and (v^.sectorStart = sectorStart) then begin
            found := v;
            DL_Delete(volumes, i);
            break;
        end else
            i := i + 1;
    end;

    if found <> nil then
        kfree(puint32(found));
end;

{ Remove all volumes belonging to a device }
procedure remove_all_volumes_for_device(device : PStorage_Device);
var
    i : uint32;
    v : PStorage_Volume;
begin
    i := 0;
    while i < DL_Size(volumes) do begin
        v := PStorage_Volume(Void(DL_Get(volumes, i))^);
        if v^.device = device then begin
            DL_Delete(volumes, i);
            kfree(puint32(v));
        end else
            i := i + 1;
    end;

    if (device <> nil) and (device^.volumes <> nil) then
        DL_Clear(device^.volumes);
end;

{ ===================== Lifecycle ===================== }

procedure init();
begin
    push_trace('VolumeManager.init');
    volumes := DL_New(sizeof(Pointer));
end;

{ ===================== Volume queries ===================== }

procedure register_volume(device : PStorage_Device; volume : PStorage_Volume);
var
    volPtr : PStorage_Volume;
begin
    push_trace('VolumeManager.register_volume');
    if device = nil then exit;
    volPtr := volume;
    DL_Add(volumes);
    DL_Set(volumes, DL_Size(volumes) - 1, puint32(@volPtr));

    if device^.volumes <> nil then begin
        volPtr := volume;
        DL_Add(device^.volumes);
        DL_Set(device^.volumes, DL_Size(device^.volumes) - 1, puint32(@volPtr));
    end;
end;

function get_volume_list() : PDList;
begin
    get_volume_list := volumes;
end;

function get_volume_count() : uint32;
begin
    get_volume_count := DL_Size(volumes);
end;

function get_volume(index : uint32) : PStorage_Volume;
var
    slot : Void;
begin
    push_trace('VolumeManager.get_volume.enter');
    if index < DL_Size(volumes) then begin
        slot := DL_Get(volumes, index);
        get_volume := PStorage_Volume(slot^);
    end else
        get_volume := nil;
    push_trace('VolumeManager.get_volume.exit');
end;

{ ===================== Partition operations ===================== }

function get_partition(device : PStorage_Device; index : uint32) : TPartition_table;
var
    bootrecord : PMaster_Boot_Record;
begin
    push_trace('VolumeManager.get_partition');
    memset(uint32(@get_partition), 0, sizeof(TPartition_table));
    if (device = nil) or (index > 3) then exit;
    bootrecord := storagemanager.read_mbr(device);
    if bootrecord = nil then exit;
    get_partition := bootrecord^.partition[index];
    kfree(puint32(bootrecord));
end;

{ Write a partition entry to the MBR and create a matching volume }
procedure add_partition(device : PStorage_Device; slot : uint32; partition : TPartition_table);
var
    bootrecord : PMaster_Boot_Record;
begin
    push_trace('VolumeManager.add_partition');
    if (device = nil) or (slot > 3) or (not device^.writable) then exit;

    { Write to MBR }
    bootrecord := storagemanager.read_mbr(device);
    if bootrecord = nil then exit;
    bootrecord^.partition[slot] := partition;
    storagemanager.write_mbr(device, bootrecord);
    kfree(puint32(bootrecord));

    { Create volume in memory }
    if (partition.LBA_start <> 0) and (partition.sector_count <> 0) then
        create_volume_from_partition(device, partition.LBA_start, partition.sector_count);
end;

{ Zero a partition entry in the MBR and remove the matching volume }
procedure remove_partition(device : PStorage_Device; slot : uint32);
var
    bootrecord : PMaster_Boot_Record;
    oldPart    : TPartition_table;
    emptyPart  : TPartition_table;
begin
    push_trace('VolumeManager.remove_partition');
    if (device = nil) or (slot > 3) or (not device^.writable) then exit;

    { Read old entry so we know which volume to remove }
    bootrecord := storagemanager.read_mbr(device);
    if bootrecord = nil then exit;
    oldPart := bootrecord^.partition[slot];

    { Zero the slot }
    memset(uint32(@emptyPart), 0, sizeof(TPartition_table));
    bootrecord^.partition[slot] := emptyPart;
    storagemanager.write_mbr(device, bootrecord);
    kfree(puint32(bootrecord));

    { Remove the corresponding volume }
    if (oldPart.LBA_start <> 0) and (oldPart.sector_count <> 0) then
        remove_volume_by_start(device, oldPart.LBA_start);
end;

{ Wipe MBR (fresh signature) and remove all volumes for this device }
procedure init_disk(device : PStorage_Device);
var
    bootrecord : PMaster_Boot_Record;
begin
    push_trace('VolumeManager.init_disk');
    if device = nil then exit;
    if not device^.writable then exit;

    { Remove all volumes first }
    remove_all_volumes_for_device(device);

    { Write clean MBR }
    bootrecord := PMaster_Boot_Record(kalloc(sizeof(TMaster_Boot_Record)));
    if bootrecord = nil then exit;
    memset(uint32(bootrecord), 0, sizeof(TMaster_Boot_Record));
    bootrecord^.boot_sector := $AA55;
    storagemanager.write_mbr(device, bootrecord);
    kfree(puint32(bootrecord));
end;

{ Read MBR and create volumes for all non-empty partitions.
  If the MBR contains no partitions, or no partition was identified
  by any filesystem, fall back to asking each registered filesystem's
  detectCallback to probe the raw disk (e.g. ISO 9660 media may have
  a hybrid MBR with dummy partitions that don't match any FS). }
procedure discover_volumes(device : PStorage_Device);
var
    bootrecord : PMaster_Boot_Record;
    i          : uint32;
    found      : uint32;
    identified : uint32;
    fsCount    : uint32;
    fs         : PFilesystem;
    v          : PStorage_Volume;
begin
    push_trace('VolumeManager.discover_volumes');
    if device = nil then exit;
    bootrecord := storagemanager.read_mbr(device);
    if bootrecord = nil then exit;

    found := 0;
    for i := 0 to 3 do begin
        if bootrecord^.partition[i].LBA_start <> 0 then begin
            create_volume_from_partition(device, bootrecord^.partition[i].LBA_start, bootrecord^.partition[i].sector_count);
            found := found + 1;
        end;
    end;

    kfree(puint32(bootrecord));

    { Check whether any MBR volume was actually identified }
    identified := 0;
    if (found > 0) and (device^.volumes <> nil) then begin
        for i := 0 to DL_Size(device^.volumes) - 1 do begin
            v := PStorage_Volume(Void(DL_Get(device^.volumes, i))^);
            if v^.filesystem <> nil then
                identified := identified + 1;
        end;
    end;

    { No identified volumes — let filesystem drivers probe the raw disk }
    if identified = 0 then begin
        fsCount := filesystemmanager.get_filesystem_count();
        for i := 0 to fsCount - 1 do begin
            fs := filesystemmanager.get_filesystem(i);
            if (fs <> nil) and (fs^.detectCallback <> nil) then
                fs^.detectCallback(device);
        end;
    end;
end;

{ Find the first LBA after all existing partitions.
  Returns 0 if no space available. Minimum result is 1 (after MBR). }
function find_free_space(device : PStorage_Device; needed : uint32) : uint32;
var
    bootrecord : PMaster_Boot_Record;
    i          : uint32;
    partEnd    : uint32;
    nextLBA    : uint32;
begin
    push_trace('VolumeManager.find_free_space');
    find_free_space := 0;

    bootrecord := storagemanager.read_mbr(device);
    if bootrecord = nil then exit;
    nextLBA := 1;

    for i := 0 to 3 do begin
        if bootrecord^.partition[i].LBA_start <> 0 then begin
            partEnd := bootrecord^.partition[i].LBA_start + bootrecord^.partition[i].sector_count;
            if partEnd > nextLBA then
                nextLBA := partEnd;
        end;
    end;

    kfree(puint32(bootrecord));

    if (nextLBA + needed) <= device^.maxSectorCount then
        find_free_space := nextLBA;
end;

{ Find first empty MBR partition slot (0-3). Returns -1 if all occupied. }
function find_free_slot(device : PStorage_Device) : sint32;
var
    bootrecord : PMaster_Boot_Record;
    i          : uint32;
begin
    push_trace('VolumeManager.find_free_slot');
    find_free_slot := -1;

    bootrecord := storagemanager.read_mbr(device);
    if bootrecord = nil then exit;

    for i := 0 to 3 do begin
        if (bootrecord^.partition[i].LBA_start = 0) and
           (bootrecord^.partition[i].sector_count = 0) then begin
            find_free_slot := i;
            kfree(puint32(bootrecord));
            exit;
        end;
    end;

    kfree(puint32(bootrecord));
end;

{ Return number of free sectors remaining after all partitions. }
function get_free_sector_count(device : PStorage_Device) : uint32;
var
    lba : uint32;
begin
    push_trace('VolumeManager.get_free_sector_count');
    get_free_sector_count := 0;

    lba := find_free_space(device, 0);
    if lba = 0 then exit;

    if device^.maxSectorCount > lba then
        get_free_sector_count := device^.maxSectorCount - lba;
end;

{ ===================== Filesystem operations ===================== }

function format_volume(device : PStorage_Device; volIndex : uint32; filesystemName : pchar; config : puint32) : boolean;
var
    vol : PStorage_Volume;
    fs  : PFilesystem;
begin
    push_trace('VolumeManager.format_volume');
    format_volume := false;

    vol := get_volume(volIndex);
    if vol = nil then exit;
    if vol^.device <> device then exit;

    fs := filesystemmanager.find_filesystem_by_name(filesystemName);
    if fs = nil then exit;
    if fs^.createCallback = nil then exit;

    vol^.filesystem := fs;
    fs^.createCallback(vol, vol^.sectorCount, vol^.sectorStart, config);
    format_volume := true;
end;

procedure delete_volume(volume : PStorage_Volume);
var
    device : PStorage_Device;
begin
    push_trace('VolumeManager.delete_volume');
    if volume = nil then exit;
    device := volume^.device;
    remove_volume_by_start(device, volume^.sectorStart);
end;

end.