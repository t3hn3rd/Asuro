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
    Driver->Storage->VolumeManager - Partition and volume management.

    Owns the partition table and volume list. All partition operations
    (add, remove, init) go through here so the in-memory volume list
    is always in sync with what is on disk.

    @author(Aaron Hance <ah@aaronhance.me>)
}

unit driver.storage.vol.mgr;

interface

uses
    boot.mgr,
    io.syslog,
    driver.storage.fs.mgr,
    core.ds.lists,
    memory.heap,
    driver.storage.vol.mbr,
    driver.storage.vol.gpt,
    driver.storage.mgr,
    driver.storage.types,
    core.strings,
    io.stdio,
    debug.tracer,
    core.util, arch.x86.util;

var
    volumes : PDList;

{ --- Lifecycle --- }
procedure init();
function watch_lifecycle(callback : TStorageLifecycleCallback; userdata : pointer) : uint32;
procedure unwatch_lifecycle(watchId : uint32);
function volume_is_busy(volume : PStorage_Volume) : boolean;
function volume_is_formatting(volume : PStorage_Volume) : boolean;
procedure volume_set_mounted(volume : PStorage_Volume; mounted : boolean);

{ --- Volume queries --- }
function get_volume_list() : PDList;
function get_volume_count() : uint32;
function get_volume(index : uint32) : PStorage_Volume;

{ --- Volume registration (used by FS detect callbacks) --- }
procedure register_volume(device : PStorage_Device; volume : PStorage_Volume);
procedure create_volume_from_partition(device : PStorage_Device; sectorStart : uint32; sectorCount : uint32);

{ --- Partition operations (read/write mbr + update volume list) --- }
function get_partition(device : PStorage_Device; index : uint32) : TPartition_table;
function add_partition(device : PStorage_Device; slot : uint32; partition : TPartition_table) : TError;
function remove_partition(device : PStorage_Device; slot : uint32) : TError;
function init_disk(device : PStorage_Device) : TError;
procedure discover_volumes(device : PStorage_Device);
function find_free_space(device : PStorage_Device; needed : uint32) : uint32;
function find_free_slot(device : PStorage_Device) : sint32;
function get_free_sector_count(device : PStorage_Device) : uint32;

{ --- Async partition operations (ISR-safe — no blocking I/O) --- }
procedure add_partition_async(device : PStorage_Device; slot : uint32; partition : TPartition_table;
                              callback : TIOCallback; callbackData : pointer);
procedure remove_partition_async(device : PStorage_Device; slot : uint32;
                                 callback : TIOCallback; callbackData : pointer);
procedure init_disk_async(device : PStorage_Device;
                          callback : TIOCallback; callbackData : pointer);

{ --- Filesystem operations --- }
function format_volume(device : PStorage_Device; volIndex : uint32; filesystemName : pchar; config : PFSFormatParams) : boolean;
{ False: no callback, caller retains callbackData.
  True: worker owns completion and invokes the callback exactly once. }
function format_volume_async(device : PStorage_Device; volIndex : uint32; filesystemName : pchar; config : PFSFormatParams; callback : TIOCallback; callbackData : pointer) : boolean;
{ eNone transfers completion to a worker; other returns never invoke callback. }
function set_volume_label_async(device : PStorage_Device; volIndex : uint32; text : pchar;
                                callback : TIOCallback; data : pointer) : TError;
procedure delete_volume(volume : PStorage_Volume);

implementation

uses
    driver.storage.vfs,
    proc.mgr,
    proc.types;

type
    PLabelWork = ^TLabelWork;
    TLabelWork = record
        Volume : PStorage_Volume;
        Value : TVolumeLabel;
        Callback : TIOCallback;
        Data : pointer;
    end;
    PStorageLifecycleWatch = ^TStorageLifecycleWatch;
    TStorageLifecycleWatch = record
        Active   : boolean;
        ID       : uint32;
        Callback : TStorageLifecycleCallback;
        UserData : pointer;
    end;

    PFormatVolumeAsyncCtx = ^TFormatVolumeAsyncCtx;
    TFormatVolumeAsyncCtx = record
        Volume       : PStorage_Volume;
        Filesystem   : PFilesystem;
        Config       : PFSFormatParams;
        UserCallback : TIOCallback;
        UserData     : pointer;
    end;

const
    MAX_STORAGE_LIFECYCLE_WATCHES = 32;

{ ===================== helpers ===================== }

var
    LifecycleWatches : array[0..MAX_STORAGE_LIFECYCLE_WATCHES - 1] of TStorageLifecycleWatch;
    NextLifecycleWatchID : uint32;
    NextVolumeID : uint32;

procedure notify_lifecycle(event : TStorageLifecycleEvent; device : PStorage_Device; volume : PStorage_Volume; error : TError);
var
    i : uint32;
