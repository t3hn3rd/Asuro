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
procedure add_partition(device : PStorage_Device; slot : uint32; partition : TPartition_table);
procedure remove_partition(device : PStorage_Device; slot : uint32);
procedure init_disk(device : PStorage_Device);
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
function format_volume_async(device : PStorage_Device; volIndex : uint32; filesystemName : pchar; config : PFSFormatParams; callback : TIOCallback; callbackData : pointer) : boolean;
procedure delete_volume(volume : PStorage_Volume);

implementation

uses
    driver.storage.vfs,
    proc.mgr,
    proc.types;

type
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

procedure auto_mount_volume(volume : PStorage_Volume);
var
    volIdx    : sint32;
    volNumStr : pchar;
    volName   : pchar;
    prefix    : pchar;
    mountPath : pchar;
begin
    if volume = nil then exit;
    if volume^.filesystem = nil then exit;

    volIdx := find_volume_index(volume);
    if volIdx < 0 then exit;

    volNumStr := intToString(uint32(volIdx));
    volName := stringConcat('vol', volNumStr);
    kfree(void(volNumStr));
    prefix := stringNew(6);
    prefix[0] := '/';
    prefix[1] := 'd';
    prefix[2] := 'i';
    prefix[3] := 's';
    prefix[4] := 'k';
    prefix[5] := '/';
    mountPath := stringConcat(prefix, volName);

    driver.storage.vfs.mountVolume(mountPath, volume);
    if volume^.isBootDrive then
        driver.storage.vfs.mountVolume('/boot', volume);

    kfree(void(volName));
    kfree(void(prefix));
    kfree(void(mountPath));
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

procedure update_partition_system_id_sync(device : PStorage_Device; sectorStart : uint32; systemId : uint8);
var
    srcMbr     : PMaster_Boot_Record;
    tempMbr    : PMaster_Boot_Record;
    slot       : sint32;
    freeSrcMbr : boolean;
begin
    if device = nil then exit;

    srcMbr := driver.storage.mgr.get_cached_mbr(device);
    freeSrcMbr := false;
    if srcMbr = nil then begin
        srcMbr := driver.storage.mgr.read_mbr(device);
        freeSrcMbr := srcMbr <> nil;
    end;
    if srcMbr = nil then exit;

    slot := find_partition_slot_by_start(srcMbr, sectorStart);
    if slot < 0 then begin
        if freeSrcMbr then kfree(void(srcMbr));
        exit;
    end;

    if srcMbr^.partition[slot].system_id = systemId then begin
        if freeSrcMbr then kfree(void(srcMbr));
        exit;
    end;

    tempMbr := PMaster_Boot_Record(kalloc(sizeof(TMaster_Boot_Record)));
    if tempMbr = nil then begin
        if freeSrcMbr then kfree(void(srcMbr));
        exit;
    end;
    memcpy(uint32(srcMbr), uint32(tempMbr), sizeof(TMaster_Boot_Record));
    tempMbr^.partition[slot].system_id := systemId;
    driver.storage.mgr.write_mbr(device, tempMbr);
    kfree(void(tempMbr));

    if freeSrcMbr then kfree(void(srcMbr));
end;

procedure update_partition_system_id_async(device : PStorage_Device; sectorStart : uint32; systemId : uint8);
var
    srcMbr     : PMaster_Boot_Record;
    tempMbr    : PMaster_Boot_Record;
    slot       : sint32;
    freeSrcMbr : boolean;
begin
    if device = nil then exit;

    srcMbr := driver.storage.mgr.get_cached_mbr(device);
    freeSrcMbr := false;
    if srcMbr = nil then begin
        srcMbr := driver.storage.mgr.read_mbr(device);
        freeSrcMbr := srcMbr <> nil;
    end;
    if srcMbr = nil then exit;

    slot := find_partition_slot_by_start(srcMbr, sectorStart);
    if slot < 0 then begin
        if freeSrcMbr then kfree(void(srcMbr));
        exit;
    end;

    if srcMbr^.partition[slot].system_id = systemId then begin
        if freeSrcMbr then kfree(void(srcMbr));
        exit;
    end;

    tempMbr := PMaster_Boot_Record(kalloc(sizeof(TMaster_Boot_Record)));
    if tempMbr = nil then begin
        if freeSrcMbr then kfree(void(srcMbr));
        exit;
    end;
    memcpy(uint32(srcMbr), uint32(tempMbr), sizeof(TMaster_Boot_Record));
    tempMbr^.partition[slot].system_id := systemId;
    driver.storage.mgr.write_mbr_async(device, tempMbr, nil, nil);
    kfree(void(tempMbr));

    if freeSrcMbr then kfree(void(srcMbr));