begin
    for i := 0 to MAX_STORAGE_LIFECYCLE_WATCHES - 1 do begin
        if LifecycleWatches[i].Active and (LifecycleWatches[i].Callback <> nil) then
            LifecycleWatches[i].Callback(event, device, volume, error, LifecycleWatches[i].UserData);
    end;
end;

procedure set_volume_flag(volume : PStorage_Volume; flag : uint32; enabled : boolean);
begin
    if volume = nil then exit;
    if enabled then
        volume^.lifecycleFlags := volume^.lifecycleFlags or flag
    else
        volume^.lifecycleFlags := volume^.lifecycleFlags and (not flag);
end;

function find_volume_index(volume : PStorage_Volume) : sint32;
var
    i : uint32;
begin
    find_volume_index := -1;
    if volume = nil then exit;
    if volumes = nil then exit;
    if DL_Size(volumes) = 0 then exit;
    for i := 0 to DL_Size(volumes) - 1 do begin
        if get_volume(i) = volume then begin
            find_volume_index := sint32(i);
            exit;
        end;
    end;
end;

function auto_mount_volume(volume : PStorage_Volume) : TError;
begin
    auto_mount_volume := eVolumeNotFound;
    if find_volume_index(volume) < 0 then exit;
    auto_mount_volume := driver.storage.vfs.mountDefaultVolume(volume);
end;

function find_partition_slot_by_start(mbr : PMaster_Boot_Record; sectorStart : uint32) : sint32;
var
    i : uint32;
begin
    find_partition_slot_by_start := -1;
    if mbr = nil then exit;
    for i := 0 to 3 do begin
        if mbr^.partition[i].LBA_start = sectorStart then begin
            find_partition_slot_by_start := sint32(i);
            exit;
        end;
    end;
end;

function claim_metadata(device : PStorage_Device) : boolean;
var flags : uint32;
begin
    claim_metadata := false;
    if (device = nil) or device^.removed or (not device^.writable) then exit;
    asm pushfd; cli; pop flags end;
    if not device^.metadataBusy then begin
        device^.metadataBusy := true; claim_metadata := true;
    end;
    if (flags and $200) <> 0 then asm sti end;
end;

function update_partition_system_id(device : PStorage_Device; sectorStart : uint32; systemId : uint8) : TError;
var src, copyMbr : PMaster_Boot_Record; slot : sint32;
begin
    update_partition_system_id := eNone;
    src := get_cached_mbr(device);
    if src = nil then begin update_partition_system_id := eDeviceNotReady; exit; end;
    slot := find_partition_slot_by_start(src, sectorStart);
    if slot < 0 then exit; { whole-device filesystem or GPT, no MBR type to update }
    if src^.partition[slot].system_id = MBR_TYPE_GPT_PROTECTIVE then exit;
    if src^.partition[slot].system_id = systemId then exit;
    copyMbr := PMaster_Boot_Record(kalloc(sizeof(TMaster_Boot_Record)));
    if copyMbr = nil then begin update_partition_system_id := eOutOfMemory; exit; end;
    memcpy(uint32(src), uint32(copyMbr), sizeof(TMaster_Boot_Record));
    copyMbr^.partition[slot].system_id := systemId;
    update_partition_system_id := write_mbr(device, copyMbr);
    kfree(void(copyMbr));
end;

function perform_format(vol : PStorage_Volume; fs : PFilesystem; config : PFSFormatParams) : TError;
var err : TError;
begin
    perform_format := eFileInUse;
    if not driver.storage.vfs.InvalidateVolume(vol) then exit;
    vol^.filesystem := fs;
    memset(uint32(@vol^.labelText[0]),0,sizeof(vol^.labelText));
    err := fs^.createCallback(vol, vol^.sectorCount, vol^.sectorStart, config);
    { Do not identify/remount a partially formatted volume after an error. }
    vol^.filesystem := nil;
    if err = eNone then err := update_partition_system_id(vol^.device, vol^.sectorStart, fs^.system_id);
    if err = eNone then begin
        driver.storage.fs.mgr.probe_volume(vol);
        if vol^.filesystem <> fs then err := eCorruptFilesystem
        else err := auto_mount_volume(vol);
    end;
    if err <> eNone then begin
        driver.storage.vfs.InvalidateVolume(vol);
        vol^.filesystem := nil;
    end;
    perform_format := err;
end;

procedure format_volume_worker(pctx : proc.types.PProcessContext);
var ctx : PFormatVolumeAsyncCtx; err : TError;
begin
    ctx := PFormatVolumeAsyncCtx(pctx^.Local);
    if ctx = nil then begin proc.mgr.proc_exit(1); exit; end;
    err := perform_format(ctx^.Volume, ctx^.Filesystem, ctx^.Config);
    set_volume_flag(ctx^.Volume, STORAGE_VOLUME_FLAG_FORMATTING, false);
    ctx^.Volume^.device^.metadataBusy := false;
    notify_lifecycle(sleVolumeFormatCompleted, ctx^.Volume^.device, ctx^.Volume, err);
    if ctx^.Config <> nil then kfree(void(ctx^.Config));
    if ctx^.UserCallback <> nil then ctx^.UserCallback(err, ctx^.UserData);
    kfree(void(ctx)); proc.mgr.proc_exit(0);
end;

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
    volume^.isBootDrive  := device^.isBootDevice;
    volume^.lifecycleFlags := 0;
    driver.storage.fs.mgr.probe_volume(volume);
    register_volume(device, volume);
end;

procedure remove_volume_from_device_list(device : PStorage_Device; volume : PStorage_Volume);
var
    i : uint32;
    v : PStorage_Volume;
begin
    if (device = nil) or (device^.volumes = nil) or (volume = nil) then exit;
    i := 0;
    while i < DL_Size(device^.volumes) do begin
        v := PStorage_Volume(Void(DL_Get(device^.volumes, i))^);
        if v = volume then begin
            DL_Delete(device^.volumes, i);
            exit;
        end;
        i := i + 1;
    end;
end;

procedure detach_volume(volume : PStorage_Volume);
var idx : sint32;
begin
    idx := find_volume_index(volume);
    if idx < 0 then exit;
    notify_lifecycle(sleVolumeRemoved, volume^.device, volume, eNone);
    remove_volume_from_device_list(volume^.device, volume);
    DL_Delete(volumes, uint32(idx));
    kfree(void(volume));
end;

{ ===================== Lifecycle ===================== }

procedure init();
begin
    push_trace('driver.storage.vol.mgr.init');
    volumes := DL_New(sizeof(Pointer));
    memset(uint32(@LifecycleWatches[0]), 0, sizeof(LifecycleWatches));
    NextLifecycleWatchID := 1;
    NextVolumeID := 0;
end;

function watch_lifecycle(callback : TStorageLifecycleCallback; userdata : pointer) : uint32;
var
    i : uint32;
begin
    watch_lifecycle := 0;
    if callback = nil then exit;
    for i := 0 to MAX_STORAGE_LIFECYCLE_WATCHES - 1 do begin
        if not LifecycleWatches[i].Active then begin
            LifecycleWatches[i].Active := true;
            LifecycleWatches[i].ID := NextLifecycleWatchID;
            LifecycleWatches[i].Callback := callback;
            LifecycleWatches[i].UserData := userdata;
            watch_lifecycle := NextLifecycleWatchID;
            NextLifecycleWatchID := NextLifecycleWatchID + 1;
            if NextLifecycleWatchID = 0 then
                NextLifecycleWatchID := 1;
            exit;
        end;
    end;
end;

procedure unwatch_lifecycle(watchId : uint32);
var
    i : uint32;
begin
    if watchId = 0 then exit;
    for i := 0 to MAX_STORAGE_LIFECYCLE_WATCHES - 1 do begin
        if LifecycleWatches[i].Active and (LifecycleWatches[i].ID = watchId) then begin
            LifecycleWatches[i].Active := false;
            LifecycleWatches[i].ID := 0;
            LifecycleWatches[i].Callback := nil;
            LifecycleWatches[i].UserData := nil;
            exit;
        end;
    end;
end;

function volume_is_busy(volume : PStorage_Volume) : boolean;
begin
    volume_is_busy := false;
    if volume = nil then exit;
    volume_is_busy :=
        (volume^.lifecycleFlags and (STORAGE_VOLUME_FLAG_FORMATTING or STORAGE_VOLUME_FLAG_INVALIDATING or STORAGE_VOLUME_FLAG_REMOVED)) <> 0;
end;

function volume_is_formatting(volume : PStorage_Volume) : boolean;
begin
    volume_is_formatting := false;
    if volume = nil then exit;
    volume_is_formatting := (volume^.lifecycleFlags and STORAGE_VOLUME_FLAG_FORMATTING) <> 0;
end;

procedure volume_set_mounted(volume : PStorage_Volume; mounted : boolean);
begin
    if volume = nil then exit;
    if mounted then begin
        if (volume^.lifecycleFlags and STORAGE_VOLUME_FLAG_MOUNTED) = 0 then begin
            set_volume_flag(volume, STORAGE_VOLUME_FLAG_MOUNTED, true);
            notify_lifecycle(sleVolumeMounted, volume^.device, volume, eNone);
        end;
    end else begin
        if (volume^.lifecycleFlags and STORAGE_VOLUME_FLAG_MOUNTED) <> 0 then begin
            set_volume_flag(volume, STORAGE_VOLUME_FLAG_MOUNTED, false);
            notify_lifecycle(sleVolumeUnmounted, volume^.device, volume, eNone);
        end;
    end;