end;

procedure format_volume_worker(pctx : proc.types.PProcessContext);
var
    ctx : PFormatVolumeAsyncCtx;
    err : TError;
begin
    ctx := PFormatVolumeAsyncCtx(pctx^.Local);
    if ctx = nil then begin
        proc.mgr.proc_exit(1);
        exit;
    end;

    err := eNone;
    if (ctx^.Volume = nil) or (ctx^.Filesystem = nil) then
        err := eInvalidArgument
    else if ctx^.Volume^.device = nil then
        err := eDeviceNotFound
    else if not ctx^.Volume^.device^.writable then
        err := eReadOnly
    else if ctx^.Filesystem^.createCallback = nil then
        err := eInvalidArgument;

    if err = eNone then begin
        if not driver.storage.vfs.InvalidateVolume(ctx^.Volume) then
            err := eFileInUse
        else begin
            update_partition_system_id_sync(ctx^.Volume^.device, ctx^.Volume^.sectorStart, ctx^.Filesystem^.system_id);
            ctx^.Volume^.filesystem := ctx^.Filesystem;
            ctx^.Filesystem^.createCallback(ctx^.Volume, ctx^.Volume^.sectorCount, ctx^.Volume^.sectorStart, ctx^.Config);

            { Re-probe the freshly formatted volume so the caller gets a verified
              filesystem assignment and refreshed free-space metadata. }
            ctx^.Volume^.filesystem := nil;
            driver.storage.fs.mgr.probe_volume(ctx^.Volume);
            if ctx^.Volume^.filesystem <> ctx^.Filesystem then
                err := eUnsupportedFilesystem
            else
                auto_mount_volume(ctx^.Volume);
        end;
    end;

    set_volume_flag(ctx^.Volume, STORAGE_VOLUME_FLAG_FORMATTING, false);
    notify_lifecycle(sleVolumeFormatCompleted, ctx^.Volume^.device, ctx^.Volume, err);

    if ctx^.Config <> nil then
        kfree(void(ctx^.Config));
    if ctx^.UserCallback <> nil then
        ctx^.UserCallback(err, ctx^.UserData);
    kfree(void(ctx));
    proc.mgr.proc_exit(0);
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

{ Remove from both global and device volume core.ds.lists, then free }
procedure remove_volume_by_start(device : PStorage_Device; sectorStart : uint32);
var
    i    : uint32;
    v    : PStorage_Volume;
    found : PStorage_Volume;
begin
    found := nil;
    if device = nil then exit;

    i := 0;
    while i < DL_Size(volumes) do begin
        v := PStorage_Volume(Void(DL_Get(volumes, i))^);
        if (v^.device = device) and (v^.sectorStart = sectorStart) then begin
            found := v;
            break;
        end else
            i := i + 1;
    end;

    if found <> nil then begin
        set_volume_flag(found, STORAGE_VOLUME_FLAG_INVALIDATING, true);
        notify_lifecycle(sleVolumeInvalidating, device, found, eNone);
        if not driver.storage.vfs.InvalidateVolume(found) then begin
            set_volume_flag(found, STORAGE_VOLUME_FLAG_INVALIDATING, false);
            exit;
        end;
        set_volume_flag(found, STORAGE_VOLUME_FLAG_INVALIDATING, false);
        notify_lifecycle(sleVolumeInvalidated, device, found, eNone);
        set_volume_flag(found, STORAGE_VOLUME_FLAG_REMOVED, true);
        notify_lifecycle(sleVolumeRemoved, device, found, eNone);
        remove_volume_from_device_list(device, found);
        DL_Delete(volumes, i);
        kfree(puint32(found));
    end;
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
            set_volume_flag(v, STORAGE_VOLUME_FLAG_INVALIDATING, true);
            notify_lifecycle(sleVolumeInvalidating, device, v, eNone);
            if not driver.storage.vfs.InvalidateVolume(v) then begin
                set_volume_flag(v, STORAGE_VOLUME_FLAG_INVALIDATING, false);
                i := i + 1;
                continue;
            end;
            set_volume_flag(v, STORAGE_VOLUME_FLAG_INVALIDATING, false);
            notify_lifecycle(sleVolumeInvalidated, device, v, eNone);
            set_volume_flag(v, STORAGE_VOLUME_FLAG_REMOVED, true);
            notify_lifecycle(sleVolumeRemoved, device, v, eNone);
            DL_Delete(volumes, i);
            remove_volume_from_device_list(device, v);
            kfree(puint32(v));
        end else
            i := i + 1;
    end;