end;

{ ===================== Volume queries ===================== }

procedure register_volume(device : PStorage_Device; volume : PStorage_Volume);
var
    volPtr : PStorage_Volume;
begin
    push_trace('driver.storage.vol.mgr.register_volume');
    if device = nil then exit;
    volume^.id := NextVolumeID; Inc(NextVolumeID);
    volPtr := volume;
    DL_Add(volumes);
    DL_Set(volumes, DL_Size(volumes) - 1, puint32(@volPtr));

    if device^.volumes <> nil then begin
        volPtr := volume;
        DL_Add(device^.volumes);
        DL_Set(device^.volumes, DL_Size(device^.volumes) - 1, puint32(@volPtr));
    end;
    notify_lifecycle(sleVolumeAdded, device, volume, eNone);
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
    push_trace('driver.storage.vol.mgr.get_volume.enter');
    if index < DL_Size(volumes) then begin
        slot := DL_Get(volumes, index);
        get_volume := PStorage_Volume(slot^);
    end else
        get_volume := nil;
    push_trace('driver.storage.vol.mgr.get_volume.exit');
end;

{ ===================== Partition operations ===================== }

function get_partition(device : PStorage_Device; index : uint32) : TPartition_table;
var
    mbr : PMaster_Boot_Record;
begin
    push_trace('driver.storage.vol.mgr.get_partition');
    memset(uint32(@get_partition), 0, sizeof(TPartition_table));
    if (device = nil) or (index > 3) then exit;
    mbr := driver.storage.mgr.get_cached_mbr(device);
    if mbr = nil then exit;
    get_partition := mbr^.partition[index];
end;

{ kind: 0=add, 1=remove, 2=initialize. Caller owns metadataBusy. }
function partition_operation(device : PStorage_Device; kind, slot : uint32; const part : TPartition_table) : TError;
var
    mbr, src : PMaster_Boot_Record;
    newVol, victim, vol : PStorage_Volume;
    i, j : uint32;
    err : TError;
    partEnd, otherEnd : uint64;
begin
    partition_operation := eInvalidArgument;
    if (device = nil) or (not device^.writable) or device^.removed or (slot > 3) then exit;
    src := get_cached_mbr(device);
    if src = nil then begin partition_operation := eDeviceNotReady; exit; end;
    { GPT partition editing is not implemented; never mutate its protective MBR. }
    for i := 0 to 3 do
        if src^.partition[i].system_id = MBR_TYPE_GPT_PROTECTIVE then begin
            partition_operation := eNotSupported; exit;
        end;
    newVol := nil; victim := nil;
    if kind = 0 then begin
        if (part.LBA_start = 0) or (part.sector_count = 0) or
           (part.LBA_start >= device^.maxSectorCount) or
           (part.sector_count > device^.maxSectorCount-part.LBA_start) then exit;
        if src^.boot_sector = $AA55 then begin
            if (src^.partition[slot].LBA_start <> 0) or (src^.partition[slot].sector_count <> 0) then begin
                partition_operation := eAlreadyExists; exit;
            end;
            partEnd := uint64(part.LBA_start) + part.sector_count;
            for i := 0 to 3 do begin
                otherEnd := uint64(src^.partition[i].LBA_start) + src^.partition[i].sector_count;
                if (src^.partition[i].sector_count <> 0) and
                   (part.LBA_start < otherEnd) and (src^.partition[i].LBA_start < partEnd) then exit;
            end;
        end else if (device^.volumes <> nil) and (DL_Size(device^.volumes) <> 0) then begin
            partition_operation := eFileInUse; exit;
        end;
        newVol := PStorage_Volume(kalloc(sizeof(TStorage_Volume)));
        if newVol = nil then begin partition_operation := eOutOfMemory; exit; end;
        memset(uint32(newVol), 0, sizeof(TStorage_Volume));
        newVol^.device := device; newVol^.sectorStart := part.LBA_start;
        newVol^.sectorCount := part.sector_count; newVol^.sectorSize := device^.sectorSize;
    end;
    mbr := PMaster_Boot_Record(kalloc(sizeof(TMaster_Boot_Record)));
    if mbr = nil then begin
        if newVol <> nil then kfree(void(newVol));
        partition_operation := eOutOfMemory; exit;
    end;
    memcpy(uint32(src), uint32(mbr), sizeof(TMaster_Boot_Record));
    if (kind = 2) or (mbr^.boot_sector <> $AA55) then begin
        memset(uint32(mbr), 0, sizeof(TMaster_Boot_Record)); mbr^.boot_sector := $AA55;
    end;
    err := eNone;
    if kind = 0 then mbr^.partition[slot] := part
    else begin
        { Refuse teardown before touching the partition entry. metadataBusy
          prevents another format/delete from taking ownership of these objects. }
        i := 0;
        while i < DL_Size(volumes) do begin
            vol := get_volume(i);
            if (vol^.device = device) and ((kind = 2) or
               (vol^.sectorStart = src^.partition[slot].LBA_start)) then begin
                if volume_is_busy(vol) then begin err := eFileInUse; break; end;
                if not driver.storage.vfs.InvalidateVolume(vol) then begin err := eFileInUse; break; end;
                if kind = 1 then victim := vol;
            end;
            Inc(i);
        end;
        if (kind = 1) and (err = eNone) then
            memset(uint32(@mbr^.partition[slot]), 0, sizeof(TPartition_table));
    end;
    if err = eNone then err := write_mbr(device, mbr);
    kfree(void(mbr));
    if err = eNone then begin
        if kind = 0 then register_volume(device, newVol)
        else if kind = 1 then begin if victim <> nil then detach_volume(victim); end
        else begin
            i := 0;
            while i < DL_Size(volumes) do begin
                vol := get_volume(i);
                if vol^.device = device then detach_volume(vol) else Inc(i);
            end;
        end;
    end else begin
        if newVol <> nil then kfree(void(newVol));
        { Keep objects/cache on failure; remount anything invalidated above. }
        i := 0;
        while i < DL_Size(volumes) do begin
            vol := get_volume(i);
            if (vol^.device = device) and (vol^.filesystem <> nil) and
               ((vol^.lifecycleFlags and STORAGE_VOLUME_FLAG_MOUNTED) = 0) then auto_mount_volume(vol);
            Inc(i);
        end;
    end;
    partition_operation := err;
end;

function add_partition(device : PStorage_Device; slot : uint32; partition : TPartition_table) : TError;
begin
    add_partition := eFileInUse;
    if not claim_metadata(device) then exit;
    add_partition := partition_operation(device, 0, slot, partition);
    device^.metadataBusy := false;
end;

function remove_partition(device : PStorage_Device; slot : uint32) : TError;
var part : TPartition_table;
begin
    remove_partition := eFileInUse;
    if not claim_metadata(device) then exit;
    memset(uint32(@part), 0, sizeof(part));
    remove_partition := partition_operation(device, 1, slot, part);
    device^.metadataBusy := false;
end;

function init_disk(device : PStorage_Device) : TError;
var part : TPartition_table;
begin
    init_disk := eFileInUse;
    if not claim_metadata(device) then exit;
    memset(uint32(@part), 0, sizeof(part));
    init_disk := partition_operation(device, 2, 0, part);
    device^.metadataBusy := false;
end;

{ Read mbr and create volumes for all non-empty partitions.
  If the mbr contains a protective GPT partition (type 0xEE), try GPT
  detection first.  If GPT is valid, create volumes from the GPT partition
  array.  Otherwise, fall back to classic mbr parsing.

  If no partition was identified by any filesystem, fall back to asking
  each registered filesystem's detectCallback to probe the raw disk
  (e.g. ISO 9660 media may have a hybrid mbr). }
procedure discover_volumes(device : PStorage_Device);
var
    bootrecord : PMaster_Boot_Record;
    gptHeader  : PGPTHeader;
    gptEntries : PGPTPartitionEntry;
    entry      : PGPTPartitionEntry;
    i          : uint32;
    found      : uint32;
    identified : uint32;
    fsCount    : uint32;
    fs         : PFilesystem;
    v          : PStorage_Volume;
    hasGPT     : boolean;