end;

{ ===================== Lifecycle ===================== }

procedure init();
begin
    push_trace('driver.storage.vol.mgr.init');
    volumes := DL_New(sizeof(Pointer));
    memset(uint32(@LifecycleWatches[0]), 0, sizeof(LifecycleWatches));
    NextLifecycleWatchID := 1;
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

{ Write a partition entry to the mbr and create a matching volume }
procedure add_partition(device : PStorage_Device; slot : uint32; partition : TPartition_table);
var
    bootrecord : PMaster_Boot_Record;
begin
    push_trace('driver.storage.vol.mgr.add_partition');
    if (device = nil) or (slot > 3) or (not device^.writable) then exit;

    { Write to mbr }
    bootrecord := driver.storage.mgr.read_mbr(device);
    if bootrecord = nil then exit;
    bootrecord^.partition[slot] := partition;
    driver.storage.mgr.write_mbr(device, bootrecord);
    kfree(puint32(bootrecord));

    { Create volume in memory }
    if (partition.LBA_start <> 0) and (partition.sector_count <> 0) then
        create_volume_from_partition(device, partition.LBA_start, partition.sector_count);
end;

{ Zero a partition entry in the mbr and remove the matching volume }
procedure remove_partition(device : PStorage_Device; slot : uint32);
var
    bootrecord : PMaster_Boot_Record;
    oldPart    : TPartition_table;
    emptyPart  : TPartition_table;
begin
    push_trace('driver.storage.vol.mgr.remove_partition');
    if (device = nil) or (slot > 3) or (not device^.writable) then exit;

    { Read old entry so we know which volume to remove }
    bootrecord := driver.storage.mgr.read_mbr(device);
    if bootrecord = nil then exit;
    oldPart := bootrecord^.partition[slot];

    { Zero the slot }
    memset(uint32(@emptyPart), 0, sizeof(TPartition_table));
    bootrecord^.partition[slot] := emptyPart;
    driver.storage.mgr.write_mbr(device, bootrecord);
    kfree(puint32(bootrecord));

    { Remove the corresponding volume }
    if (oldPart.LBA_start <> 0) and (oldPart.sector_count <> 0) then
        remove_volume_by_start(device, oldPart.LBA_start);
end;

{ Wipe mbr (fresh signature) and remove all volumes for this device }
procedure init_disk(device : PStorage_Device);
var
    bootrecord : PMaster_Boot_Record;
begin
    push_trace('driver.storage.vol.mgr.init_disk');
    if device = nil then exit;
    if not device^.writable then exit;

    { Remove all volumes first }
    remove_all_volumes_for_device(device);

    { Write clean mbr }
    bootrecord := PMaster_Boot_Record(kalloc(sizeof(TMaster_Boot_Record)));
    if bootrecord = nil then exit;
    memset(uint32(bootrecord), 0, sizeof(TMaster_Boot_Record));
    bootrecord^.boot_sector := $AA55;
    driver.storage.mgr.write_mbr(device, bootrecord);
    kfree(puint32(bootrecord));
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
    nextLBA := 1;

    for i := 0 to 3 do begin
        if mbr^.partition[i].LBA_start <> 0 then begin
            partEnd := mbr^.partition[i].LBA_start + mbr^.partition[i].sector_count;
            if partEnd > nextLBA then
                nextLBA := partEnd;
        end;
    end;

    if (nextLBA + needed) <= device^.maxSectorCount then
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

{ Modify cached mbr in-place, create volume in memory, fire-and-forget write.
  All in-memory changes happen synchronously so the caller can refresh UI
  immediately.  The disk write completes asynchronously. }
procedure add_partition_async(device : PStorage_Device; slot : uint32; partition : TPartition_table;
                              callback : TIOCallback; callbackData : pointer);
var
    mbr : PMaster_Boot_Record;
    vol : PStorage_Volume;
begin
    push_trace('driver.storage.vol.mgr.add_partition_async');
    if (device = nil) or (slot > 3) or (not device^.writable) then begin
        if callback <> nil then callback(eInvalidArgument, callbackData);
        exit;
    end;

    mbr := driver.storage.mgr.get_cached_mbr(device);
    if mbr = nil then begin
        if callback <> nil then callback(eDeviceNotReady, callbackData);
        exit;
    end;

    { Modify cache in-place }
    mbr^.partition[slot] := partition;

    { Create volume in memory — skip probe_volume because
      (a) the partition is freshly created / unformatted, and
      (b) probe_volume does blocking I/O which is unsafe here. }
    if (partition.LBA_start <> 0) and (partition.sector_count <> 0) then begin
        vol := PStorage_Volume(kalloc(sizeof(TStorage_Volume)));
        if vol <> nil then begin
            vol^.device      := device;
            vol^.sectorStart := partition.LBA_start;
            vol^.sectorCount := partition.sector_count;
            vol^.sectorSize  := device^.sectorSize;
            vol^.freeSectors := 0;
            vol^.filesystem  := nil;
            vol^.isBootDrive := false;
            register_volume(device, vol);
        end;
    end;

    { Write cached mbr to disk through the storage manager's staged MBR path. }
    driver.storage.mgr.write_mbr_async(device, mbr, callback, callbackData);
end;

procedure remove_partition_async(device : PStorage_Device; slot : uint32;
                                 callback : TIOCallback; callbackData : pointer);
var
    mbr       : PMaster_Boot_Record;
    oldPart   : TPartition_table;
    emptyPart : TPartition_table;
begin
    push_trace('driver.storage.vol.mgr.remove_partition_async');
    if (device = nil) or (slot > 3) or (not device^.writable) then begin
        if callback <> nil then callback(eInvalidArgument, callbackData);
        exit;
    end;

    mbr := driver.storage.mgr.get_cached_mbr(device);
    if mbr = nil then begin
        if callback <> nil then callback(eDeviceNotReady, callbackData);
        exit;
    end;

    oldPart := mbr^.partition[slot];

    { Zero the slot in cache }
    memset(uint32(@emptyPart), 0, sizeof(TPartition_table));
    mbr^.partition[slot] := emptyPart;

    { Remove the corresponding volume from memory }
    if (oldPart.LBA_start <> 0) and (oldPart.sector_count <> 0) then
        remove_volume_by_start(device, oldPart.LBA_start);

    { Write cached mbr to disk through the storage manager's staged MBR path. }
    driver.storage.mgr.write_mbr_async(device, mbr, callback, callbackData);
end;

procedure init_disk_async(device : PStorage_Device;
                          callback : TIOCallback; callbackData : pointer);
var
    cache : puint32;
begin
    push_trace('driver.storage.vol.mgr.init_disk_async');
    if (device = nil) or (not device^.writable) then begin
        if callback <> nil then callback(eInvalidArgument, callbackData);
        exit;
    end;

    { Remove all volumes first }
    remove_all_volumes_for_device(device);

    { Create fresh cached mbr }
    if device^.cachedMBR <> nil then
        kfree(device^.cachedMBR);
    cache := puint32(kalloc(sizeof(TMaster_Boot_Record)));
    if cache = nil then begin
        device^.cachedMBR := nil;
        if callback <> nil then callback(eOutOfMemory, callbackData);
        exit;
    end;
    memset(uint32(cache), 0, sizeof(TMaster_Boot_Record));
    PMaster_Boot_Record(cache)^.boot_sector := $AA55;
    device^.cachedMBR := pointer(cache);

    { Write to disk through the storage manager's staged MBR path. }
    driver.storage.mgr.write_mbr_async(device, PMaster_Boot_Record(cache), callback, callbackData);
end;

{ ===================== Filesystem operations ===================== }

function format_volume(device : PStorage_Device; volIndex : uint32; filesystemName : pchar; config : PFSFormatParams) : boolean;
var
    vol : PStorage_Volume;
    fs  : PFilesystem;
begin
    push_trace('driver.storage.vol.mgr.format_volume');
    format_volume := false;

    vol := get_volume(volIndex);
    if vol = nil then exit;
    if vol^.device <> device then exit;

    fs := driver.storage.fs.mgr.find_filesystem_by_name(filesystemName);
    if fs = nil then exit;
    if fs^.createCallback = nil then exit;
    if volume_is_busy(vol) then exit;

    set_volume_flag(vol, STORAGE_VOLUME_FLAG_FORMATTING, true);
    notify_lifecycle(sleVolumeFormatStarted, device, vol, eNone);
    if not driver.storage.vfs.InvalidateVolume(vol) then begin
        set_volume_flag(vol, STORAGE_VOLUME_FLAG_FORMATTING, false);
        notify_lifecycle(sleVolumeFormatCompleted, device, vol, eFileInUse);
        exit;
    end;

    update_partition_system_id_sync(device, vol^.sectorStart, fs^.system_id);
    vol^.filesystem := fs;
    fs^.createCallback(vol, vol^.sectorCount, vol^.sectorStart, config);
    vol^.filesystem := nil;
    driver.storage.fs.mgr.probe_volume(vol);
    format_volume := vol^.filesystem = fs;
    if format_volume then
        auto_mount_volume(vol);
    set_volume_flag(vol, STORAGE_VOLUME_FLAG_FORMATTING, false);
    if format_volume then
        notify_lifecycle(sleVolumeFormatCompleted, device, vol, eNone)
    else
        notify_lifecycle(sleVolumeFormatCompleted, device, vol, eUnsupportedFilesystem);
end;

function format_volume_async(device : PStorage_Device; volIndex : uint32; filesystemName : pchar;
                             config : PFSFormatParams; callback : TIOCallback; callbackData : pointer) : boolean;
var
    vol : PStorage_Volume;
    fs  : PFilesystem;
    ctx : PFormatVolumeAsyncCtx;
    cfgCopy : PFSFormatParams;
begin
    push_trace('driver.storage.vol.mgr.format_volume_async');
    format_volume_async := false;

    vol := get_volume(volIndex);
    if vol = nil then exit;
    if vol^.device <> device then exit;

    fs := driver.storage.fs.mgr.find_filesystem_by_name(filesystemName);
    if fs = nil then exit;
    if fs^.createCallback = nil then exit;
    if volume_is_busy(vol) then begin
        if callback <> nil then callback(eFileInUse, callbackData);
        exit;
    end;

    cfgCopy := nil;
    if config <> nil then begin
        cfgCopy := PFSFormatParams(kalloc(sizeof(TFSFormatParams)));
        if cfgCopy = nil then begin
            if callback <> nil then callback(eOutOfMemory, callbackData);
            exit;
        end;
        memcpy(uint32(config), uint32(cfgCopy), sizeof(TFSFormatParams));
    end;

    ctx := PFormatVolumeAsyncCtx(kalloc(sizeof(TFormatVolumeAsyncCtx)));
    if ctx = nil then begin
        if cfgCopy <> nil then kfree(void(cfgCopy));
        if callback <> nil then callback(eOutOfMemory, callbackData);
        exit;
    end;
    ctx^.Volume := vol;
    ctx^.Filesystem := fs;
    ctx^.Config := cfgCopy;
    ctx^.UserCallback := callback;
    ctx^.UserData := callbackData;

    set_volume_flag(vol, STORAGE_VOLUME_FLAG_FORMATTING, true);
    notify_lifecycle(sleVolumeFormatStarted, device, vol, eNone);

    if proc.mgr.create('vol.fmt', @format_volume_worker, void(ctx), 1) = nil then begin
        set_volume_flag(vol, STORAGE_VOLUME_FLAG_FORMATTING, false);
        notify_lifecycle(sleVolumeFormatCompleted, device, vol, eOutOfMemory);
        if cfgCopy <> nil then kfree(void(cfgCopy));
        kfree(void(ctx));
        if callback <> nil then callback(eOutOfMemory, callbackData);
        exit;
    end;

    format_volume_async := true;
end;

procedure delete_volume(volume : PStorage_Volume);
var
    device : PStorage_Device;
begin
    push_trace('driver.storage.vol.mgr.delete_volume');
    if volume = nil then exit;
    device := volume^.device;
    remove_volume_by_start(device, volume^.sectorStart);
end;

initialization
    boot.mgr.registerBoot('driver.storage.vol.mgr', @init, 'Volume Manager', 'driver.storage.mgr*');

end.