begin
    push_trace('driver.storage.vol.mgr.discover_volumes');
    if device = nil then exit;

    { ATAPI / CD-ROM devices do not use mbr partitions — skip directly
      to filesystem detect callbacks (ISO 9660, etc.) }
    if (device^.controller = ControllerATAPI) or
       (device^.controller = ControllerAHCI_ATAPI) then begin
        fsCount := driver.storage.fs.mgr.get_filesystem_count();
        for i := 0 to fsCount - 1 do begin
            fs := driver.storage.fs.mgr.get_filesystem(i);
            if (fs <> nil) and (fs^.detectCallback <> nil) then
                fs^.detectCallback(device);
        end;
        exit;
    end;

    hasGPT := false;

    { Read mbr (LBA 0) }
    bootrecord := driver.storage.mgr.read_mbr(device);
    if bootrecord = nil then exit;

    { Check for protective GPT mbr (any partition with type 0xEE) }
    for i := 0 to 3 do begin
        if bootrecord^.partition[i].system_id = MBR_TYPE_GPT_PROTECTIVE then begin
            hasGPT := true;
            break;
        end;
    end;

    found := 0;

    if hasGPT then begin
        { ---- GPT path ---- }
        kfree(puint32(bootrecord));
        bootrecord := nil;

        gptHeader := gpt_read_header(device);
        if gptHeader <> nil then begin
            gptEntries := gpt_read_entries(device, gptHeader);
            if gptEntries <> nil then begin
                { Iterate partition entries }
                for i := 0 to gptHeader^.NumPartEntries - 1 do begin
                    entry := PGPTPartitionEntry(uint32(gptEntries) + i * gptHeader^.PartEntrySize);
                    if gpt_guid_is_zero(entry^.TypeGUID) then continue;  { empty slot }
                    if entry^.StartLBA_Hi <> 0 then continue;  { LBA beyond 32-bit range }
                    if entry^.EndLBA_Hi <> 0 then continue;
                    if entry^.StartLBA = 0 then continue;
                    if entry^.EndLBA < entry^.StartLBA then continue;

                    create_volume_from_partition(device,
                        entry^.StartLBA,
                        entry^.EndLBA - entry^.StartLBA + 1);
                    found := found + 1;
                end;
                kfree(puint32(gptEntries));
            end else begin
                io.syslog.logln('VOLMGR', 'GPT entry read failed — falling back to MBR.');
                hasGPT := false;  { fall through to mbr below }
            end;
            kfree(puint32(gptHeader));
        end else begin
            io.syslog.logln('VOLMGR', 'GPT header invalid — falling back to MBR.');
            hasGPT := false;  { fall through to mbr below }
        end;
    end;

    if not hasGPT then begin
        { ---- mbr path ---- }
        if bootrecord = nil then
            bootrecord := driver.storage.mgr.read_mbr(device);
        if bootrecord <> nil then begin
            for i := 0 to 3 do begin
                if bootrecord^.partition[i].LBA_start <> 0 then begin
                    create_volume_from_partition(device,
                        bootrecord^.partition[i].LBA_start,
                        bootrecord^.partition[i].sector_count);
                    found := found + 1;
                end;
            end;
            kfree(puint32(bootrecord));
        end;
    end;

    { Check whether any volume was actually identified }
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
        fsCount := driver.storage.fs.mgr.get_filesystem_count();
        for i := 0 to fsCount - 1 do begin
            fs := driver.storage.fs.mgr.get_filesystem(i);
            if (fs <> nil) and (fs^.detectCallback <> nil) then
                fs^.detectCallback(device);
        end;
    end;
end;

{ Find the first LBA after all existing partitions.
  Returns 0 if no space available. Minimum result is 1 (after mbr). }
function find_free_space(device : PStorage_Device; needed : uint32) : uint32;
var
    mbr     : PMaster_Boot_Record;
    i       : uint32;
    partEnd : uint32;
    nextLBA : uint32;
begin
    push_trace('driver.storage.vol.mgr.find_free_space');
    find_free_space := 0;

    mbr := driver.storage.mgr.get_cached_mbr(device);
    if mbr = nil then exit;
    if device^.maxSectorCount <= 1 then exit;
    if mbr^.boot_sector <> $AA55 then begin
        if needed <= device^.maxSectorCount-1 then find_free_space := 1;
        exit;
    end;
    nextLBA := 1;

    for i := 0 to 3 do begin
        if mbr^.partition[i].LBA_start <> 0 then begin
            if (mbr^.partition[i].LBA_start >= device^.maxSectorCount) or
               (mbr^.partition[i].sector_count > device^.maxSectorCount-mbr^.partition[i].LBA_start) then exit;
            partEnd := mbr^.partition[i].LBA_start + mbr^.partition[i].sector_count;
            if partEnd > nextLBA then
                nextLBA := partEnd;
        end;
    end;

    if (nextLBA <= device^.maxSectorCount) and (needed <= device^.maxSectorCount-nextLBA) then
        find_free_space := nextLBA;
end;

{ Find first empty mbr partition slot (0-3). Returns -1 if all occupied. }
function find_free_slot(device : PStorage_Device) : sint32;
var
    mbr : PMaster_Boot_Record;
    i   : uint32;
begin
    push_trace('driver.storage.vol.mgr.find_free_slot');
    find_free_slot := -1;

    mbr := driver.storage.mgr.get_cached_mbr(device);
    if mbr = nil then exit;
    if mbr^.boot_sector <> $AA55 then begin find_free_slot := 0; exit; end;

    for i := 0 to 3 do begin
        if (mbr^.partition[i].LBA_start = 0) and
           (mbr^.partition[i].sector_count = 0) then begin
            find_free_slot := i;
            exit;
        end;
    end;
end;

{ Return number of free sectors remaining after all partitions. }
function get_free_sector_count(device : PStorage_Device) : uint32;
var
    lba : uint32;
begin
    push_trace('driver.storage.vol.mgr.get_free_sector_count');
    get_free_sector_count := 0;

    lba := find_free_space(device, 0);
    if lba = 0 then exit;

    if device^.maxSectorCount > lba then
        get_free_sector_count := device^.maxSectorCount - lba;
end;

{ ===================== Async partition operations ===================== }

type
    PPartitionWork = ^TPartitionWork;
    TPartitionWork = record
        Device : PStorage_Device;
        Kind, Slot : uint32;
        Part : TPartition_table;
        Callback : TIOCallback;
        Data : pointer;
    end;

procedure partition_worker(pctx : proc.types.PProcessContext);
var ctx : PPartitionWork; err : TError;
begin
    ctx := PPartitionWork(pctx^.Local);
    err := partition_operation(ctx^.Device, ctx^.Kind, ctx^.Slot, ctx^.Part);
    ctx^.Device^.metadataBusy := false;
    if ctx^.Callback <> nil then ctx^.Callback(err, ctx^.Data);
    kfree(void(ctx)); proc.mgr.proc_exit(0);
end;

procedure submit_partition(device : PStorage_Device; kind, slot : uint32; const part : TPartition_table;
                           callback : TIOCallback; data : pointer);
var ctx : PPartitionWork;
begin
    if not claim_metadata(device) then begin
        if callback <> nil then callback(eFileInUse, data); exit;
    end;
    ctx := PPartitionWork(kalloc(sizeof(TPartitionWork)));
    if ctx <> nil then begin
        ctx^.Device := device; ctx^.Kind := kind; ctx^.Slot := slot;
        ctx^.Part := part; ctx^.Callback := callback; ctx^.Data := data;
        if proc.mgr.create('vol.part', @partition_worker, void(ctx), 1) <> nil then exit;
        kfree(void(ctx));
    end;
    device^.metadataBusy := false;
    if callback <> nil then callback(eOutOfMemory, data);
end;

procedure add_partition_async(device : PStorage_Device; slot : uint32; partition : TPartition_table;
                              callback : TIOCallback; callbackData : pointer);
begin submit_partition(device, 0, slot, partition, callback, callbackData); end;

procedure remove_partition_async(device : PStorage_Device; slot : uint32;
                                 callback : TIOCallback; callbackData : pointer);
var part : TPartition_table;
begin
    memset(uint32(@part), 0, sizeof(part));
    submit_partition(device, 1, slot, part, callback, callbackData);
end;

procedure init_disk_async(device : PStorage_Device; callback : TIOCallback; callbackData : pointer);
var part : TPartition_table;
begin
    memset(uint32(@part), 0, sizeof(part));
    submit_partition(device, 2, 0, part, callback, callbackData);
end;

{ ===================== Filesystem operations ===================== }

function prepare_format(device : PStorage_Device; volIndex : uint32; name : pchar; config : PFSFormatParams;
                        var vol : PStorage_Volume; var fs : PFilesystem) : boolean;
begin
    prepare_format := false;
    if not claim_metadata(device) then exit;
    vol := get_volume(volIndex); fs := driver.storage.fs.mgr.find_filesystem_by_name(name);
    if (vol <> nil) and (vol^.device = device) and (fs <> nil) then begin
        if (fs^.createCallback <> nil) and (fs^.validateFormat <> nil) and (not volume_is_busy(vol)) then begin
            if fs^.validateFormat(vol, vol^.sectorCount, vol^.sectorStart, config) = eNone then begin
                set_volume_flag(vol, STORAGE_VOLUME_FLAG_FORMATTING, true);
                prepare_format := true; exit;
            end;
        end;
    end;
    device^.metadataBusy := false;
end;

function format_volume(device : PStorage_Device; volIndex : uint32; filesystemName : pchar; config : PFSFormatParams) : boolean;
var vol : PStorage_Volume; fs : PFilesystem; err : TError;
begin
    format_volume := false;
    if not prepare_format(device, volIndex, filesystemName, config, vol, fs) then exit;
    notify_lifecycle(sleVolumeFormatStarted, device, vol, eNone);
    err := perform_format(vol, fs, config);
    set_volume_flag(vol, STORAGE_VOLUME_FLAG_FORMATTING, false);
    device^.metadataBusy := false;
    notify_lifecycle(sleVolumeFormatCompleted, device, vol, err);
    format_volume := err = eNone;
end;

{ False: caller still owns callbackData and NO callback has fired.
  True: worker owns it and invokes exactly one callback. }
function format_volume_async(device : PStorage_Device; volIndex : uint32; filesystemName : pchar;
                             config : PFSFormatParams; callback : TIOCallback; callbackData : pointer) : boolean;
var vol : PStorage_Volume; fs : PFilesystem; ctx : PFormatVolumeAsyncCtx;
begin
    format_volume_async := false;
    if not prepare_format(device, volIndex, filesystemName, config, vol, fs) then exit;
    ctx := PFormatVolumeAsyncCtx(kalloc(sizeof(TFormatVolumeAsyncCtx)));
    if ctx <> nil then begin
        ctx^.Volume := vol; ctx^.Filesystem := fs;
        ctx^.UserCallback := callback; ctx^.UserData := callbackData;
        ctx^.Config := nil;
        if config <> nil then begin
            ctx^.Config := PFSFormatParams(kalloc(sizeof(TFSFormatParams)));
            if ctx^.Config <> nil then memcpy(uint32(config), uint32(ctx^.Config), sizeof(TFSFormatParams));
        end;
        if (config = nil) or (ctx^.Config <> nil) then begin
            notify_lifecycle(sleVolumeFormatStarted, device, vol, eNone);
            if proc.mgr.create('vol.fmt', @format_volume_worker, void(ctx), 1) <> nil then begin
                format_volume_async := true; exit;
            end;
        end;
        if ctx^.Config <> nil then kfree(void(ctx^.Config));
        kfree(void(ctx));
    end;
    set_volume_flag(vol, STORAGE_VOLUME_FLAG_FORMATTING, false);
    device^.metadataBusy := false;
    notify_lifecycle(sleVolumeFormatCompleted, device, vol, eOutOfMemory);
end;

procedure label_worker(pctx : proc.types.PProcessContext);
var ctx : PLabelWork; vol : PStorage_Volume; err, mountErr : TError; wasMounted : boolean;
begin
    ctx := PLabelWork(pctx^.Local); vol := ctx^.Volume;
    wasMounted := (vol^.lifecycleFlags and STORAGE_VOLUME_FLAG_MOUNTED) <> 0;
    err := eFileInUse;
    if (not driver.storage.vfs.VolumeHasOpenHandles(vol)) and driver.storage.vfs.InvalidateVolume(vol) then begin
        err := vol^.filesystem^.setLabelCallback(vol,@ctx^.Value[0]);
        if wasMounted then begin
            mountErr := auto_mount_volume(vol);
            if err = eNone then err := mountErr;
        end;
    end;
    vol^.device^.metadataBusy := false;
    notify_lifecycle(sleVolumeLabelChanged,vol^.device,vol,err);
    if ctx^.Callback <> nil then ctx^.Callback(err,ctx^.Data);
    kfree(void(ctx)); proc.mgr.proc_exit(0);
end;

function set_volume_label_async(device : PStorage_Device; volIndex : uint32; text : pchar;
                                callback : TIOCallback; data : pointer) : TError;
var vol : PStorage_Volume; ctx : PLabelWork; value : TVolumeLabel;
begin
    set_volume_label_async := eInvalidArgument;
    if device = nil then exit;
    if not device^.writable then begin set_volume_label_async := eReadOnly; exit; end;
    set_volume_label_async := eFileInUse;
    if not claim_metadata(device) then exit;
    repeat
        vol := get_volume(volIndex);
        if (vol = nil) or (vol^.device <> device) then begin set_volume_label_async := eVolumeNotFound; break; end;
        if volume_is_busy(vol) then break;
        set_volume_label_async := eUnsupportedFilesystem;
        if vol^.filesystem = nil then break;
        if (vol^.filesystem^.validateLabelCallback = nil) or (vol^.filesystem^.setLabelCallback = nil) then break;
        set_volume_label_async := vol^.filesystem^.validateLabelCallback(text,value);
        if set_volume_label_async <> eNone then break;
        set_volume_label_async := eOutOfMemory;
        ctx := PLabelWork(kalloc(sizeof(TLabelWork))); if ctx = nil then break;
        ctx^.Volume := vol; ctx^.Value := value; ctx^.Callback := callback; ctx^.Data := data;
        if proc.mgr.create('vol.label',@label_worker,void(ctx),1) <> nil then begin
            set_volume_label_async := eNone; exit;
        end;
        kfree(void(ctx));
    until true;
    device^.metadataBusy := false;
end;

procedure delete_volume(volume : PStorage_Volume);
var device : PStorage_Device;
begin
    if volume = nil then exit;
    device := volume^.device;
    if not claim_metadata(device) then exit;
    if not volume_is_busy(volume) then
        if driver.storage.vfs.InvalidateVolume(volume) then detach_volume(volume);
    device^.metadataBusy := false;
end;

initialization
    boot.mgr.registerBoot('driver.storage.vol.mgr', @init, 'Volume Manager', 'driver.storage.mgr*');

end.
