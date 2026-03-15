//  Copyright 2021 Kieron Morris
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
	Driver->storage->driver.storage.fs.fat32 - driver.storage.fs.fat32 filesystem driver
	
	@author(Aaron Hance <ah@aaronhance.me>)
}

unit driver.storage.fs.fat32;

interface

uses
    boot.mgr,
    driver.storage.fs.mgr,
    core.ds.lists,
    memory.heap,
    proc.mgr,
    proc.types,
    driver.timer.rtc,
    io.stdio,
    driver.storage.mgr,
    driver.storage.types,
    core.strings,
    io.syslog,
    debug.tracer,
    core.util, arch.x86.util,
    driver.storage.vol.mgr;

type 

    TBootRecord = bitpacked record
        jmp2boot        : ubit24;
        OEMName         : array[0..7] of char;
        sectorSize      : uint16;
        spc             : uint8;
        rsvSectors      : uint16;
        numFats         : uint8;
        numDirEnt       : uint16;
        numSectors      : uint16;
        mediaDescp      : uint8;
        sectorsPerFat   : uint16;
        sectorsPerTrack : uint16;
        heads           : uint16;
        hiddenSectors   : uint32;
        manySectors     : uint32;
        FATSize       : uint32;
        flags         : uint16;
        signature     : uint8;
        FATVersion    : uint16;
        rootCluster   : uint32;
        FSInfoCluster : uint16;
        backupCluster : uint16;
        reserved0     : array[0..11] of uint8;
        driveNumber   : uint8;
        reserved1     : uint8;
        bsignature     : uint8;// = $28;
        volumeID      : uint32;
        volumeLabel   : array[0..10] of uint8;
        identString   : array[0..7] of char;// = 'FAT32 ';
    end;
    PBootRecord = ^TBootRecord;

    TFATExtArray = array[0..2] of char;

    TDirectory = packed record
        fileName      : array[0..7] of char;
        fileExtension : TFATExtArray;
        attributes    : uint8;
        reserved0     : uint8;
        timeFine      : uint8;
        time          : uint16;
        date          : uint16;
        accessTime    : uint16;
        clusterHigh   : uint16;
        modifiedTime  : uint16;
        modifiedDate  : uint16;
        clusterLow    : uint16;
        byteSize      : uint32;
    end;
    PDirectory = ^TDirectory;

    TFilesystemInfo = record
        leadSignature   : uint32;
        reserved0       : array[0..479] of uint8;
        structSignature : uint32;
        freeSectors     : uint32;
        nextFreeSector  : uint32;
        reserved1       : array[0..11] of uint8;
        trailSignature  : uint32; 
    end;

    TFatVolumeInfo = record
        sectorsPerCluster : uint8; // must be power of 2 and mult by sectorsize to max 32k
    end;
    PFatVolumeInfo = ^TFatVolumeInfo;

    TClusterExtent = record
        StartCluster : uint32;
        ClusterCount : uint32;
    end;
    PClusterExtent = ^TClusterExtent;

const
    { FAT sector cache — 2-way set-associative, 256 sets, LRU replacement.
      This keeps small-cluster sequential files from churning the FAT cache
      once they grow beyond a few megabytes. }
    FAT_CACHE_SETS = 256;
    FAT_CACHE_WAYS = 2;
    FAT_CACHE_LINES = 512;  { SETS * WAYS }
    FAT_TRANSFER_POOL_CAPACITY = 64;
    FAT_WORK_QUEUE_CAPACITY = FAT_TRANSFER_POOL_CAPACITY;
    FAT_WRITE_PREALLOC_BYTES = 8 * 1024 * 1024;
    FAT_WRITE_PREALLOC_MAX_CLUSTERS = 2048;
    FAT_WRITE_PREALLOC_MIN_CLUSTERS = 64;

type
    TFATCacheLine = record
        SectorIdx : uint32;   { which FAT sector is stored here }
        Dirty     : boolean;  { true if written but not flushed to disk }
        Valid     : boolean;  { true if line contains valid data }
        LRU       : uint8;    { 0 = MRU, 1 = LRU, 2 = LRU (for 3-way), 3 = LRU (for 4-way) }
    end;

    PFATCache = ^TFATCache;
    TFATCache = record
        Lines      : array[0..FAT_CACHE_LINES - 1] of TFATCacheLine;
        Data       : puint32;   { kalloc'd FAT_CACHE_LINES * 512 bytes of FAT sector data }
        EvictBuf   : puint32;   { kalloc'd 512-byte scratch for eviction writes }
        Busy       : boolean;   { spinlock: serializes miss-path eviction+load }
        FatStart   : uint32;    { LBA of first FAT sector on disk }
        Device     : PStorage_Device; { device pointer for I/O }
        BootRecord : PBootRecord;     { cached boot record (read once) }
    end;

    TFATAsyncMode = (famRead, famWrite);

    TFATTransferState = (
        ftsIdle,
        ftsPrepare,
        ftsIssueIO,
        ftsAwaitIO,
        ftsAdvance,
        ftsComplete,
        ftsError
    );

    { Per-file cached metadata created by fat32OpenFile and stored in the
      file descriptor's FSPrivate pointer.  Avoids re-reading boot record,
      directory listing, and searching for the file on every read/write. }
    PFATOpenFile = ^TFATOpenFile;
    PFATVolumeCtx = ^TFATVolumeCtx;
    PFATFileIOAsyncCtx = ^TFATFileIOAsyncCtx;

    TFATOpenFile = record
        Volume       : PStorage_Volume;
        BootRecord   : PBootRecord;    { borrows from TFATCache — do NOT kfree }
        DataStart    : uint32;         { fatDataStartLBA result }
        FirstCluster : uint32;         { file's start cluster (0 if new/empty) }
        ByteSize     : uint32;         { current file size in bytes }
        AllocClusters: uint32;         { current reserved cluster count for appends }
        Extents      : PLinkedListBase;{ cached cluster extents for fast sequential I/O }
        DirCluster   : uint32;         { parent directory's start cluster }
        CleanName    : byteArray8;     { cleaned 8.3 filename }
        ExtPart      : pchar;          { heap-allocated extension string — owned }
        ScratchSector: puint32;        { per-open-file sector scratch buffer }
        ScratchSize  : uint32;         { size of ScratchSector in bytes }
        Exists       : boolean;        { true if file existed at open time }
        FatDirty     : boolean;        { true if FAT cache must be flushed on close }
        MetaDirty    : boolean;        { true if dir entry size/cluster needs sync on close }
    end;

    TFATVolumeCtx = record
        Cache            : TFATCache;
        TransferPoolBuf  : pointer;
        TransferFreeList : pointer;
        Worker           : proc.types.PProcessContext;
        WorkHead         : uint32;
        WorkTail         : uint32;
        WorkCount        : uint32;
        WorkQueue        : array[0..FAT_WORK_QUEUE_CAPACITY - 1] of PFATFileIOAsyncCtx;
    end;

    TFATFileIOAsyncCtx = record
        Next         : PFATFileIOAsyncCtx;
        VolumeCtx    : PFATVolumeCtx;
        State        : TFATTransferState;
        Mode         : TFATAsyncMode;
        Volume       : PStorage_Volume;
        OpenFile     : PFATOpenFile;
        Buffer       : puint32;
        Offset       : uint32;
        ByteCount    : uint32;
        BytesDone    : uint32;
        BytesOut     : puint32;
        Callback     : TIOCallback;
        CallbackData : pointer;
        Cluster      : uint32;
        OrigByteSize : uint32;
        DataStart    : uint32;
        BootRecord   : PBootRecord;
        ChunkBytes   : uint32;
        LastError    : TError;
        CursorValid  : boolean;
        CursorIndex  : uint32;
        CursorCluster: uint32;
        ExtentValid  : boolean;
        ExtentIdx    : uint32;
        ExtentStartIdx : uint32;
    end;

    { Async format state machine steps }
    TFmtStep = (
        fmtBootSector,
        fmtZeroFAT,
        fmtFATEntries,
        fmtRootDir,
        fmtSystemDir,
        fmtDone
    );

    PFmtContext = ^TFmtContext;
    TFmtContext = record
        Step         : TFmtStep;
        Volume       : PStorage_Volume;
        Disk         : PStorage_Device;
        SectorStart  : uint32;
        FATStart     : uint32;
        DataStart    : uint32;
        FATSize      : uint32;
        BatchPos     : uint32;
        BatchSize    : uint32;
        RootCluster  : uint32;
        SPC          : uint32;
        Buffer       : puint32;
        ZeroBuffer   : puint32;
        Callback     : TIOCallback;
        CallbackData : pointer;
    end;

var
    filesystem : TFilesystem;

procedure init;
procedure create_volume(volume : PStorage_Volume; sectors : uint32; start : uint32; config : puint32);
procedure create_volume_async(volume : PStorage_Volume; sectors : uint32; start : uint32; config : puint32; callback : TIOCallback; callbackData : pointer);
procedure detect_volumes(disk : PStorage_Device);
//function writeDirectory(volume : PStorage_volume; directory : pchar; attributes : uint32) : uint8; // need to handle parent table cluster overflow, need to take attributes
//function readDirectory(volume : PStorage_volume; directory : pchar; listPtr : PLinkedListBase) : uint8; //returns: 0 = success, 1 = dir not exsist, 2 = not directory, 3 = error


implementation

{ ---- Module-level I/O caches ---- }
var

    { Sequential I/O chain-position cache: stores the last visited
      (cluster-index, cluster-number) pair so the next call can resume
      instead of walking the entire chain from cluster 0. }
    sioc_vol        : PStorage_Volume = nil;
    sioc_fileClust  : uint32 = 0;
    sioc_chainIdx   : uint32 = 0;
    sioc_chainClust : uint32 = 0;
    sioc_valid      : boolean = false;

    { Free-cluster allocation hint: next findFreeClusters scan starts here
      instead of cluster 2, making sequential allocations O(1). }
    sioc_allocHint  : uint32 = 2;
    sioc_allocVol   : PStorage_Volume = nil;

{ Validate a FAT32 8.3 filename.
  fullName should be in "NAME.EXT" form.
  Returns true if valid: name part 1-8 chars, extension 0-3 chars,
  no illegal characters. }
function isValidFAT32Name(fullName : pchar) : boolean;
var
    i, fnLen, dotPos, nameLen, extLen : uint32;
    c : char;
begin
    isValidFAT32Name := false;
    if fullName = nil then exit;
    fnLen := stringSize(fullName);
    if fnLen = 0 then exit;

    { Find last dot position }
    dotPos := fnLen;
    for i := 0 to fnLen - 1 do begin
        if fullName[i] = '.' then
            dotPos := i;
    end;

    nameLen := dotPos;
    if dotPos < fnLen then
        extLen := fnLen - dotPos - 1
    else
        extLen := 0;

    { Name part must be 1-8 characters }
    if (nameLen < 1) or (nameLen > 8) then exit;
    { Extension part must be 0-3 characters }
    if extLen > 3 then exit;

    { Check all characters for validity }
    for i := 0 to fnLen - 1 do begin
        c := fullName[i];
        if i = dotPos then continue; { skip the dot separator }
        { Reject control characters (< 0x20) except we don't need to check 0 since stringSize stops there }
        if uint8(c) < $20 then exit;
        { Reject illegal FAT32 characters: " * / : < > ? \ | }
        case c of
            '"', '*', '/', ':', '<', '>', '?', '\', '|': exit;
        end;
    end;

    isValidFAT32Name := true;
end;

function load(ptr : void) : boolean;
begin
    io.syslog.logln('FAT32', 'LOADED.')
end;

function matchExtension(dirExt : TFATExtArray; ext : pchar) : boolean;
var
    j : uint32;
    c : char;
    extDone : boolean;
begin
    matchExtension:= true;
    extDone := false;
    for j:=0 to 2 do begin
        if (not extDone) and (ext <> nil) and (ext[j] <> char(0)) then begin
            c:= ext[j];
            { Uppercase a-z to A-Z for case-insensitive FAT32 matching }
            if (c >= 'a') and (c <= 'z') then
                c := char(uint8(c) - 32);
        end else begin
            c:= ' ';
            extDone := true;
        end;
        if dirExt[j] <> c then begin
            matchExtension:= false;
            break;
        end;
    end;
end;

function cleanString(str : pchar; status : puint32) : byteArray8;
var
    i : uint32;
    ii: uint32;
begin
    push_trace('cleanstring()');
    if str = nil then begin
        for i:=0 to 7 do cleanString[i]:= ' ';
        exit;
    end;
    for i:=0 to 7 do begin
        if str[i] = char(0) then begin
            for ii:=i to 7 do begin
                cleanString[ii]:= ' ';
            end;
            break;
        end else begin
            { Uppercase a-z to A-Z for FAT32 }
            if (str[i] >= 'a') and (str[i] <= 'z') then
                cleanString[i]:= char(uint8(str[i]) - 32)
            else
                cleanString[i]:= str[i];
        end;
    end;

end;

{ Split a full filename like 'README.TXT' into name and extension parts.
  Caller must free nameOut and extOut. }
procedure splitFileNameParts(fullName : pchar; var nameOut : pchar; var extOut : pchar);
var
    fnLen, dotPos, i : uint32;
begin
    push_trace('driver.storage.fs.fat32.splitFileNameParts');
    nameOut := nil;
    extOut := nil;
    if fullName = nil then begin
        nameOut := stringNew(0);
        extOut := stringNew(0);
        exit;
    end;
    fnLen := stringSize(fullName);
    dotPos := fnLen;
    for i := 0 to fnLen - 1 do begin
        if fullName[i] = '.' then
            dotPos := i;
    end;
    nameOut := stringTrim(fullName, dotPos);
    if dotPos < fnLen then
        extOut := stringCopy(pchar(@fullName[dotPos + 1]))
    else
        extOut := stringNew(0);
end;    

function cleanStringCha(str : pchar) : pchar;
var
    i : uint32;
    ii: uint32;
begin
    cleanStringCha:= pchar(kalloc(10));
    memset(uint32(cleanstringcha), 0, 10);
    push_trace('cleanstringcha');
    if str = nil then begin
        for i:=0 to 7 do cleanStringCha[i]:= ' ';
        exit;
    end;
    for i:=0 to 7 do begin
        if str[i] = char(0) then begin
            for ii:=i to 7 do begin
                cleanStringCha[ii]:= ' ';
            end;
            break;
        end else begin
                        push_trace('cleanstringcha1.2');
            cleanstringcha[i]:= str[i];

        end;
    end;

end;

function readBootRecord(volume : PStorage_volume) : PBootRecord;
var
    buffer : puint32;
begin
    buffer:= puint32(kalloc(512));
    memset(uint32(buffer), 0, 512);
    driver.storage.mgr.storage_read(volume^.device, volume^.sectorStart + 1, 1, buffer);
    readBootRecord:= PBootRecord(buffer);
end;

{ ---- FAT sector cache ---- }

{ Get or lazily create the per-volume FAT32 context.
  Stores the context pointer in volume^.fsPrivate. }
function fatVolumeCtxGet(volume : PStorage_Volume) : PFATVolumeCtx;
var
    ctx  : PFATVolumeCtx;
    br   : PBootRecord;
    i    : uint32;
    base : uint32;
    tx   : PFATFileIOAsyncCtx;
begin
    fatVolumeCtxGet := nil;
    if volume = nil then exit;

    if volume^.fsPrivate <> nil then begin
        fatVolumeCtxGet := PFATVolumeCtx(volume^.fsPrivate);
        exit;
    end;

    ctx := PFATVolumeCtx(kalloc(sizeof(TFATVolumeCtx)));
    if ctx = nil then exit;
    memset(uint32(ctx), 0, sizeof(TFATVolumeCtx));

    ctx^.Cache.Data := puint32(kalloc(FAT_CACHE_LINES * 512));
    if ctx^.Cache.Data = nil then begin
        kfree(puint32(ctx));
        exit;
    end;
    memset(uint32(ctx^.Cache.Data), 0, FAT_CACHE_LINES * 512);

    ctx^.Cache.EvictBuf := puint32(kalloc(512));
    if ctx^.Cache.EvictBuf = nil then begin
        kfree(ctx^.Cache.Data);
        kfree(puint32(ctx));
        exit;
    end;
    memset(uint32(ctx^.Cache.EvictBuf), 0, 512);

    ctx^.Cache.Busy := false;
    for i := 0 to FAT_CACHE_LINES - 1 do begin
        ctx^.Cache.Lines[i].Valid := false;
        ctx^.Cache.Lines[i].Dirty := false;
        ctx^.Cache.Lines[i].LRU := uint8(i mod FAT_CACHE_WAYS);
    end;

    br := readBootRecord(volume);
    ctx^.Cache.BootRecord := br;
    ctx^.Cache.FatStart := volume^.sectorStart + 1 + br^.rsvSectors;
    ctx^.Cache.Device := volume^.device;

    ctx^.TransferPoolBuf := kalloc(FAT_TRANSFER_POOL_CAPACITY * sizeof(TFATFileIOAsyncCtx));
    if ctx^.TransferPoolBuf <> nil then begin
        base := uint32(ctx^.TransferPoolBuf);
        if FAT_TRANSFER_POOL_CAPACITY > 0 then
            for i := 0 to FAT_TRANSFER_POOL_CAPACITY - 1 do begin
                tx := PFATFileIOAsyncCtx(base + (i * sizeof(TFATFileIOAsyncCtx)));
                tx^.Next := PFATFileIOAsyncCtx(ctx^.TransferFreeList);
                tx^.VolumeCtx := ctx;
                tx^.State := ftsIdle;
                ctx^.TransferFreeList := pointer(tx);
            end;
    end;

    volume^.fsPrivate := pointer(ctx);
    fatVolumeCtxGet := ctx;
end;

{ Get or lazily create the per-volume FAT cache. }
function fatCacheGet(volume : PStorage_Volume) : PFATCache;
var
    ctx : PFATVolumeCtx;
begin
    ctx := fatVolumeCtxGet(volume);
    if ctx = nil then
        fatCacheGet := nil
    else
        fatCacheGet := @ctx^.Cache;
end;

function fatTransferAlloc(volume : PStorage_Volume) : PFATFileIOAsyncCtx;
var
    ctx      : PFATVolumeCtx;
    transfer : PFATFileIOAsyncCtx;
begin
    fatTransferAlloc := nil;
    ctx := fatVolumeCtxGet(volume);
    if ctx = nil then exit;

    asm pushf; cli end;
    transfer := PFATFileIOAsyncCtx(ctx^.TransferFreeList);
    if transfer <> nil then
        ctx^.TransferFreeList := pointer(transfer^.Next);
    asm popf end;

    if transfer = nil then exit;

    memset(uint32(transfer), 0, sizeof(TFATFileIOAsyncCtx));
    transfer^.VolumeCtx := ctx;
    transfer^.State := ftsIdle;
    fatTransferAlloc := transfer;
end;

procedure fatTransferFree(ctx : PFATFileIOAsyncCtx);
var
    volCtx : PFATVolumeCtx;
begin
    if ctx = nil then exit;
    volCtx := ctx^.VolumeCtx;
    if volCtx = nil then exit;

    asm pushf; cli end;
    ctx^.Next := PFATFileIOAsyncCtx(volCtx^.TransferFreeList);
    volCtx^.TransferFreeList := pointer(ctx);
    asm popf end;
end;

function fatWorkerQueuePush(volCtx : PFATVolumeCtx; transfer : PFATFileIOAsyncCtx) : boolean;
begin
    fatWorkerQueuePush := false;
    if (volCtx = nil) or (transfer = nil) then exit;

    asm pushf; cli end;
    if volCtx^.WorkCount < FAT_WORK_QUEUE_CAPACITY then begin
        volCtx^.WorkQueue[volCtx^.WorkTail] := transfer;
        volCtx^.WorkTail := (volCtx^.WorkTail + 1) mod FAT_WORK_QUEUE_CAPACITY;
        volCtx^.WorkCount := volCtx^.WorkCount + 1;
        fatWorkerQueuePush := true;
    end;
    asm popf end;
end;

function fatWorkerQueuePop(volCtx : PFATVolumeCtx; var transfer : PFATFileIOAsyncCtx) : boolean;
begin
    fatWorkerQueuePop := false;
    transfer := nil;
    if volCtx = nil then exit;

    asm pushf; cli end;
    if volCtx^.WorkCount > 0 then begin
        transfer := volCtx^.WorkQueue[volCtx^.WorkHead];
        volCtx^.WorkQueue[volCtx^.WorkHead] := nil;
        volCtx^.WorkHead := (volCtx^.WorkHead + 1) mod FAT_WORK_QUEUE_CAPACITY;
        volCtx^.WorkCount := volCtx^.WorkCount - 1;
        fatWorkerQueuePop := true;
    end;
    asm popf end;
end;

procedure fatWorkerWake(volCtx : PFATVolumeCtx);
begin
    if (volCtx = nil) or (volCtx^.Worker = nil) then exit;

    asm pushf; cli end;
    volCtx^.Worker^.PendingMsg := smCustom;
    volCtx^.Worker^.MsgData := nil;
    if volCtx^.Worker^.State = psAwaiting then
        volCtx^.Worker^.State := psReady;
    asm popf end;
end;

procedure fat32_fileio_async_run_next(ctx : PFATFileIOAsyncCtx); forward;

procedure fat32_transfer_worker(pctx : proc.types.PProcessContext);
var
    volCtx   : PFATVolumeCtx;
    transfer : PFATFileIOAsyncCtx;
begin
    volCtx := PFATVolumeCtx(pctx^.Local);
    if volCtx = nil then begin
        proc.mgr.proc_exit(1);
        exit;
    end;

    while true do begin
        if pctx^.PendingMsg = smTerminate then begin
            pctx^.PendingMsg := smNone;
            proc.mgr.proc_exit(0);
            exit;
        end;

        if fatWorkerQueuePop(volCtx, transfer) then begin
            fat32_fileio_async_run_next(transfer);
            continue;
        end;

        asm pushf; cli end;
        if volCtx^.WorkCount = 0 then begin
            pctx^.PendingMsg := smNone;
            pctx^.State := psAwaiting;
        end;
        asm popf end;

        if pctx^.State = psAwaiting then
            proc.mgr.proc_await;
    end;
end;

procedure fatWorkerEnsure(volume : PStorage_Volume);
var
    volCtx : PFATVolumeCtx;
begin
    volCtx := fatVolumeCtxGet(volume);
    if volCtx = nil then exit;
    if volCtx^.Worker <> nil then exit;
    volCtx^.Worker := proc.mgr.create('fat32.xfer', @fat32_transfer_worker, void(volCtx), 1);
end;

function fatScheduleTransfer(ctx : PFATFileIOAsyncCtx) : boolean;
var
    volCtx : PFATVolumeCtx;
begin
    fatScheduleTransfer := false;
    if ctx = nil then exit;

    volCtx := ctx^.VolumeCtx;
    if volCtx = nil then exit;
    if volCtx^.Worker = nil then exit;

    if fatWorkerQueuePush(volCtx, ctx) then begin
        fatWorkerWake(volCtx);
        fatScheduleTransfer := true;
    end;
end;

{ Flush all dirty cache lines to disk.
  CLI/STI protects cache metadata; disk I/O runs with interrupts enabled. }
procedure fatCacheFlush(cache : PFATCache; volume : PStorage_Volume);
var
    i         : uint32;
    lba       : uint32;
    needFlush : boolean;
begin
    { Acquire Busy lock — protects EvictBuf and prevents concurrent evictions }
    while true do begin
        asm pushf; cli end;
        if not cache^.Busy then begin
            cache^.Busy := true;
            asm popf end;
            break;
        end;
        asm popf end;
        asm hlt end;
    end;

    for i := 0 to FAT_CACHE_LINES - 1 do begin
        asm pushf; cli end;
        needFlush := cache^.Lines[i].Valid and cache^.Lines[i].Dirty;
        if needFlush then begin
            lba := cache^.FatStart + cache^.Lines[i].SectorIdx;
            cache^.Lines[i].Dirty := false;
            core.util.memcpy(uint32(cache^.Data) + (i * 512),
                             uint32(cache^.EvictBuf), 512);
        end;
        asm popf end;

        if needFlush then
            driver.storage.mgr.storage_write(
                cache^.Device, lba, 1, cache^.EvictBuf);
    end;

    { Release lock }
    asm pushf; cli end;
    cache^.Busy := false;
    asm popf end;
end;

{ Invalidate all cache lines (e.g. on unmount). }
procedure fatCacheInvalidate(cache : PFATCache);
var
    i : uint32;
begin
    for i := 0 to FAT_CACHE_LINES - 1 do begin
        cache^.Lines[i].Valid := false;
        cache^.Lines[i].Dirty := false;
        cache^.Lines[i].LRU := uint8(i mod FAT_CACHE_WAYS);
    end;
end;

{ Return the per-volume cached boot record without any allocation.
  The FAT cache lazily reads and keeps a single copy; callers MUST NOT kfree it. }
function getCachedBootRecord(volume : PStorage_Volume) : PBootRecord;
begin
    getCachedBootRecord := fatCacheGet(volume)^.BootRecord;
end;

{ Read a single FAT entry using the sector cache.
  128 FAT entries per 512-byte sector. 2-way set-associative: set = fatSector mod FAT_CACHE_SETS.
  CLI/STI protects cache metadata; disk I/O runs with interrupts enabled. }
function readFat(volume : PStorage_volume; cluster : uint32; bootRecord : PBootRecord) : uint32;
var
    cache       : PFATCache;
    fatSecIdx   : uint32;  { which FAT sector this cluster lives in }
    setIdx      : uint32;  { cache set index }
    baseSlot    : uint32;  { first line index of this set }
    entryOff    : uint32;  { offset within that sector (0..127) }
    dataPtr     : puint32; { pointer into cache data for the hit/victim slot }
    lba         : uint32;
    doEvict     : boolean;
    evictLBA    : uint32;
    w           : uint32;  { way iterator }
    victim      : uint32;  { chosen victim slot index }
begin
    cache := fatCacheGet(volume);
    fatSecIdx := cluster div 128;
    setIdx := fatSecIdx mod FAT_CACHE_SETS;
    baseSlot := setIdx * FAT_CACHE_WAYS;
    entryOff := cluster mod 128;

    { Fast path: cache hit under CLI — check both ways }
    asm pushf; cli end;
    for w := 0 to FAT_CACHE_WAYS - 1 do begin
        if cache^.Lines[baseSlot + w].Valid and (cache^.Lines[baseSlot + w].SectorIdx = fatSecIdx) then begin
            dataPtr := puint32(uint32(cache^.Data) + ((baseSlot + w) * 512));
            readFat := dataPtr[entryOff] and $0FFFFFFF;
            { Update LRU: this way is MRU }
            cache^.Lines[baseSlot + w].LRU := 0;
            cache^.Lines[baseSlot + (1 - w)].LRU := 1;
            asm popf end;
            exit;
        end;
    end;
    asm popf end;

    { Miss path: acquire Busy spinlock to serialize eviction+load }
    while true do begin
        asm pushf; cli end;
        if not cache^.Busy then begin
            { Re-check for hit — another process may have loaded this sector }
            for w := 0 to FAT_CACHE_WAYS - 1 do begin
                if cache^.Lines[baseSlot + w].Valid and (cache^.Lines[baseSlot + w].SectorIdx = fatSecIdx) then begin
                    dataPtr := puint32(uint32(cache^.Data) + ((baseSlot + w) * 512));
                    readFat := dataPtr[entryOff] and $0FFFFFFF;
                    cache^.Lines[baseSlot + w].LRU := 0;
                    cache^.Lines[baseSlot + (1 - w)].LRU := 1;
                    asm popf end;
                    exit;
                end;
            end;
            cache^.Busy := true;
            { Pick victim: prefer invalid way, else LRU way }
            victim := baseSlot;
            if (not cache^.Lines[baseSlot].Valid) then
                victim := baseSlot
            else if (not cache^.Lines[baseSlot + 1].Valid) then
                victim := baseSlot + 1
            else if cache^.Lines[baseSlot + 1].LRU >= cache^.Lines[baseSlot].LRU then
                victim := baseSlot + 1
            else
                victim := baseSlot;
            dataPtr := puint32(uint32(cache^.Data) + (victim * 512));
            doEvict := cache^.Lines[victim].Valid and cache^.Lines[victim].Dirty;
            if doEvict then begin
                evictLBA := cache^.FatStart + cache^.Lines[victim].SectorIdx;
                core.util.memcpy(uint32(dataPtr), uint32(cache^.EvictBuf), 512);
            end;
            cache^.Lines[victim].Valid := false;
            asm popf end;
            break;
        end;
        asm popf end;
        asm hlt end;
    end;

    { Disk I/O with interrupts enabled — exclusive via Busy flag }
    if doEvict then
        driver.storage.mgr.storage_write(cache^.Device, evictLBA, 1, cache^.EvictBuf);
    lba := cache^.FatStart + fatSecIdx;
    driver.storage.mgr.storage_read(cache^.Device, lba, 1, dataPtr);

    { Update cache metadata, set LRU, release lock under CLI }
    asm pushf; cli end;
    cache^.Lines[victim].SectorIdx := fatSecIdx;
    cache^.Lines[victim].Valid := true;
    cache^.Lines[victim].Dirty := false;
    { New entry is MRU, the other way is LRU }
    cache^.Lines[victim].LRU := 0;
    if victim = baseSlot then
        cache^.Lines[baseSlot + 1].LRU := 1
    else
        cache^.Lines[baseSlot].LRU := 1;
    readFat := dataPtr[entryOff] and $0FFFFFFF;
    cache^.Busy := false;
    asm popf end;
end;

{ Write a single FAT entry into cache. No immediate disk I/O — call fatCacheFlush later.
  2-way set-associative: set = fatSector mod FAT_CACHE_SETS.
  CLI/STI protects cache metadata; disk I/O runs with interrupts enabled. }
procedure writeFat(volume : PStorage_volume; cluster : uint32; value : uint32; bootRecord : PBootRecord);
var
    cache       : PFATCache;
    fatSecIdx   : uint32;
    setIdx      : uint32;
    baseSlot    : uint32;
    entryOff    : uint32;
    dataPtr     : puint32;
    lba         : uint32;
    doEvict     : boolean;
    evictLBA    : uint32;
    w           : uint32;
    victim      : uint32;
begin
    cache := fatCacheGet(volume);
    fatSecIdx := cluster div 128;
    setIdx := fatSecIdx mod FAT_CACHE_SETS;
    baseSlot := setIdx * FAT_CACHE_WAYS;
    entryOff := cluster mod 128;

    { Fast path: cache hit — check both ways }
    asm pushf; cli end;
    for w := 0 to FAT_CACHE_WAYS - 1 do begin
        if cache^.Lines[baseSlot + w].Valid and (cache^.Lines[baseSlot + w].SectorIdx = fatSecIdx) then begin
            dataPtr := puint32(uint32(cache^.Data) + ((baseSlot + w) * 512));
            if value = 0 then
                dataPtr[entryOff] := 0
            else
                dataPtr[entryOff] := (dataPtr[entryOff] and $F0000000) or (value and $0FFFFFFF);
            cache^.Lines[baseSlot + w].Dirty := true;
            { Update LRU: this way is MRU }
            cache^.Lines[baseSlot + w].LRU := 0;
            cache^.Lines[baseSlot + (1 - w)].LRU := 1;
            asm popf end;
            exit;
        end;
    end;
    asm popf end;

    { Miss path: acquire Busy spinlock }
    while true do begin
        asm pushf; cli end;
        if not cache^.Busy then begin
            { Re-check for hit after acquiring lock }
            for w := 0 to FAT_CACHE_WAYS - 1 do begin
                if cache^.Lines[baseSlot + w].Valid and (cache^.Lines[baseSlot + w].SectorIdx = fatSecIdx) then begin
                    dataPtr := puint32(uint32(cache^.Data) + ((baseSlot + w) * 512));
                    if value = 0 then
                        dataPtr[entryOff] := 0
                    else
                        dataPtr[entryOff] := (dataPtr[entryOff] and $F0000000) or (value and $0FFFFFFF);
                    cache^.Lines[baseSlot + w].Dirty := true;
                    cache^.Lines[baseSlot + w].LRU := 0;
                    cache^.Lines[baseSlot + (1 - w)].LRU := 1;
                    asm popf end;
                    exit;
                end;
            end;
            cache^.Busy := true;
            { Pick victim: prefer invalid way, else LRU way }
            victim := baseSlot;
            if (not cache^.Lines[baseSlot].Valid) then
                victim := baseSlot
            else if (not cache^.Lines[baseSlot + 1].Valid) then
                victim := baseSlot + 1
            else if cache^.Lines[baseSlot + 1].LRU >= cache^.Lines[baseSlot].LRU then
                victim := baseSlot + 1
            else
                victim := baseSlot;
            dataPtr := puint32(uint32(cache^.Data) + (victim * 512));
            doEvict := cache^.Lines[victim].Valid and cache^.Lines[victim].Dirty;
            if doEvict then begin
                evictLBA := cache^.FatStart + cache^.Lines[victim].SectorIdx;
                core.util.memcpy(uint32(dataPtr), uint32(cache^.EvictBuf), 512);
            end;
            cache^.Lines[victim].Valid := false;
            asm popf end;
            break;
        end;
        asm popf end;
        asm hlt end;
    end;

    { Disk I/O with interrupts enabled — exclusive via Busy flag }
    if doEvict then
        driver.storage.mgr.storage_write(cache^.Device, evictLBA, 1, cache^.EvictBuf);
    lba := cache^.FatStart + fatSecIdx;
    driver.storage.mgr.storage_read(cache^.Device, lba, 1, dataPtr);

    { Update cache, write value, set LRU, release lock under CLI }
    asm pushf; cli end;
    cache^.Lines[victim].SectorIdx := fatSecIdx;
    cache^.Lines[victim].Valid := true;
    cache^.Lines[victim].Dirty := false;
    if value = 0 then
        dataPtr[entryOff] := 0
    else
        dataPtr[entryOff] := (dataPtr[entryOff] and $F0000000) or (value and $0FFFFFFF);
    cache^.Lines[victim].Dirty := true;
    cache^.Lines[victim].LRU := 0;
    if victim = baseSlot then
        cache^.Lines[baseSlot + 1].LRU := 1
    else
        cache^.Lines[baseSlot].LRU := 1;
    cache^.Busy := false;
    asm popf end;
end;

function getFatChain(volume : PStorage_volume; cluster : uint32; bootRecord : PBootRecord) : PLinkedListBase;
var
    currentCluster      : uint32;
    currentClusterValue : uint32;
    clusters            : PLinkedListBase;
    dirElm              : puint32;
    maxCluster          : uint32;
    iterCount           : uint32;
begin
    clusters:= LL_New(sizeof(uint32));
    currentCluster:= cluster;
    currentClusterValue:= cluster;
    if bootRecord^.sectorSize > 0 then
        maxCluster := (bootRecord^.FATSize * bootRecord^.sectorSize) div 4
    else
        maxCluster := 0;
    iterCount := 0;

    while true do begin
        if (maxCluster > 0) and (iterCount >= maxCluster) then
            break;
        currentClusterValue:= readFat(volume, currentClusterValue, bootRecord);

        if (currentClusterValue and $0FFFFFFF) = $0FFFFFF7 then begin
            break;
        end else if (currentClusterValue and $0FFFFFFF) >= $0FFFFFF8 then begin
            dirElm:= LL_add(clusters);
            dirElm^:= currentCluster;
            break;
        end else if currentClusterValue = 0 then begin
            break;
        end else begin
            dirElm:= LL_add(clusters);
            dirElm^:= currentCluster;
        end;

        currentCluster := currentClusterValue;
        iterCount := iterCount + 1;
    end;

    getFatChain:= clusters;
end;

function fatMaxClusterCount(bootRecord : PBootRecord) : uint32;
begin
    if (bootRecord <> nil) and (bootRecord^.sectorSize > 0) then
        fatMaxClusterCount := (bootRecord^.FATSize * bootRecord^.sectorSize) div 4
    else
        fatMaxClusterCount := 0;
end;

function fatDefaultSPC(sectors : uint32; sectorSize : uint32) : uint32;
begin
    if sectorSize = 0 then begin
        fatDefaultSPC := 1;
        exit;
    end;

    { Default to 4 KiB clusters for sane FAT32 throughput without excessive
      slack on small files. Callers can still override via config. }
    fatDefaultSPC := 4096 div sectorSize;
    if fatDefaultSPC = 0 then
        fatDefaultSPC := 1;
    if fatDefaultSPC > 64 then
        fatDefaultSPC := 64;
end;

function fatComputeFATSize(sectors : uint32; spc : uint32; sectorSize : uint32) : uint32;
var
    clusterCount : uint32;
    fatBytes     : uint32;
begin
    if spc = 0 then
        spc := 1;
    if sectorSize = 0 then begin
        fatComputeFATSize := 0;
        exit;
    end;

    clusterCount := (sectors + spc - 1) div spc;
    fatBytes := clusterCount * 4;
    fatComputeFATSize := (fatBytes + sectorSize - 1) div sectorSize;
    if fatComputeFATSize = 0 then
        fatComputeFATSize := 1;
end;

function fatClustersForBytes(byteCount : uint32; bytesPerCluster : uint32) : uint32;
begin
    if (byteCount = 0) or (bytesPerCluster = 0) then begin
        fatClustersForBytes := 0;
        exit;
    end;

    fatClustersForBytes := (byteCount + bytesPerCluster - 1) div bytesPerCluster;
end;

function fatPreallocClusterCount(bytesPerCluster : uint32) : uint32;
begin
    if bytesPerCluster = 0 then begin
        fatPreallocClusterCount := 1;
        exit;
    end;

    fatPreallocClusterCount := FAT_WRITE_PREALLOC_BYTES div bytesPerCluster;
    if fatPreallocClusterCount = 0 then
        fatPreallocClusterCount := 1;
    if fatPreallocClusterCount < FAT_WRITE_PREALLOC_MIN_CLUSTERS then
        fatPreallocClusterCount := FAT_WRITE_PREALLOC_MIN_CLUSTERS;
    if fatPreallocClusterCount > FAT_WRITE_PREALLOC_MAX_CLUSTERS then
        fatPreallocClusterCount := FAT_WRITE_PREALLOC_MAX_CLUSTERS;
end;

procedure fatUpdateAllocHint(volume : PStorage_volume; bootRecord : PBootRecord; nextCluster : uint32);
var
    maxCluster : uint32;
begin
    maxCluster := fatMaxClusterCount(bootRecord);
    if maxCluster <= 2 then begin
        sioc_allocHint := 2;
        sioc_allocVol := volume;
        exit;
    end;

    if nextCluster < 2 then
        nextCluster := 2;
    if nextCluster >= maxCluster then
        nextCluster := 2;

    sioc_allocHint := nextCluster;
    sioc_allocVol := volume;
end;

function fatTryContiguousRange(volume : PStorage_volume; bootRecord : PBootRecord;
                               rangeStart : uint32; rangeEnd : uint32; needed : uint32;
                               var foundStart : uint32) : boolean;
var
    scanPos : uint32;
    runLen  : uint32;
    runPos  : uint32;
    fatVal  : uint32;
begin
    fatTryContiguousRange := false;
    if (needed = 0) or (bootRecord = nil) or (rangeStart >= rangeEnd) then
        exit;

    scanPos := rangeStart;
    runLen := 0;
    runPos := 0;

    while scanPos < rangeEnd do begin
        fatVal := readFat(volume, scanPos, bootRecord);
        if fatVal = 0 then begin
            if runLen = 0 then
                runPos := scanPos;
            runLen := runLen + 1;
            if runLen >= needed then begin
                foundStart := runPos;
                fatTryContiguousRange := true;
                exit;
            end;
        end else
            runLen := 0;
        scanPos := scanPos + 1;
    end;
end;

function fatFindContiguousFreeRange(volume : PStorage_volume; amount : uint32;
                                    bootRecord : PBootRecord; var runStart : uint32) : boolean;
var
    scanStart  : uint32;
    maxCluster : uint32;
begin
    fatFindContiguousFreeRange := false;
    if amount = 0 then exit;

    maxCluster := fatMaxClusterCount(bootRecord);
    if maxCluster <= 2 then exit;

    if (sioc_allocVol = volume) and (sioc_allocHint >= 2) and (sioc_allocHint < maxCluster) then
        scanStart := sioc_allocHint
    else
        scanStart := 2;

    if fatTryContiguousRange(volume, bootRecord, scanStart, maxCluster, amount, runStart) or
       ((scanStart > 2) and fatTryContiguousRange(volume, bootRecord, 2, scanStart, amount, runStart)) then
        fatFindContiguousFreeRange := true;
end;

procedure fatLinkContiguousRange(volume : PStorage_volume; bootRecord : PBootRecord;
                                 previousTail : uint32; firstCluster : uint32; clusterCount : uint32;
                                 var lastCluster : uint32);
var
    cur : uint32;
    i   : uint32;
begin
    lastCluster := previousTail;
    if clusterCount = 0 then exit;

    if previousTail <> 0 then
        writeFat(volume, previousTail, firstCluster, bootRecord);

    cur := firstCluster;
    i := 1;
    while i < clusterCount do begin
        writeFat(volume, cur, cur + 1, bootRecord);
        cur := cur + 1;
        i := i + 1;
    end;

    writeFat(volume, cur, $FFFFFFF8, bootRecord);
    lastCluster := cur;
    fatUpdateAllocHint(volume, bootRecord, lastCluster + 1);
end;

function fatAppendExtent(extents : PLinkedListBase; firstCluster : uint32;
                         clusterCount : uint32) : boolean;
var
    ext      : PClusterExtent;
    lastExt  : PClusterExtent;
    extCount : uint32;
begin
    fatAppendExtent := false;
    if (extents = nil) or (clusterCount = 0) then
        exit;

    extCount := LL_Size(extents);
    if extCount > 0 then begin
        lastExt := PClusterExtent(LL_Get(extents, extCount - 1));
        if (lastExt <> nil) and ((lastExt^.StartCluster + lastExt^.ClusterCount) = firstCluster) then begin
            lastExt^.ClusterCount := lastExt^.ClusterCount + clusterCount;
            fatAppendExtent := true;
            exit;
        end;
    end;

    ext := PClusterExtent(LL_Add(extents));
    if ext = nil then
        exit;
    ext^.StartCluster := firstCluster;
    ext^.ClusterCount := clusterCount;
    fatAppendExtent := true;
end;

function fatBuildExtentList(volume : PStorage_volume; cluster : uint32;
                            bootRecord : PBootRecord) : PLinkedListBase;
var
    extents      : PLinkedListBase;
    current      : uint32;
    nextCluster  : uint32;
    runStart     : uint32;
    runCount     : uint32;
    maxCluster   : uint32;
    iterCount    : uint32;
begin
    fatBuildExtentList := nil;
    if (bootRecord = nil) or (cluster < 2) then
        exit;

    extents := LL_New(sizeof(TClusterExtent));
    if extents = nil then
        exit;

    if bootRecord^.sectorSize > 0 then
        maxCluster := (bootRecord^.FATSize * bootRecord^.sectorSize) div 4
    else
        maxCluster := 0;

    current := cluster;
    runStart := cluster;
    runCount := 1;
    iterCount := 0;

    while true do begin
        if (maxCluster > 0) and (iterCount >= maxCluster) then
            break;

        nextCluster := readFat(volume, current, bootRecord);
        if (nextCluster = 0) or ((nextCluster and $0FFFFFFF) = $0FFFFFF7) then
            break;

        if (nextCluster and $0FFFFFFF) >= $0FFFFFF8 then begin
            if not fatAppendExtent(extents, runStart, runCount) then begin
                LL_Free(extents);
                exit;
            end;
            fatBuildExtentList := extents;
            exit;
        end;

        if nextCluster = (current + 1) then
            runCount := runCount + 1
        else begin
            if not fatAppendExtent(extents, runStart, runCount) then begin
                LL_Free(extents);
                exit;
            end;
            runStart := nextCluster;
            runCount := 1;
        end;

        current := nextCluster;
        iterCount := iterCount + 1;
    end;

    if runCount > 0 then begin
        if not fatAppendExtent(extents, runStart, runCount) then begin
            LL_Free(extents);
            exit;
        end;
    end;

    fatBuildExtentList := extents;
end;

function fatLocateExtentRun(extents : PLinkedListBase; targetIdx : uint32;
                            hintValid : boolean; hintExtentIdx : uint32;
                            hintStartIdx : uint32; var runStartCluster : uint32;
                            var runClusterCount : uint32; var outExtentIdx : uint32;
                            var outExtentStartIdx : uint32) : boolean;
var
    i         : uint32;
    clusterIx : uint32;
    extCount  : uint32;
    ext       : PClusterExtent;
begin
    fatLocateExtentRun := false;
    if extents = nil then
        exit;

    extCount := LL_Size(extents);
    if extCount = 0 then
        exit;

    if hintValid and (hintExtentIdx < extCount) and (hintStartIdx <= targetIdx) then begin
        i := hintExtentIdx;
        clusterIx := hintStartIdx;
    end else begin
        i := 0;
        clusterIx := 0;
    end;

    while i < extCount do begin
        ext := PClusterExtent(LL_Get(extents, i));
        if ext = nil then
            exit;

        if targetIdx < (clusterIx + ext^.ClusterCount) then begin
            runStartCluster := ext^.StartCluster + (targetIdx - clusterIx);
            runClusterCount := ext^.ClusterCount - (targetIdx - clusterIx);
            outExtentIdx := i;
            outExtentStartIdx := clusterIx;
            fatLocateExtentRun := true;
            exit;
        end;

        clusterIx := clusterIx + ext^.ClusterCount;
        i := i + 1;
    end;
end;

function findFreeClusterExtents(volume : PStorage_volume; amount : uint32;
                                bootRecord : PBootRecord) : PLinkedListBase;
var
    maxCluster    : uint32;
    scanStart     : uint32;
    currentAmount : uint32;
    lastAllocated : uint32;
    extents       : PLinkedListBase;

    procedure appendExtent(firstCluster : uint32; clusterCount : uint32);
    var
        ext : PClusterExtent;
    begin
        ext := PClusterExtent(LL_Add(extents));
        ext^.StartCluster := firstCluster;
        ext^.ClusterCount := clusterCount;
        currentAmount := currentAmount + clusterCount;
        lastAllocated := firstCluster + clusterCount - 1;
    end;

    procedure scanRange(rangeStart : uint32; rangeEnd : uint32);
    var
        scanPos   : uint32;
        runStart  : uint32;
        runLen    : uint32;
        takeCount : uint32;
        fatVal    : uint32;
    begin
        scanPos := rangeStart;
        while (scanPos < rangeEnd) and (currentAmount < amount) do begin
            fatVal := readFat(volume, scanPos, bootRecord);
            if fatVal <> 0 then begin
                scanPos := scanPos + 1;
                continue;
            end;

            runStart := scanPos;
            runLen := 0;
            while scanPos < rangeEnd do begin
                fatVal := readFat(volume, scanPos, bootRecord);
                if fatVal <> 0 then
                    break;
                runLen := runLen + 1;
                scanPos := scanPos + 1;
            end;

            takeCount := amount - currentAmount;
            if runLen < takeCount then
                takeCount := runLen;
            appendExtent(runStart, takeCount);
        end;
    end;
begin
    extents := LL_New(sizeof(TClusterExtent));
    currentAmount := 0;
    lastAllocated := 0;

    if amount = 0 then begin
        findFreeClusterExtents := extents;
        exit;
    end;

    maxCluster := fatMaxClusterCount(bootRecord);
    if maxCluster <= 2 then begin
        LL_Free(extents);
        findFreeClusterExtents := nil;
        exit;
    end;

    if (sioc_allocVol = volume) and (sioc_allocHint >= 2) and (sioc_allocHint < maxCluster) then
        scanStart := sioc_allocHint
    else
        scanStart := 2;

    scanRange(scanStart, maxCluster);
    if (currentAmount < amount) and (scanStart > 2) then
        scanRange(2, scanStart);

    if currentAmount < amount then begin
        LL_Free(extents);
        findFreeClusterExtents := nil;
        exit;
    end;

    fatUpdateAllocHint(volume, bootRecord, lastAllocated + 1);
    findFreeClusterExtents := extents;
end;

function compareByteArray8(str1 : byteArray8; str2 : byteArray8) : boolean;
var
    i : uint32;
begin
    push_trace('driver.storage.fs.fat32.compareArray');
    compareByteArray8:= true;
    for i:=0 to 7 do begin
        if str1[i] <> str2[i] then begin
            compareByteArray8:= false;
            break;
        end;
    end;
end;

{ Extract the starting cluster number from a directory entry. }
function dirFirstCluster(dir : PDirectory) : uint32;
begin
    dirFirstCluster := uint32(dir^.clusterLow) or uint32(dir^.clusterHigh shl 16);
end;

{ Set the starting cluster number in a directory entry. }
procedure setDirFirstCluster(dir : PDirectory; cluster : uint32);
begin
    dir^.clusterLow := uint16(cluster and $FFFF);
    dir^.clusterHigh := uint16((cluster shr 16) and $FFFF);
end;

{ Calculate the LBA of the first data sector on a FAT32 volume. }
function fatDataStartLBA(volume : PStorage_Volume; bootRecord : PBootRecord) : uint32;
begin
    fatDataStartLBA := volume^.sectorStart + 1 + bootRecord^.rsvSectors + bootRecord^.FATSize;
end;

{ Convert a cluster number to its starting LBA. }
function clusterToLBA(dataStart : uint32; spc : uint32; cluster : uint32) : uint32;
begin
    clusterToLBA := dataStart + (cluster * spc);
end;

{ Write an 8.3 extension into a TFATExtArray: uppercase, pad with spaces. }
procedure fillFatExt(var dest : TFATExtArray; extPart : pchar);
var
    j : uint32;
begin
    dest[0] := ' ';
    dest[1] := ' ';
    dest[2] := ' ';
    if (extPart <> nil) and (extPart[0] <> char(0)) then begin
        for j := 0 to 2 do begin
            if extPart[j] = char(0) then break;
            if (extPart[j] >= 'a') and (extPart[j] <= 'z') then
                dest[j] := char(uint8(extPart[j]) - 32)
            else
                dest[j] := extPart[j];
        end;
    end;
end;

{ Search a single sector buffer for a directory entry matching name+ext.
  Returns the index (0..entriesPerSec-1), or -1 if not found.
  Sets hitEnd to true if a char(0) sentinel was reached (end of directory). }
function findEntryInSector(buffer : puint32; entriesPerSec : uint32;
    name : byteArray8; ext : pchar; var hitEnd : boolean) : integer;
var
    idx : uint32;
    dir : PDirectory;
begin
    findEntryInSector := -1;
    hitEnd := false;
    if entriesPerSec > 0 then
    for idx := 0 to entriesPerSec - 1 do begin
        dir := @PDirectory(buffer)[idx];
        if dir^.fileName[0] = char(0) then begin
            hitEnd := true;
            exit;
        end;
        if dir^.fileName[0] = char($E5) then continue;
        if compareByteArray8(dir^.fileName, name)
           and matchExtension(dir^.fileExtension, ext) then begin
            findEntryInSector := integer(idx);
            exit;
        end;
    end;
end;

{ Search a single sector buffer for a free directory entry (char(0) or $E5).
  Returns the index (0..entriesPerSec-1), or -1 if sector is full. }
function findFreeEntryInSector(buffer : puint32; entriesPerSec : uint32) : integer;
var
    idx : uint32;
    dir : PDirectory;
begin
    findFreeEntryInSector := -1;
    if entriesPerSec > 0 then
    for idx := 0 to entriesPerSec - 1 do begin
        dir := @PDirectory(buffer)[idx];
        if (dir^.fileName[0] = char(0)) or (dir^.fileName[0] = char($E5)) then begin
            findFreeEntryInSector := integer(idx);
            exit;
        end;
    end;
end;

{ --- Higher-level helpers --- }

type
    TDirEntryLocation = record
        Found      : boolean;
        SectorLBA  : uint32;
        EntryIdx   : uint32;
    end;

    TFileLookup = record
        BootRecord : PBootRecord;
        Dirs       : PLinkedListBase;
        Dir        : PDirectory;
        Exists     : boolean;
        Status     : puint32;
    end;

    TRunInfo = record
        StartCluster : uint32;
        LastCluster  : uint32;
        RunLen       : uint32;
        RunSectors   : uint32;
        RunBytes     : uint32;
        LBA          : uint32;
    end;

{ Locate a named entry in the parent directory's raw sectors.
  Walks the full FAT chain of parentCluster, scanning each sector
  with findEntryInSector.  On match, fills loc and leaves buffer
  containing the matching sector (caller must kfree buffer).
  Returns true if found. }
function locateDirEntry(
    volume        : PStorage_Volume;
    parentCluster : uint32;
    bootRecord    : PBootRecord;
    cleanName     : byteArray8;
    ext           : pchar;
    var loc       : TDirEntryLocation;
    buffer        : puint32
) : boolean;
var
    dataStart        : uint32;
    spc              : uint32;
    entriesPerSector : uint32;
    dirChain         : PLinkedListBase;
    dc               : uint32;
    ds               : uint32;
    curCluster       : uint32;
    clusterLBA       : uint32;
    hitEnd           : boolean;
    entryIdx         : integer;
    done             : boolean;
begin
    locateDirEntry := false;
    loc.Found := false;

    dataStart := fatDataStartLBA(volume, bootRecord);
    spc := uint32(bootRecord^.spc);
    entriesPerSector := uint32(bootRecord^.sectorSize) div uint32(sizeof(TDirectory));
    dirChain := getFatChain(volume, parentCluster, bootRecord);
    done := false;

    dc := 0;
    while (dc < LL_size(dirChain)) and (not done) do begin
        curCluster := puint32(LL_Get(dirChain, dc))^;
        clusterLBA := clusterToLBA(dataStart, spc, curCluster);
        ds := 0;
        while (ds < spc) and (not done) do begin
            driver.storage.mgr.storage_read(volume^.device, clusterLBA + ds, 1, buffer);
            entryIdx := findEntryInSector(buffer, entriesPerSector, cleanName, ext, hitEnd);
            if hitEnd then
                done := true
            else if entryIdx >= 0 then begin
                loc.Found     := true;
                loc.SectorLBA := clusterLBA + ds;
                loc.EntryIdx  := uint32(entryIdx);
                done := true;
            end;
            ds := ds + 1;
        end;
        dc := dc + 1;
    end;

    LL_Free(dirChain);
    locateDirEntry := loc.Found;
end;

{ Locate an unused (free) directory entry slot in the parent directory.
  Returns true if a free slot was found, filling loc and leaving buffer
  containing the sector. }
function locateFreeDirEntry(
    volume        : PStorage_Volume;
    parentCluster : uint32;
    bootRecord    : PBootRecord;
    var loc       : TDirEntryLocation;
    buffer        : puint32
) : boolean;
var
    dataStart        : uint32;
    spc              : uint32;
    entriesPerSector : uint32;
    dirChain         : PLinkedListBase;
    dc               : uint32;
    ds               : uint32;
    curCluster       : uint32;
    clusterLBA       : uint32;
    entryIdx         : integer;
    found            : boolean;
begin
    locateFreeDirEntry := false;
    loc.Found := false;

    dataStart := fatDataStartLBA(volume, bootRecord);
    spc := uint32(bootRecord^.spc);
    entriesPerSector := uint32(bootRecord^.sectorSize) div uint32(sizeof(TDirectory));
    dirChain := getFatChain(volume, parentCluster, bootRecord);
    found := false;

    if LL_size(dirChain) > 0 then begin
        for dc := 0 to LL_size(dirChain) - 1 do begin
            curCluster := puint32(LL_Get(dirChain, dc))^;
            clusterLBA := clusterToLBA(dataStart, spc, curCluster);
            for ds := 0 to spc - 1 do begin
                driver.storage.mgr.storage_read(volume^.device, clusterLBA + ds, 1, buffer);
                entryIdx := findFreeEntryInSector(buffer, entriesPerSector);
                if entryIdx >= 0 then begin
                    loc.Found     := true;
                    loc.SectorLBA := clusterLBA + ds;
                    loc.EntryIdx  := uint32(entryIdx);
                    found := true;
                end;
                if found then break;
            end;
            if found then break;
        end;
    end;

    LL_Free(dirChain);
    locateFreeDirEntry := loc.Found;
end;

{ Build a contiguous cluster run starting at startCluster.
  Scans ahead via readFat, accumulating consecutive clusters up to
  maxRunSectors worth of sectors.
  Returns the number of clusters in the run (runLen).
  Sets lastCluster to the last cluster in the run (= startCluster + runLen - 1). }
function buildContiguousRun(
    volume        : PStorage_Volume;
    startCluster  : uint32;
    spc           : uint32;
    maxRunSectors : uint32;
    bootRecord    : PBootRecord;
    var runLen    : uint32;
    var lastCluster : uint32
) : uint32;
var
    nextFat : uint32;
begin
    runLen := 1;
    lastCluster := startCluster;

    while (runLen * spc) < maxRunSectors do begin
        nextFat := readFat(volume, lastCluster, bootRecord);
        if ((nextFat and $0FFFFFFF) >= $0FFFFFF8) or (nextFat = 0) then
            break;
        if nextFat <> lastCluster + 1 then
            break;
        lastCluster := nextFat;
        runLen := runLen + 1;
    end;

    buildContiguousRun := runLen;
end;

procedure updateSIOC(
    volume           : PStorage_Volume;
    fileStartCluster : uint32;
    chainIdx         : uint32;
    chainCluster     : uint32
); forward;

function seekToClusterIndex(
    volume           : PStorage_Volume;
    fileStartCluster : uint32;
    targetIdx        : uint32;
    bootRecord       : PBootRecord;
    var curCluster   : uint32;
    var chainPos     : uint32
) : boolean; forward;

function seekToClusterIndexHinted(
    volume           : PStorage_Volume;
    fileStartCluster : uint32;
    targetIdx        : uint32;
    bootRecord       : PBootRecord;
    hintValid        : boolean;
    hintIdx          : uint32;
    hintCluster      : uint32;
    var curCluster   : uint32;
    var chainPos     : uint32
) : boolean; forward;

procedure fat32_fileio_async_complete(ctx : PFATFileIOAsyncCtx; error : TError);
begin
    if ctx = nil then exit;
    if ctx^.BytesOut <> nil then
        ctx^.BytesOut^ := ctx^.BytesDone;
    if ctx^.Callback <> nil then
        ctx^.Callback(error, ctx^.CallbackData);
    fatTransferFree(ctx);
end;

function fat32_fileio_prepare_single_run(ctx : PFATFileIOAsyncCtx;
    var sectorLBA : uint32; var chunkSectors : uint32) : boolean;
const
    MAX_RUN_SECTORS = 2048;
var
    run             : TRunInfo;
    curCluster      : uint32;
    chainPos        : uint32;
    currentOffset   : uint32;
    bytesPerCluster : uint32;
    startClusterIdx : uint32;
    inClusterOffset : uint32;
    remaining       : uint32;
    skipBytes       : uint32;
    copyBytes       : uint32;
    secSize         : uint32;
    spc             : uint32;
    lastBytePos     : uint32;
    lastClusterUsed : uint32;
    lastClusterIdx  : uint32;
    maxRunClusters  : uint32;
    extentIdx       : uint32;
    extentStartIdx  : uint32;
begin
    fat32_fileio_prepare_single_run := false;
    if ctx = nil then
        exit;

    currentOffset := ctx^.Offset + ctx^.BytesDone;
    remaining := ctx^.ByteCount - ctx^.BytesDone;
    spc := uint32(ctx^.BootRecord^.spc);
    secSize := uint32(ctx^.BootRecord^.sectorSize);
    bytesPerCluster := spc * secSize;
    startClusterIdx := currentOffset div bytesPerCluster;
    inClusterOffset := currentOffset mod bytesPerCluster;

    maxRunClusters := MAX_RUN_SECTORS div spc;
    if maxRunClusters = 0 then
        maxRunClusters := 1;

    if (ctx^.OpenFile <> nil) and (ctx^.OpenFile^.Extents <> nil) and
       fatLocateExtentRun(ctx^.OpenFile^.Extents, startClusterIdx,
           ctx^.ExtentValid, ctx^.ExtentIdx, ctx^.ExtentStartIdx,
           run.StartCluster, run.RunLen, extentIdx, extentStartIdx) then begin
        if run.RunLen > maxRunClusters then
            run.RunLen := maxRunClusters;
        run.LastCluster := run.StartCluster + run.RunLen - 1;
        ctx^.ExtentValid := true;
        ctx^.ExtentIdx := extentIdx;
        ctx^.ExtentStartIdx := extentStartIdx;
        curCluster := run.LastCluster;
        chainPos := startClusterIdx + run.RunLen - 1;
    end else begin
        if not seekToClusterIndexHinted(
            ctx^.Volume, ctx^.Cluster, startClusterIdx, ctx^.BootRecord,
            ctx^.CursorValid, ctx^.CursorIndex, ctx^.CursorCluster,
            curCluster, chainPos) then
            exit;

        run.StartCluster := curCluster;
        buildContiguousRun(ctx^.Volume, curCluster, spc, MAX_RUN_SECTORS, ctx^.BootRecord, run.RunLen, run.LastCluster);
    end;

    run.RunSectors := run.RunLen * spc;
    run.RunBytes := run.RunSectors * secSize;
    run.LBA := clusterToLBA(ctx^.DataStart, spc, run.StartCluster);

    skipBytes := inClusterOffset;
    copyBytes := run.RunBytes - skipBytes;
    if copyBytes > remaining then
        copyBytes := remaining;

    if (copyBytes = 0) or ((copyBytes mod secSize) <> 0) or ((skipBytes mod secSize) <> 0) then
        exit;

    sectorLBA := run.LBA + (skipBytes div secSize);
    chunkSectors := copyBytes div secSize;
    ctx^.ChunkBytes := copyBytes;

    lastBytePos := skipBytes + copyBytes - 1;
    lastClusterIdx := startClusterIdx + (lastBytePos div bytesPerCluster);
    lastClusterUsed := run.StartCluster + (lastBytePos div bytesPerCluster);
    updateSIOC(ctx^.Volume, ctx^.Cluster, lastClusterIdx, lastClusterUsed);
    ctx^.CursorValid := true;
    ctx^.CursorIndex := lastClusterIdx;
    ctx^.CursorCluster := lastClusterUsed;

    fat32_fileio_prepare_single_run := true;
end;

procedure fat32_fileio_direct_complete(error : TError; userdata : pointer);
var
    ctx : PFATFileIOAsyncCtx;
begin
    ctx := PFATFileIOAsyncCtx(userdata);
    if ctx = nil then exit;

    if error = eNone then begin
        ctx^.BytesDone := ctx^.BytesDone + ctx^.ChunkBytes;
        if (ctx^.Mode = famWrite) and (ctx^.OpenFile <> nil) then begin
            if (ctx^.BytesDone > 0) and ((ctx^.Offset + ctx^.BytesDone) > ctx^.OpenFile^.ByteSize) then begin
                ctx^.OpenFile^.ByteSize := ctx^.Offset + ctx^.BytesDone;
                ctx^.OpenFile^.MetaDirty := true;
            end;
            if (ctx^.OpenFile^.FirstCluster = 0) and (ctx^.Cluster <> 0) then begin
                ctx^.OpenFile^.FirstCluster := ctx^.Cluster;
                ctx^.OpenFile^.Exists := true;
                ctx^.OpenFile^.MetaDirty := true;
            end;
        end;
    end;

    fat32_fileio_async_complete(ctx, error);
end;

procedure fat32_fileio_async_step(error : TError; userdata : pointer); forward;

procedure fat32_fileio_async_run_next(ctx : PFATFileIOAsyncCtx);
const
    MAX_RUN_SECTORS = 2048;
var
    run             : TRunInfo;
    curCluster      : uint32;
    chainPos        : uint32;
    currentOffset   : uint32;
    bytesPerCluster : uint32;
    startClusterIdx : uint32;
    inClusterOffset : uint32;
    remaining       : uint32;
    skipBytes       : uint32;
    copyBytes       : uint32;
    secSize         : uint32;
    spc             : uint32;
    sectorLBA       : uint32;
    chunkSectors    : uint32;
    lastBytePos     : uint32;
    lastClusterUsed : uint32;
    lastClusterIdx  : uint32;
    maxRunClusters  : uint32;
    extentIdx       : uint32;
    extentStartIdx  : uint32;
    err             : TError;
begin
    if ctx = nil then exit;

    if ctx^.State = ftsAwaitIO then begin
        if ctx^.LastError <> eNone then begin
            ctx^.State := ftsError;
            fat32_fileio_async_complete(ctx, ctx^.LastError);
            exit;
        end;

        ctx^.State := ftsAdvance;
        ctx^.BytesDone := ctx^.BytesDone + ctx^.ChunkBytes;

        if (ctx^.Mode = famWrite) and (ctx^.OpenFile <> nil) then begin
            if (ctx^.BytesDone > 0) and ((ctx^.Offset + ctx^.BytesDone) > ctx^.OpenFile^.ByteSize) then begin
                ctx^.OpenFile^.ByteSize := ctx^.Offset + ctx^.BytesDone;
                ctx^.OpenFile^.MetaDirty := true;
            end;
            if (ctx^.OpenFile^.FirstCluster = 0) and (ctx^.Cluster <> 0) then begin
                ctx^.OpenFile^.FirstCluster := ctx^.Cluster;
                ctx^.OpenFile^.Exists := true;
                ctx^.OpenFile^.MetaDirty := true;
            end;
        end;
    end;

    if ctx^.BytesDone >= ctx^.ByteCount then begin
        ctx^.State := ftsComplete;
        fat32_fileio_async_complete(ctx, eNone);
        exit;
    end;

    ctx^.State := ftsPrepare;

    currentOffset := ctx^.Offset + ctx^.BytesDone;
    remaining := ctx^.ByteCount - ctx^.BytesDone;
    spc := uint32(ctx^.BootRecord^.spc);
    secSize := uint32(ctx^.BootRecord^.sectorSize);
    bytesPerCluster := spc * secSize;
    startClusterIdx := currentOffset div bytesPerCluster;
    inClusterOffset := currentOffset mod bytesPerCluster;

    maxRunClusters := MAX_RUN_SECTORS div spc;
    if maxRunClusters = 0 then
        maxRunClusters := 1;

    if (ctx^.OpenFile <> nil) and (ctx^.OpenFile^.Extents <> nil) and
       fatLocateExtentRun(ctx^.OpenFile^.Extents, startClusterIdx,
           ctx^.ExtentValid, ctx^.ExtentIdx, ctx^.ExtentStartIdx,
           run.StartCluster, run.RunLen, extentIdx, extentStartIdx) then begin
        if run.RunLen > maxRunClusters then
            run.RunLen := maxRunClusters;
        run.LastCluster := run.StartCluster + run.RunLen - 1;
        ctx^.ExtentValid := true;
        ctx^.ExtentIdx := extentIdx;
        ctx^.ExtentStartIdx := extentStartIdx;
        curCluster := run.LastCluster;
        chainPos := startClusterIdx + run.RunLen - 1;
    end else begin
        if not seekToClusterIndexHinted(
            ctx^.Volume, ctx^.Cluster, startClusterIdx, ctx^.BootRecord,
            ctx^.CursorValid, ctx^.CursorIndex, ctx^.CursorCluster,
            curCluster, chainPos) then begin
            ctx^.State := ftsError;
            fat32_fileio_async_complete(ctx, eCorruptFilesystem);
            exit;
        end;

        run.StartCluster := curCluster;
        buildContiguousRun(ctx^.Volume, curCluster, spc, MAX_RUN_SECTORS, ctx^.BootRecord, run.RunLen, run.LastCluster);
    end;
    run.RunSectors := run.RunLen * spc;
    run.RunBytes := run.RunSectors * secSize;
    run.LBA := clusterToLBA(ctx^.DataStart, spc, run.StartCluster);

    skipBytes := inClusterOffset;
    copyBytes := run.RunBytes - skipBytes;
    if copyBytes > remaining then
        copyBytes := remaining;

    if (copyBytes = 0) or ((copyBytes mod secSize) <> 0) or ((skipBytes mod secSize) <> 0) then begin
        ctx^.State := ftsError;
        fat32_fileio_async_complete(ctx, eInvalidArgument);
        exit;
    end;

    sectorLBA := run.LBA + (skipBytes div secSize);
    chunkSectors := copyBytes div secSize;
    ctx^.ChunkBytes := copyBytes;

    lastBytePos := skipBytes + copyBytes - 1;
    lastClusterIdx := startClusterIdx + (lastBytePos div bytesPerCluster);
    lastClusterUsed := run.StartCluster + (lastBytePos div bytesPerCluster);
    updateSIOC(ctx^.Volume, ctx^.Cluster, lastClusterIdx, lastClusterUsed);
    ctx^.CursorValid := true;
    ctx^.CursorIndex := lastClusterIdx;
    ctx^.CursorCluster := lastClusterUsed;

    ctx^.State := ftsIssueIO;

    if ctx^.Mode = famRead then
        err := driver.storage.mgr.storage_read_async(
            ctx^.Volume^.device, sectorLBA, chunkSectors,
            puint32(uint32(ctx^.Buffer) + ctx^.BytesDone), @fat32_fileio_async_step, ctx)
    else
        err := driver.storage.mgr.storage_write_async(
            ctx^.Volume^.device, sectorLBA, chunkSectors,
            puint32(uint32(ctx^.Buffer) + ctx^.BytesDone), @fat32_fileio_async_step, ctx);

    if err = eNone then
        ctx^.State := ftsAwaitIO
    else
        ctx^.State := ftsError;
    if err <> eNone then
        fat32_fileio_async_complete(ctx, err);
end;

procedure fat32_fileio_async_step(error : TError; userdata : pointer);
var
    ctx : PFATFileIOAsyncCtx;
begin
    ctx := PFATFileIOAsyncCtx(userdata);
    if ctx = nil then exit;
    ctx^.LastError := error;
    if not fatScheduleTransfer(ctx) then begin
        ctx^.State := ftsError;
        fat32_fileio_async_complete(ctx, eQueueFull);
    end;
end;

{ Update the SIOC chain-position cache. }
procedure updateSIOC(
    volume           : PStorage_Volume;
    fileStartCluster : uint32;
    chainIdx         : uint32;
    chainCluster     : uint32
);
begin
    sioc_vol        := volume;
    sioc_fileClust  := fileStartCluster;
    sioc_chainIdx   := chainIdx;
    sioc_chainClust := chainCluster;
    sioc_valid      := true;
end;

{ Seek to a specific cluster index in a file's FAT chain.
  Uses the SIOC cache to resume from a previously cached position
  when possible, otherwise walks from the file's start cluster.
  Returns true on success, false if the chain ended prematurely. }
function seekToClusterIndex(
    volume           : PStorage_Volume;
    fileStartCluster : uint32;
    targetIdx        : uint32;
    bootRecord       : PBootRecord;
    var curCluster   : uint32;
    var chainPos     : uint32
) : boolean;
var
    nextFat : uint32;
    maxCluster : uint32;
begin
    seekToClusterIndex := false;
    if bootRecord^.sectorSize > 0 then
        maxCluster := (bootRecord^.FATSize * bootRecord^.sectorSize) div 4
    else
        maxCluster := 0;

    { Resume from SIOC cache if it covers this file at a useful position }
    if sioc_valid and (sioc_vol = volume) and (sioc_fileClust = fileStartCluster)
       and (sioc_chainIdx <= targetIdx) then begin
        curCluster := sioc_chainClust;
        chainPos   := sioc_chainIdx;
    end else begin
        curCluster := fileStartCluster;
        chainPos   := 0;
    end;

    { Walk forward to targetIdx }
    while chainPos < targetIdx do begin
        if (maxCluster > 0) and (chainPos >= maxCluster) then
            exit;
        nextFat := readFat(volume, curCluster, bootRecord);
        if ((nextFat and $0FFFFFFF) >= $0FFFFFF8) or (nextFat = 0) then
            exit;
        curCluster := nextFat;
        chainPos   := chainPos + 1;
    end;

    seekToClusterIndex := true;
end;

function seekToClusterIndexHinted(
    volume           : PStorage_Volume;
    fileStartCluster : uint32;
    targetIdx        : uint32;
    bootRecord       : PBootRecord;
    hintValid        : boolean;
    hintIdx          : uint32;
    hintCluster      : uint32;
    var curCluster   : uint32;
    var chainPos     : uint32
) : boolean;
var
    nextFat    : uint32;
    maxCluster : uint32;
begin
    seekToClusterIndexHinted := false;
    if bootRecord^.sectorSize > 0 then
        maxCluster := (bootRecord^.FATSize * bootRecord^.sectorSize) div 4
    else
        maxCluster := 0;

    if hintValid and (hintIdx <= targetIdx) then begin
        curCluster := hintCluster;
        chainPos := hintIdx;
    end else begin
        if not seekToClusterIndex(volume, fileStartCluster, targetIdx, bootRecord, curCluster, chainPos) then
            exit;
        seekToClusterIndexHinted := true;
        exit;
    end;

    while chainPos < targetIdx do begin
        if (maxCluster > 0) and (chainPos >= maxCluster) then
            exit;
        nextFat := readFat(volume, curCluster, bootRecord);
        if ((nextFat and $0FFFFFFF) >= $0FFFFFF8) or (nextFat = 0) then
            exit;
        curCluster := nextFat;
        chainPos := chainPos + 1;
    end;

    seekToClusterIndexHinted := true;
end;

//TODO add optional attributes flag to refine what i return
function getDirEntries(volume : PStorage_volume; cluster : uint32; bootRecord : PBootRecord) : PLinkedListBase;
var
    buffer : puint32;
    bufferI : puint32;
    clusters : PLinkedListBase;
    directories : PLinkedListBase;
    i : uint32 = 0;
    maxEntries : uint32;
    datastart : uint32;
    sectorLocation : uint32;
    dirElm : puint32;
begin
    push_trace('driver.storage.fs.fat32.getDirEntries.enter');
    directories:= LL_New(sizeof(TDirectory));

    clusters:= PLinkedListBase(getFatChain(volume, cluster, bootRecord));
    if (clusters = nil) or (LL_size(clusters) = 0) then begin
        getDirEntries := directories;
        if clusters <> nil then LL_Free(clusters);
        push_trace('driver.storage.fs.fat32.getDirEntries.exit');
        exit;
    end;
    push_trace('driver.storage.fs.fat32.getDirEntries.allocBuffer');
    buffer:= puint32(kalloc( (bootRecord^.sectorSize * bootRecord^.spc) * LL_size(clusters) ));
    memset(uint32(buffer), 0, (bootRecord^.sectorSize * bootRecord^.spc) * LL_size(clusters) );

    dataStart:= fatDataStartLBA(volume, bootRecord);

    push_trace('driver.storage.fs.fat32.getDirEntries.readSectors');
    for i:=0 to LL_size(clusters) - 1 do begin
        sectorLocation:= bootRecord^.spc * puint32(LL_Get(clusters, i))^;
        bufferI:= puint32(uint32(buffer) + uint32(i * bootRecord^.spc * bootRecord^.sectorSize));
        driver.storage.mgr.storage_read(volume^.device, datastart + sectorLocation, bootRecord^.spc, bufferI);
    end;

    i:=0;
    maxEntries:= ((bootRecord^.sectorSize * bootRecord^.spc) * LL_size(clusters)) div sizeof(TDirectory);
    while i < maxEntries do begin
        if PDirectory(buffer)[i].fileName[0] = char(0) then break;

        { Skip deleted entries ($E5 = FAT32 deleted marker) }
        if PDirectory(buffer)[i].fileName[0] = char($E5) then begin
            i+=1;
            continue;
        end;

        dirElm:= LL_Add(directories);
        PDirectory(dirElm)^:= PDirectory(buffer)[i];
        i+=1;
    end;

    getDirEntries:= directories; //get last .
    LL_Free(clusters);
    kfree(buffer);
    push_trace('driver.storage.fs.fat32.getDirEntries.exit');
end;

function fat2GenericEntries(list : PLinkedListBase) : PLinkedListBase;
var
    i        : uint32;
    entry    : PDirectory_Entry;
    dir      : PDirectory;
    dirElm   : puint32;
    nameBuf  : pchar;
    nameLen  : uint32;
    extLen   : uint32;
begin
    push_trace('driver.storage.fs.fat32.fat2GenericEntries.enter');
    puint32(entry) := kalloc(sizeof(TDirectory_Entry));
    fat2GenericEntries:= LL_New(sizeof(TDirectory_Entry));

    if LL_size(list) > 0 then begin

        for i:= 0 to LL_Size(list) - 1 do begin
            dir := PDirectory(LL_get(list, i));

            { Skip deleted entries (should already be filtered by getDirEntries, but guard here too) }
            if dir^.fileName[0] = char($E5) then continue;

            { Trim trailing spaces from fileName (8 bytes) }
            nameLen := 8;
            while (nameLen > 0) and (dir^.fileName[nameLen - 1] = ' ') do
                nameLen := nameLen - 1;

            { Trim trailing spaces from extension (3 bytes) }
            extLen := 3;
            while (extLen > 0) and (dir^.fileExtension[extLen - 1] = ' ') do
                extLen := extLen - 1;

            { Build combined filename: NAME.EXT or just NAME }
            if extLen > 0 then begin
                nameBuf := pchar(kalloc(nameLen + 1 + extLen + 1));
                memcpy(uint32(@dir^.fileName[0]), uint32(nameBuf), nameLen);
                nameBuf[nameLen] := '.';
                memcpy(uint32(@dir^.fileExtension[0]), uint32(@nameBuf[nameLen + 1]), extLen);
                nameBuf[nameLen + 1 + extLen] := char(0);
            end else begin
                nameBuf := pchar(kalloc(nameLen + 1));
                memcpy(uint32(@dir^.fileName[0]), uint32(nameBuf), nameLen);
                nameBuf[nameLen] := char(0);
            end;

            entry^.fileName := nameBuf;

            if dir^.attributes = $10 then begin
                entry^.entryType:= TDirectory_Entry_Type.directoryEntry;
            end else begin
                entry^.entryType:= TDirectory_Entry_Type.fileEntry;
            end;

            entry^.fileSize     := dir^.byteSize;
            entry^.modifiedDate := dir^.modifiedDate;
            entry^.modifiedTime := dir^.modifiedTime;
            entry^.attributes   := dir^.attributes;

            //add to list
            dirElm:= LL_add(fat2GenericEntries);
            PDirectory_Entry(dirElm)^:= entry^;
        end;
    end;

    LL_Free(list);
    kfree(puint32(entry));
    push_trace('driver.storage.fs.fat32.fat2GenericEntries.exit');
end;

//need to find out why having multiple dir stings isn't working, maybe the ls command? did I fix this?
function readDirectory(volume : PStorage_volume; directory : pchar; statusOut : puint32) : PLinkedListBase; //statusout: 0 = success, 1 = dir not exsist, 2 = not directory, 3 = invalid name, 4= already exists
var
    bootRecord       : PBootRecord;
    directoryStrings : PLinkedListBase;
    directories      : PLinkedListBase;
    cluster          : uint32;
    i                : uint32;
    ii               : uint32 = 0;
    dirEntry         : PDirectory;
    status : puint32;
begin
    status:= puint32(kalloc(sizeof(uint32)));
    push_trace('driver.storage.fs.fat32.readDirectory.enter');
    status^:= ord(eNone);
    bootRecord:= readBootRecord(volume);
    directoryStrings:= LL_fromString(directory, '/');
    directories:= getDirEntries(volume, bootRecord^.rootCluster, bootRecord);

    if LL_size(directoryStrings) > 0 then begin
        for i:=0 to (LL_Size(directoryStrings) ) do begin /// maybe -1 will work
            ii:=0;

            while true do begin
                if ii > LL_Size(directories) - 1 then begin
                    status^:= ord(eDirectoryDoesNotExist);
                    break; 
                end;
                dirEntry:= PDirectory(LL_Get(directories, ii));

                if compareByteArray8( dirEntry^.fileName, cleanString( pchar(puint32(LL_Get(directoryStrings, i))^), status)) then begin
                    cluster:= dirFirstCluster(dirEntry);
                    break;
                end;
                ii+=1;
            end;

            if status^ <> 0 then break;
            
            LL_Free(directories); 
            directories:= getDirEntries(volume, cluster, bootRecord);

            if i = LL_Size(directoryStrings) - 1 then break;
        end;
    end else begin
        while true do begin
            if ii > LL_Size(directories) - 1 then break;
            dirEntry:= PDirectory(LL_Get(directories, ii));
            ii+=1;
        end;
    end;

    readDirectory:= directories;

    if statusOut <> nil then statusOut^ := status^;
    kfree(status);
    LL_Free(directoryStrings);
    kfree(puint32(bootRecord));
    push_trace('driver.storage.fs.fat32.readDirectory.exit');
end;

function readDirectoryGen(volume : PStorage_volume; directory : pchar; status : puint32) : PLinkedListBase; //returns: 0 = success, 1 = dir not exsist, 2 = not directory, 3 = invalid name, 4= already exists
begin
    push_trace('driver.storage.fs.fat32.readDirectoryGen.enter');
    readDirectoryGen:= fat2GenericEntries(readDirectory(volume, directory, status));
    push_trace('driver.storage.fs.fat32.readDirectoryGen.exit');
end;

//need to allow for setting file extension
function writeDirectory(volume : PStorage_volume; directory : pchar; dirName : pchar; attributes : uint32; statusOut : puint32) : uint32; // need to handle parent table cluster overflow, need to take attributes
var
    directories     : PLinkedListBase;
    parentDirectory : PDirectory;
    parentCluster   : uint32;
    extents         : PLinkedListBase;
    extent          : PClusterExtent;
    cluster         : uint32;
    bootRecord      : PBootRecord;
    buffer          : puint32;
    bufferPointer   : PDirectory;
    dataStart       : uint32;
    EntriesPerSector : uint32;
    sectorLocation  : uint32;
    dataOffset      : uint32;
    i : uint32;

    thisArray     : byteArray8 = ('.',' ',' ',' ',' ',' ',' ',' ');
    parentArray   : byteArray8 = ('.','.',' ',' ',' ',' ',' ',' ');
    status : puint32;

    namePart : pchar;
    extPart  : pchar;
begin
    push_trace('driver.storage.fs.fat32.writeDirectory.enter');
    io.syslog.logln('FAT32', 'writeDirectory: enter');
    writeDirectory := 0;
    status:= puint32(kalloc(sizeof(uint32)));
    status^:= ord(eNone);

    { Validate the directory name as a valid FAT32 8.3 name }
    if not isValidFAT32Name(dirName) then begin
        io.syslog.logln('FAT32', 'writeDirectory: invalid FAT32 name, aborting');
        statusOut^:= ord(eInvalidFileName);
        kfree(status);
        exit;
    end;

    push_trace('driver.storage.fs.fat32.writeDirectory.readDir');
    directories:= readDirectory(volume, directory, status);

    { If the parent directory does not exist, bail out }
    if status^ <> ord(eNone) then begin
        io.syslog.logln('FAT32', 'writeDirectory: parent directory not found');
        statusOut^:= status^;
        kfree(status);
        LL_Free(directories);
        exit;
    end;

    { Split dirName for duplicate checking }
    splitFileNameParts(dirName, namePart, extPart);

    if(LL_size(directories) > 1) then begin
        for i:=0 to LL_Size(directories) - 1 do begin
            if compareByteArray8(PDirectory(LL_get(directories, i))^.fileName, cleanString( namePart , status))
               and matchExtension(PDirectory(LL_get(directories, i))^.fileExtension, extPart) then begin
                status^:= ord(eDirectoryAlreadyExists);
                io.syslog.logln('FAT32', 'writeDirectory: entry already exists');
            end;
        end;
    end;

    kfree(void(namePart));
    kfree(void(extPart));

    bootRecord:= readBootRecord(volume);
    datastart:= fatDataStartLBA(volume, bootRecord);

    if status^ = ord(eNone) then begin
        push_trace('driver.storage.fs.fat32.writeDirectory.createEntry');

        { Check if directory sector is full }
        EntriesPerSector:= uint32(bootRecord^.sectorSize) div uint32(sizeof(TDirectory));
        if LL_size(directories) >= EntriesPerSector then begin
            { Current sector is full — would need cluster chain extension (not yet supported) }
            io.syslog.logln('FAT32', 'writeDirectory: directory sector full');
            statusOut^:= ord(eDirectoryFull);
            kfree(status);
            kfree(puint32(bootRecord));
            LL_Free(directories);
            exit;
        end;

        parentDirectory:= PDirectory(LL_Get(directories, 0));
        parentCluster:= dirFirstCluster(parentDirectory);

        extents := findFreeClusterExtents(volume, 1, bootRecord);
        if extents = nil then begin
            { No free clusters available — disk is full }
            io.syslog.logln('FAT32', 'writeDirectory: disk full');
            statusOut^:= ord(eDiskFull);
            kfree(status);
            kfree(puint32(bootRecord));
            LL_Free(directories);
            exit;
        end;
        extent := PClusterExtent(LL_Get(extents, 0));
        cluster := extent^.StartCluster;
        io.syslog.logln('FAT32', 'writeDirectory: allocated cluster');
        LL_Free(extents);
        buffer:= puint32(kalloc(bootRecord^.sectorSize));

        if attributes = $10 then begin // if directory

            memset(uint32(buffer), 0, bootRecord^.sectorSize);

            bufferPointer:= @PDirectory(buffer)[0];
            bufferPointer^.fileName:= thisArray; //TODO implement time
            bufferPointer^.attributes:= attributes;
            setDirFirstCluster(bufferPointer, cluster);
            
            bufferPointer:= @PDirectory(buffer)[1];
            bufferPointer^.fileName:= parentArray; //TODO implement time
            bufferPointer^.attributes:= attributes;
            setDirFirstCluster(bufferPointer, parentCluster);

            //write to disk
            driver.storage.mgr.storage_write(volume^.device, clusterToLBA(dataStart, bootRecord^.spc, cluster), 1, buffer);

            //write fat
            writeFat(volume, cluster, $FFFFFFF8, bootRecord);
        end;
        memset(uint32(buffer), 0, bootRecord^.sectorSize);
        //calculate write cluster using directories and parentCluster
        sectorLocation:= LL_size(directories) * sizeof(TDirectory) div bootRecord^.sectorSize;
        sectorLocation:= sectorLocation + (parentCluster * bootRecord^.spc);

        //dataOffset:= datastart + ( (LL_size(directories) * sizeof(PDirectory)) - (sizeUsed * bootRecord^.sectorSize));
        driver.storage.mgr.storage_read(volume^.device, dataStart + sectorLocation, 1, buffer);

        //construct my dir entry
        EntriesPerSector:= uint32(bootRecord^.sectorSize) div uint32(sizeof(TDirectory));
        bufferPointer:= @PDirectory(buffer)[LL_size(directories) - ((LL_size(directories) div EntriesPerSector) * EntriesPerSector)];

        { Split dirName into name + extension parts for FAT32 8.3 format }
        splitFileNameParts(dirName, namePart, extPart);
        bufferPointer^.fileName:= cleanString(namePart, status);
        bufferPointer^.attributes:= attributes;
        if attributes = 0 then begin
            { Copy extension characters for files }
            fillFatExt(bufferPointer^.fileExtension, extPart);
        end else begin
            fillFatExt(bufferPointer^.fileExtension, nil);
        end;
        kfree(void(namePart));
        kfree(void(extPart));
        setDirFirstCluster(bufferPointer, cluster);

        writeDirectory:= cluster;

        push_trace('driver.storage.fs.fat32.writeDirectory.writeToDisk');
        //write to disk
        driver.storage.mgr.storage_write(volume^.device, dataStart + sectorLocation, 1, buffer);
        io.syslog.logln('FAT32', 'writeDirectory: entry written to disk');
        kfree(buffer);
    end;

    statusOut^:= status^;
    kfree(status);
    kfree(puint32(bootRecord));
    LL_Free(directories);
    io.syslog.logln('FAT32', 'writeDirectory: exit');

end;

procedure writeDirectoryGen(volume : PStorage_volume; directory : pchar; dirName : pchar; attributes : uint32; statusOut : puint32); // need to handle parent table cluster overflow, need to take attributes
begin
    push_trace('driver.storage.fs.fat32.writeDirectoryGen.enter');
    writeDirectory(volume, directory, dirName, attributes, statusOut);
    push_trace('driver.storage.fs.fat32.writeDirectoryGen.exit');
end;

{ Split a full path like 'SYSTEM/FILE.TXT' into parent dir ('SYSTEM') and name ('FILE.TXT').
  If no separator, parentOut is empty string and nameOut is the whole path.
  Caller must free parentOut and nameOut. }
procedure splitPathParts(fullPath : pchar; var parentOut : pchar; var nameOut : pchar);
var
    pathLen, lastSlash, i : uint32;
begin
    parentOut := nil;
    nameOut := nil;
    if fullPath = nil then begin
        parentOut := stringNew(0);
        nameOut := stringNew(0);
        exit;
    end;
    pathLen := stringSize(fullPath);
    if pathLen = 0 then begin
        parentOut := stringNew(0);
        nameOut := stringNew(0);
        exit;
    end;

    { Find last '/' separator }
    lastSlash := pathLen; { sentinel: no slash found }
    for i := 0 to pathLen - 1 do begin
        if fullPath[i] = '/' then
            lastSlash := i;
    end;

    if lastSlash < pathLen then begin
        parentOut := stringTrim(fullPath, lastSlash);
        nameOut := stringCopy(pchar(@fullPath[lastSlash + 1]));
    end else begin
        parentOut := stringNew(0);
        nameOut := stringCopy(fullPath);
    end;
end;

{ Free a FAT chain starting from the given cluster — marks all clusters as free (0).
  Includes loop protection: aborts if iteration count exceeds maxCluster or cluster
  is out of range (< 2 or >= maxCluster). }
procedure freeFatChain(volume : PStorage_volume; startCluster : uint32; bootRecord : PBootRecord);
var
    currentCluster : uint32;
    nextCluster    : uint32;
    maxCluster     : uint32;
    iter           : uint32;
begin
    push_trace('driver.storage.fs.fat32.freeFatChain.enter');
    if (bootRecord^.FATSize > 0) and (bootRecord^.sectorsize > 0) then
        maxCluster := (bootRecord^.FATSize * bootRecord^.sectorsize) div 4
    else
        maxCluster := 0;
    currentCluster := startCluster;
    iter := 0;
    while true do begin
        if (currentCluster < 2) or (currentCluster >= maxCluster) then begin
            io.syslog.logln('FAT32', 'freeFatChain: cluster out of range, aborting');
            break;
        end;
        if iter >= maxCluster then begin
            io.syslog.logln('FAT32', 'freeFatChain: iteration limit hit, possible cycle');
            break;
        end;
        nextCluster := readFat(volume, currentCluster, bootRecord);
        writeFat(volume, currentCluster, 0, bootRecord);
        iter := iter + 1;

        if (nextCluster and $0FFFFFFF) >= $0FFFFFF8 then break; { end of chain }
        if (nextCluster and $0FFFFFFF) = $0FFFFFF7 then break;  { bad cluster }
        if nextCluster = 0 then break;                          { already free }

        currentCluster := nextCluster;
    end;
    push_trace('driver.storage.fs.fat32.freeFatChain.exit');
end;

{ Resolve a full path into parentCluster + leafName.
  Splits the path, reads the parent directory, and returns
  the parent cluster. On failure sets statusOut and returns false.
  Caller must kfree parentDir and leafName when done.
  bootRecord must already be read by the caller. }
function resolveParentCluster(
    volume       : PStorage_Volume;
    path         : pchar;
    bootRecord   : PBootRecord;
    var parentDir    : pchar;
    var leafName     : pchar;
    var parentClust  : uint32;
    var statusOut    : uint32
) : boolean;
var
    directories  : PLinkedListBase;
    parentEntry  : PDirectory;
    status       : puint32;
begin
    resolveParentCluster := false;
    splitPathParts(path, parentDir, leafName);

    if (leafName = nil) or (stringSize(leafName) = 0) then begin
        statusOut := ord(eInvalidFileName);
        exit;
    end;

    if (parentDir = nil) or (stringSize(parentDir) = 0) then begin
        parentClust := bootRecord^.rootCluster;
        resolveParentCluster := true;
        exit;
    end;

    status := puint32(kalloc(4));
    status^ := ord(eNone);
    directories := readDirectory(volume, parentDir, status);
    if status^ <> ord(eNone) then begin
        statusOut := status^;
        LL_Free(directories);
        kfree(status);
        exit;
    end;
    if LL_size(directories) < 1 then begin
        statusOut := ord(eDirectoryDoesNotExist);
        LL_Free(directories);
        kfree(status);
        exit;
    end;
    parentEntry := PDirectory(LL_Get(directories, 0));
    parentClust := dirFirstCluster(parentEntry);
    LL_Free(directories);
    kfree(status);
    resolveParentCluster := true;
end;

{ Delete a file from the volume. filePath is relative to volume root, e.g. 'SYSTEM/FILE.TXT' or 'FILE.TXT' }
procedure deleteFile(volume : PStorage_Volume; filePath : pchar; statusOut : puint32);
var
    parentDir        : pchar;
    fileName         : pchar;
    namePart         : pchar;
    extPart          : pchar;
    bootRecord       : PBootRecord;
    parentCluster    : uint32;
    status           : puint32;
    buffer           : puint32;
    dir              : PDirectory;
    cluster          : uint32;
    cleanFileName    : byteArray8;
    loc              : TDirEntryLocation;
    resolveStatus    : uint32;
begin
    push_trace('driver.storage.fs.fat32.deleteFile.enter');
    io.syslog.logln('FAT32', 'deleteFile: enter');
    status := puint32(kalloc(4));
    status^ := ord(eNone);

    bootRecord := readBootRecord(volume);

    { Resolve parent directory + leaf name from full path }
    resolveStatus := ord(eNone);
    if not resolveParentCluster(volume, filePath, bootRecord, parentDir, fileName, parentCluster, resolveStatus) then begin
        io.syslog.logln('FAT32', 'deleteFile: resolve failed');
        if statusOut <> nil then statusOut^ := resolveStatus;
        kfree(status);
        kfree(puint32(bootRecord));
        if parentDir <> nil then kfree(void(parentDir));
        if fileName <> nil then kfree(void(fileName));
        exit;
    end;

    { Split filename for 8.3 matching }
    splitFileNameParts(fileName, namePart, extPart);
    cleanFileName := cleanString(namePart, status);

    { Locate target entry in parent directory }
    buffer := puint32(kalloc(bootRecord^.sectorSize));
    if not locateDirEntry(volume, parentCluster, bootRecord, cleanFileName, extPart, loc, buffer) then begin
        io.syslog.logln('FAT32', 'deleteFile: file not found');
        if statusOut <> nil then statusOut^ := ord(eFileDoesNotExist);
        kfree(buffer);
        kfree(void(namePart));
        kfree(void(extPart));
        kfree(status);
        kfree(puint32(bootRecord));
        kfree(void(parentDir));
        kfree(void(fileName));
        exit;
    end;

    dir := @PDirectory(buffer)[loc.EntryIdx];

    { Don't allow deleting directories via deleteFile }
    if (dir^.attributes and $10) = $10 then begin
        io.syslog.logln('FAT32', 'deleteFile: target is a directory, not a file');
        if statusOut <> nil then statusOut^ := ord(eNotADirectory);
        kfree(buffer);
        kfree(void(namePart));
        kfree(void(extPart));
        kfree(status);
        kfree(puint32(bootRecord));
        kfree(void(parentDir));
        kfree(void(fileName));
        exit;
    end;

    cluster := dirFirstCluster(dir);

    { Free the FAT chain for this file }
    io.syslog.logln('FAT32', 'deleteFile: freeing FAT chain');
    if cluster >= 2 then
        freeFatChain(volume, cluster, bootRecord);

    { Mark entry deleted and write back }
    dir^.fileName[0] := char($E5);
    driver.storage.mgr.storage_write(volume^.device, loc.SectorLBA, 1, buffer);

    if statusOut <> nil then statusOut^ := ord(eNone);

    kfree(buffer);
    kfree(void(namePart));
    kfree(void(extPart));
    kfree(status);
    kfree(puint32(bootRecord));
    kfree(void(parentDir));
    kfree(void(fileName));
    push_trace('driver.storage.fs.fat32.deleteFile.exit');
    io.syslog.logln('FAT32', 'deleteFile: done');
end;

{ Delete a directory from the volume. path is relative to volume root. Directory must be empty. }
procedure deleteDir(volume : PStorage_Volume; path : pchar; statusOut : puint32);
var
    parentDir        : pchar;
    dirName          : pchar;
    namePart         : pchar;
    extPart          : pchar;
    bootRecord       : PBootRecord;
    childDirs        : PLinkedListBase;
    parentCluster    : uint32;
    status           : puint32;
    buffer           : puint32;
    dir              : PDirectory;
    cluster          : uint32;
    childCount       : uint32;
    cleanFileName    : byteArray8;
    loc              : TDirEntryLocation;
    resolveStatus    : uint32;
begin
    push_trace('driver.storage.fs.fat32.deleteDir.enter');
    io.syslog.logln('FAT32', 'deleteDir: enter');
    status := puint32(kalloc(4));
    status^ := ord(eNone);

    bootRecord := readBootRecord(volume);

    { Resolve parent directory + leaf name from full path }
    resolveStatus := ord(eNone);
    if not resolveParentCluster(volume, path, bootRecord, parentDir, dirName, parentCluster, resolveStatus) then begin
        io.syslog.logln('FAT32', 'deleteDir: resolve failed');
        if statusOut <> nil then statusOut^ := resolveStatus;
        kfree(status);
        kfree(puint32(bootRecord));
        if parentDir <> nil then kfree(void(parentDir));
        if dirName <> nil then kfree(void(dirName));
        exit;
    end;

    { Split dirName for 8.3 matching }
    splitFileNameParts(dirName, namePart, extPart);
    cleanFileName := cleanString(namePart, status);

    { Locate target entry in parent directory }
    buffer := puint32(kalloc(bootRecord^.sectorSize));
    if not locateDirEntry(volume, parentCluster, bootRecord, cleanFileName, extPart, loc, buffer) then begin
        io.syslog.logln('FAT32', 'deleteDir: directory not found');
        if statusOut <> nil then statusOut^ := ord(eDirectoryDoesNotExist);
        kfree(buffer);
        kfree(void(namePart));
        kfree(void(extPart));
        kfree(status);
        kfree(puint32(bootRecord));
        kfree(void(parentDir));
        kfree(void(dirName));
        exit;
    end;

    dir := @PDirectory(buffer)[loc.EntryIdx];

    { Must be a directory }
    if (dir^.attributes and $10) <> $10 then begin
        if statusOut <> nil then statusOut^ := ord(eNotADirectory);
        kfree(buffer);
        kfree(void(namePart));
        kfree(void(extPart));
        kfree(status);
        kfree(puint32(bootRecord));
        kfree(void(parentDir));
        kfree(void(dirName));
        exit;
    end;

    cluster := dirFirstCluster(dir);

    { Check if directory is empty — should contain only '.' and '..' }
    childDirs := getDirEntries(volume, cluster, bootRecord);
    childCount := LL_size(childDirs);
    LL_Free(childDirs);

    if childCount > 2 then begin
        io.syslog.logln('FAT32', 'deleteDir: directory not empty, refusing to delete');
        if statusOut <> nil then statusOut^ := ord(eDirectoryNotEmpty);
        kfree(buffer);
        kfree(void(namePart));
        kfree(void(extPart));
        kfree(status);
        kfree(puint32(bootRecord));
        kfree(void(parentDir));
        kfree(void(dirName));
        exit;
    end;

    { Free the FAT chain for this directory's data }
    if cluster >= 2 then
        freeFatChain(volume, cluster, bootRecord);

    { Mark entry deleted and write back }
    dir^.fileName[0] := char($E5);
    driver.storage.mgr.storage_write(volume^.device, loc.SectorLBA, 1, buffer);

    if statusOut <> nil then statusOut^ := ord(eNone);

    kfree(buffer);
    kfree(void(namePart));
    kfree(void(extPart));
    kfree(status);
    kfree(puint32(bootRecord));
    kfree(void(parentDir));
    kfree(void(dirName));
    push_trace('driver.storage.fs.fat32.deleteDir.exit');
    io.syslog.logln('FAT32', 'deleteDir: done');
end;

{ Rename a file or directory on disk. filePath is the current relative path,
  newName is the new leaf name (e.g. 'NEWFILE.TXT'). Only changes the 8.3
  directory entry in-place — does not move between directories. }
procedure renameFile(volume : PStorage_Volume; filePath : pchar; newName : pchar; statusOut : puint32);
var
    parentDir       : pchar;
    fileName        : pchar;
    namePart        : pchar;
    extPart         : pchar;
    newNamePart     : pchar;
    newExtPart      : pchar;
    bootRecord      : PBootRecord;
    parentCluster   : uint32;
    j               : uint32;
    status          : puint32;
    buffer          : puint32;
    dir             : PDirectory;
    cleanName       : byteArray8;
    newCleanName    : byteArray8;
    loc             : TDirEntryLocation;
    resolveStatus   : uint32;
begin
    push_trace('driver.storage.fs.fat32.renameFile.enter');
    io.syslog.logln('FAT32', 'renameFile: enter');
    status := puint32(kalloc(4));
    status^ := ord(eNone);

    bootRecord := readBootRecord(volume);

    { Validate new name before doing any work }
    if (newName = nil) or (stringSize(newName) = 0) then begin
        io.syslog.logln('FAT32', 'renameFile: invalid new name');
        if statusOut <> nil then statusOut^ := ord(eInvalidFileName);
        kfree(status);
        kfree(puint32(bootRecord));
        exit;
    end;

    { Resolve parent directory + leaf name from full path }
    resolveStatus := ord(eNone);
    if not resolveParentCluster(volume, filePath, bootRecord, parentDir, fileName, parentCluster, resolveStatus) then begin
        io.syslog.logln('FAT32', 'renameFile: resolve failed');
        if statusOut <> nil then statusOut^ := resolveStatus;
        kfree(status);
        kfree(puint32(bootRecord));
        if parentDir <> nil then kfree(void(parentDir));
        if fileName <> nil then kfree(void(fileName));
        exit;
    end;

    { Split current filename for 8.3 matching }
    splitFileNameParts(fileName, namePart, extPart);
    cleanName := cleanString(namePart, status);

    { Locate target entry in parent directory }
    buffer := puint32(kalloc(bootRecord^.sectorSize));
    if not locateDirEntry(volume, parentCluster, bootRecord, cleanName, extPart, loc, buffer) then begin
        io.syslog.logln('FAT32', 'renameFile: file not found');
        if statusOut <> nil then statusOut^ := ord(eFileDoesNotExist);
        kfree(buffer);
        kfree(void(namePart));
        kfree(void(extPart));
        kfree(status);
        kfree(puint32(bootRecord));
        kfree(void(parentDir));
        kfree(void(fileName));
        exit;
    end;

    dir := @PDirectory(buffer)[loc.EntryIdx];

    { Apply new 8.3 name in-place }
    splitFileNameParts(newName, newNamePart, newExtPart);
    newCleanName := cleanString(newNamePart, status);
    for j := 0 to 7 do
        dir^.fileName[j] := newCleanName[j];
    fillFatExt(dir^.fileExtension, newExtPart);
    kfree(void(newNamePart));
    kfree(void(newExtPart));

    { Write back this one sector }
    driver.storage.mgr.storage_write(volume^.device, loc.SectorLBA, 1, buffer);

    if statusOut <> nil then statusOut^ := ord(eNone);

    kfree(buffer);
    kfree(void(namePart));
    kfree(void(extPart));
    kfree(status);
    kfree(puint32(bootRecord));
    kfree(void(parentDir));
    kfree(void(fileName));
    push_trace('driver.storage.fs.fat32.renameFile.exit');
    io.syslog.logln('FAT32', 'renameFile: done');
end;

// function checkExists(volume : PStorage_Volume; directory : pchar; fileName : pchar; fileExtension : pchar; entry : PDirectory_Entry) : uint32;
// var
//     bootRecord : PBootRecord;
//     directories : PLinkedListBase;
//     dir : PDirectory;
//     genDir : PDirectory_Entry;
//     data : puint32;
//     statusOut : puint32;
//     i : uint32;
//     exists : boolean = false;
// begin
//     bootRecord := readBootRecord(volume);
//     directories := readDirectory(volume, directory, statusOut);
//     datastart:= volume^.sectorStart + 1 + bootRecord^.FATSize + bootRecord^.rsvSectors;

//     for i:=0 to LL_Size(directories) -1 do begin
//         dir:= PDirectory(LL_Get(directories, i));
//         if (dir^.fileName = entry^.fileName) and (dir^.fileExtension = entry^.extension) then begin
//             exists:= true;
//             break;
//         end;
//     end;

//     PDirectory_Entry := PDirectory_Entry(kalloc(20));

//     PDirectory_Entry^.fileName := pchar(@dir^.fileName);
//     PDirectory_Entry^.extension := pchar(@dir^.fileExtension);

// end;

//TODO check directory commands for errors with a clean disk

{ ========================================================================== }
{            Async format state machine (create_volume_async)                }
{ ========================================================================== }

procedure fmt_step_complete(error : TError; userdata : pointer); forward;

procedure fmt_run_next(ctx : PFmtContext);
var
    writeCount : uint32;
begin
    case ctx^.Step of
        fmtBootSector: begin
            io.syslog.logln('FAT32', 'fmt: fmtBootSector');
            { Write boot sector at start + 1 }
            driver.storage.mgr.storage_write_async(ctx^.Disk, ctx^.SectorStart + 1, 1,
                ctx^.Buffer, @fmt_step_complete, pointer(ctx));
        end;
        fmtZeroFAT: begin
            io.syslog.logln('FAT32', 'fmt: fmtZeroFAT batch');
            { Issue next FAT zero batch }
            if ctx^.BatchPos >= ctx^.FATSize then begin
                io.syslog.logln('FAT32', 'fmt: FAT zero complete, moving to fmtFATEntries');
                { FAT zeroing complete — move to FAT entries }
                kfree(ctx^.ZeroBuffer);
                ctx^.ZeroBuffer := nil;
                kfree(ctx^.Buffer);
                ctx^.Buffer := puint32(kalloc(ctx^.Disk^.sectorSize));
                memset(uint32(ctx^.Buffer), 0, ctx^.Disk^.sectorSize);
                puint32(ctx^.Buffer)[0] := $0FFFFFF8;  { media type (reserved entry 0) }
                puint32(ctx^.Buffer)[1] := $0FFFFFFF;  { clean marker (reserved entry 1) }
                puint32(ctx^.Buffer)[2] := $0FFFFFF8;  { root cluster EOC (entry 2) }
                puint32(ctx^.Buffer)[3] := $0FFFFFF8;  { SYSTEM dir cluster EOC (entry 3) }
                ctx^.Step := fmtFATEntries;
                fmt_run_next(ctx);
                exit;
            end;
            if (ctx^.FATSize - ctx^.BatchPos) >= ctx^.BatchSize then
                writeCount := ctx^.BatchSize
            else
                writeCount := ctx^.FATSize - ctx^.BatchPos;
            driver.storage.mgr.storage_write_async(ctx^.Disk,
                ctx^.FATStart + ctx^.BatchPos, writeCount, ctx^.ZeroBuffer,
                @fmt_step_complete, pointer(ctx));
        end;
        fmtFATEntries: begin
            io.syslog.logln('FAT32', 'fmt: fmtFATEntries');
            { Write FAT entries sector }
            driver.storage.mgr.storage_write_async(ctx^.Disk, ctx^.FATStart, 1,
                ctx^.Buffer, @fmt_step_complete, pointer(ctx));
        end;
        fmtRootDir: begin
            io.syslog.logln('FAT32', 'fmt: fmtRootDir');
            { Build root directory: "." + ".." + "SYSTEM" entries }
            memset(uint32(ctx^.Buffer), 0, ctx^.Disk^.sectorSize);
            { "." entry — volume label }
            PDirectory(ctx^.Buffer)[0].fileName[0] := '.';
            PDirectory(ctx^.Buffer)[0].fileName[1] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[2] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[3] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[4] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[5] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[6] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[7] := ' ';
            PDirectory(ctx^.Buffer)[0].attributes := $08;
            PDirectory(ctx^.Buffer)[0].clusterLow := ctx^.RootCluster;
            { ".." entry }
            PDirectory(ctx^.Buffer)[1].fileName[0] := '.';
            PDirectory(ctx^.Buffer)[1].fileName[1] := '.';
            PDirectory(ctx^.Buffer)[1].fileName[2] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[3] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[4] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[5] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[6] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[7] := ' ';
            PDirectory(ctx^.Buffer)[1].attributes := $10;
            PDirectory(ctx^.Buffer)[1].clusterLow := ctx^.RootCluster;
            { "SYSTEM" directory entry pointing to cluster 3 }
            PDirectory(ctx^.Buffer)[2].fileName[0] := 'S';
            PDirectory(ctx^.Buffer)[2].fileName[1] := 'Y';
            PDirectory(ctx^.Buffer)[2].fileName[2] := 'S';
            PDirectory(ctx^.Buffer)[2].fileName[3] := 'T';
            PDirectory(ctx^.Buffer)[2].fileName[4] := 'E';
            PDirectory(ctx^.Buffer)[2].fileName[5] := 'M';
            PDirectory(ctx^.Buffer)[2].fileName[6] := ' ';
            PDirectory(ctx^.Buffer)[2].fileName[7] := ' ';
            PDirectory(ctx^.Buffer)[2].attributes := $10;
            PDirectory(ctx^.Buffer)[2].clusterLow := 3;
            driver.storage.mgr.storage_write_async(ctx^.Disk,
                clusterToLBA(ctx^.DataStart, ctx^.SPC, ctx^.RootCluster), 1, ctx^.Buffer,
                @fmt_step_complete, pointer(ctx));
        end;
        fmtSystemDir: begin
            io.syslog.logln('FAT32', 'fmt: fmtSystemDir');
            { Build SYSTEM directory: "." and ".." }
            memset(uint32(ctx^.Buffer), 0, ctx^.Disk^.sectorSize);
            PDirectory(ctx^.Buffer)[0].fileName[0] := '.';
            PDirectory(ctx^.Buffer)[0].fileName[1] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[2] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[3] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[4] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[5] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[6] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[7] := ' ';
            PDirectory(ctx^.Buffer)[0].attributes := $10;
            PDirectory(ctx^.Buffer)[0].clusterLow := 3;
            PDirectory(ctx^.Buffer)[1].fileName[0] := '.';
            PDirectory(ctx^.Buffer)[1].fileName[1] := '.';
            PDirectory(ctx^.Buffer)[1].fileName[2] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[3] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[4] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[5] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[6] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[7] := ' ';
            PDirectory(ctx^.Buffer)[1].attributes := $10;
            PDirectory(ctx^.Buffer)[1].clusterLow := ctx^.RootCluster;
            driver.storage.mgr.storage_write_async(ctx^.Disk,
                clusterToLBA(ctx^.DataStart, ctx^.SPC, 3), 1, ctx^.Buffer,
                @fmt_step_complete, pointer(ctx));
        end;
        fmtDone: begin
            io.syslog.logln('FAT32', 'fmt: fmtDone — format complete');
            { All done — clean up and notify caller }
            kfree(ctx^.Buffer);
            ctx^.Buffer := nil;
            if ctx^.Callback <> nil then
                ctx^.Callback(eNone, ctx^.CallbackData);
            kfree(puint32(ctx));
        end;
    end;
end;

procedure fmt_step_complete(error : TError; userdata : pointer);
var
    ctx : PFmtContext;
begin
    ctx := PFmtContext(userdata);
    if error <> eNone then begin
        io.syslog.logln('FAT32', 'fmt_step_complete: I/O error — aborting format');
        { Error — abort format, clean up, notify caller }
        if ctx^.Buffer <> nil then kfree(ctx^.Buffer);
        if ctx^.ZeroBuffer <> nil then kfree(ctx^.ZeroBuffer);
        if ctx^.Callback <> nil then
            ctx^.Callback(error, ctx^.CallbackData);
        kfree(puint32(ctx));
        exit;
    end;

    { Advance to next step }
    case ctx^.Step of
        fmtBootSector: begin
            ctx^.Step := fmtZeroFAT;
            ctx^.BatchPos := 0;
        end;
        fmtZeroFAT: begin
            ctx^.BatchPos := ctx^.BatchPos + ctx^.BatchSize;
            { Step stays fmtZeroFAT — fmt_run_next checks if more batches remain }
        end;
        fmtFATEntries: begin
            ctx^.Step := fmtRootDir;
        end;
        fmtRootDir: begin
            ctx^.Step := fmtSystemDir;
        end;
        fmtSystemDir: begin
            ctx^.Step := fmtDone;
        end;
    end;
    fmt_run_next(ctx);
end;

procedure create_volume_async(volume : PStorage_Volume; sectors : uint32; start : uint32;
                              config : puint32; callback : TIOCallback; callbackData : pointer);
var
    ctx        : PFmtContext;
    bootRecord : PBootRecord;
    spc        : uint32;
begin
    push_trace('driver.storage.fs.fat32.create_volume_async');
    io.syslog.logln('FAT32', 'create_volume_async: enter');

    ctx := PFmtContext(kalloc(sizeof(TFmtContext)));
    if ctx = nil then begin
        io.syslog.logln('FAT32', 'create_volume_async: OOM allocating context');
        if callback <> nil then callback(eOutOfMemory, callbackData);
        exit;
    end;

    ctx^.Volume       := volume;
    ctx^.Disk         := volume^.device;
    ctx^.SectorStart  := start;
    ctx^.RootCluster  := 2;
    ctx^.Callback     := callback;
    ctx^.CallbackData := callbackData;
    ctx^.ZeroBuffer   := nil;

    if config <> nil then
        spc := config^
    else
        spc := fatDefaultSPC(sectors, ctx^.Disk^.sectorSize);
    if spc = 0 then
        spc := fatDefaultSPC(sectors, ctx^.Disk^.sectorSize);
    ctx^.SPC := spc;

    ctx^.FATSize  := fatComputeFATSize(sectors, spc, ctx^.Disk^.sectorSize);
    ctx^.FATStart := start + 1 + 32;   { boot sector + 32 reserved sectors }
    ctx^.DataStart := ctx^.FATStart + ctx^.FATSize;

    { Allocate boot sector buffer and build boot record }
    ctx^.Buffer := puint32(kalloc(ctx^.Disk^.sectorSize + 512));
    if ctx^.Buffer = nil then begin
        if callback <> nil then callback(eOutOfMemory, callbackData);
        kfree(puint32(ctx));
        exit;
    end;
    memset(uint32(ctx^.Buffer), 0, ctx^.Disk^.sectorSize);

    bootRecord := PBootRecord(ctx^.Buffer);
    bootRecord^.jmp2boot        := $0;
    bootRecord^.OEMName[0]      := 'A';
    bootRecord^.OEMName[1]      := 'S';
    bootRecord^.OEMName[2]      := 'U';
    bootRecord^.OEMName[3]      := 'R';
    bootRecord^.OEMName[4]      := 'O';
    bootRecord^.OEMName[5]      := ' ';
    bootRecord^.OEMName[6]      := 'V';
    bootRecord^.OEMName[7]      := '1';
    bootRecord^.sectorSize      := ctx^.Disk^.sectorSize;
    bootRecord^.spc             := uint8(spc);
    bootRecord^.rsvSectors      := 32;
    bootRecord^.numFats         := 1;
    bootRecord^.mediaDescp      := $F8;
    bootRecord^.hiddenSectors   := start;
    bootRecord^.manySectors     := sectors;
    bootRecord^.FATSize         := ctx^.FATSize;
    bootRecord^.rootCluster     := ctx^.RootCluster;
    bootRecord^.FSInfoCluster   := 0;
    bootRecord^.driveNumber     := $80;
    bootRecord^.volumeID        := 62;
    bootRecord^.bsignature      := $29;
    bootRecord^.identString[0]  := 'F';
    bootRecord^.identString[1]  := 'A';
    bootRecord^.identString[2]  := 'T';
    bootRecord^.identString[3]  := '3';
    bootRecord^.identString[4]  := '2';
    bootRecord^.identString[5]  := ' ';
    bootRecord^.identString[6]  := ' ';
    bootRecord^.identString[7]  := ' ';

    { Boot sector signature at bytes 508-511 }
    puint32(ctx^.Buffer)[127] := $55AA;

    { Allocate zero buffer for FAT batches }
    if ctx^.FATSize > 128 then
        ctx^.BatchSize := 128
    else
        ctx^.BatchSize := ctx^.FATSize;
    ctx^.BatchPos := 0;
    ctx^.ZeroBuffer := puint32(kalloc(ctx^.Disk^.sectorSize * ctx^.BatchSize));
    if ctx^.ZeroBuffer = nil then begin
        kfree(ctx^.Buffer);
        if callback <> nil then callback(eOutOfMemory, callbackData);
        kfree(puint32(ctx));
        exit;
    end;
    memset(uint32(ctx^.ZeroBuffer), 0, ctx^.Disk^.sectorSize * ctx^.BatchSize);

    { Kick off the first step: write boot sector }
    io.syslog.logln('FAT32', 'create_volume_async: kicking off fmtBootSector');
    ctx^.Step := fmtBootSector;
    fmt_run_next(ctx);
end;

{ ========================================================================== }
{              Synchronous create_volume (task context only)                  }
{ ========================================================================== }

procedure create_volume(volume : PStorage_Volume; sectors : uint32; start : uint32; config : puint32);
var
    buffer     : puint32;
    zeroBuffer : puint32;
    bootRecord : PBootRecord;
    dataStart  : uint32;
    fatStart   : uint32;
    FATSize    : uint32;
    batchSize  : uint32;
    batchPos   : uint32;

    asuroArray    : byteArray8 = ('A','S','U','R','O',' ','V','1');
    fatArray      : byteArray8 = ('F','A','T','3','2',' ',' ',' ');
    thisArray     : byteArray8 = ('.',' ',' ',' ',' ',' ',' ',' ');
    parentArray   : byteArray8 = ('.','.',' ',' ',' ',' ',' ',' ');

    asuroFileArray     : byteArray8 = ('A','S','U','R','O',' ',' ',' ');
    mountFileArray     : byteArray8 = ('M','O','U','N','T',' ',' ',' ');
    programFileArray   : byteArray8 = ('P','R','O','G','R','A','M','S');
    rootCluster   : uint32 = 2;

    sysArray : byteArray8 = ('S','Y','S','T','E','M',' ',' ');
    progArray : byteArray8 = ('P','R','O','G','R','A','M','S');
    userArray : byteArray8 = ('U','S','E','R',' ',' ',' ',' ');

    status : puint32;
    disk : PStorage_device;
    spc : uint32;

begin
    push_trace('driver.storage.fs.fat32.create_volume()');
    io.syslog.logln('FAT32', 'create_volume (sync): enter');

    disk := volume^.device;

    { Default sectors-per-cluster to 1 if config is nil }
    if config <> nil then
        spc := config^
    else
        spc := fatDefaultSPC(sectors, disk^.sectorSize);
    if spc = 0 then
        spc := fatDefaultSPC(sectors, disk^.sectorSize);

    //driver.storage.fs.fat32 structure
    (* BootRecord            *)
    (* reserved sectors      *)
    (* File Allocation Table *)
    (* Data Area             *)

    buffer:= puint32(kalloc(disk^.sectorSize+512));
    memset(uint32(buffer), 0, disk^.sectorSize);

    bootRecord:= PBootRecord(buffer);

    FATSize:= fatComputeFATSize(sectors, spc, disk^.sectorsize);

    bootRecord^.jmp2boot        := $0; //TODO impliment boot jump
    bootRecord^.OEMName         := asuroArray;
    bootRecord^.sectorSize      := disk^.sectorsize;
    bootRecord^.spc             := uint8(spc);
    bootRecord^.rsvSectors      := 32; //32 is standard
    bootRecord^.numFats         := 1;
    bootRecord^.mediaDescp      := $F8;
    bootRecord^.hiddenSectors   := start;
    bootRecord^.manySectors     := sectors;
    bootRecord^.FATSize         := FATSize;
    bootRecord^.rootCluster     := rootCluster;
    bootRecord^.FSInfoCluster   := 0;
    bootRecord^.driveNumber     := $80;
    bootRecord^.volumeID        := 62; //+ puint32(@driver.timer.rtc.getDateTime())^;
    bootRecord^.bsignature      := $29;
    bootRecord^.identString     := fatArray;


    { Write the boot sector signature marker at bytes 508-511 }
    puint32(buffer)[127] := $55AA;

    driver.storage.mgr.storage_write(disk, start + 1, 1, puint32(buffer));
    io.syslog.logln('FAT32', 'create_volume (sync): boot sector written');

    fatStart:= start + 1 + bootRecord^.rsvSectors;
    dataStart:= fatStart + bootRecord^.FATSize;

    { Batch zero the FAT: write 128 sectors at a time instead of 1 }
    if FATSize > 128 then
        batchSize := 128
    else
        batchSize := FATSize;
    zeroBuffer:= puint32(kalloc( disk^.sectorSize * batchSize ));
    memset(uint32(zeroBuffer), 0, disk^.sectorSize * batchSize);

    batchPos := 0;
    while batchPos < FATSize do begin
        if (FATSize - batchPos) >= batchSize then
            driver.storage.mgr.storage_write(disk, fatStart + batchPos, batchSize, zeroBuffer)
        else
            driver.storage.mgr.storage_write(disk, fatStart + batchPos, FATSize - batchPos, zeroBuffer);
        batchPos += batchSize;
    end;

    kfree(buffer);
    kfree(zeroBuffer);
    io.syslog.logln('FAT32', 'create_volume (sync): FAT zeroed');

    buffer:= puint32(kalloc(disk^.sectorSize));
    memset(uint32(buffer), 0, disk^.sectorSize);

    puint32(buffer)[0]:= $0FFFFFF8; //media type marker (reserved entry 0)
    puint32(buffer)[1]:= $0FFFFFFF; //clean/dirty marker (reserved entry 1)
    puint32(buffer)[2]:= $0FFFFFF8; //root cluster end-of-chain (entry 2)

    driver.storage.mgr.storage_write(disk, fatStart, 1, buffer);
    io.syslog.logln('FAT32', 'create_volume (sync): FAT entries written');

    kfree(buffer);

    buffer:= puint32(kalloc(disk^.sectorsize));
    memset(uint32(buffer), 0, disk^.sectorsize);

    PDirectory(buffer)[0].fileName   := thisArray;
    PDirectory(buffer)[0].attributes := $08;
    PDirectory(buffer)[0].clusterLow := rootCluster;

    PDirectory(buffer)[1].fileName   := parentArray;
    PDirectory(buffer)[1].attributes := $10;
    PDirectory(buffer)[1].clusterLow := rootCluster;
    
    driver.storage.mgr.storage_write(disk, clusterToLBA(dataStart, spc, rootCluster), 1, buffer);
    io.syslog.logln('FAT32', 'create_volume (sync): root dir written');

    memset(uint32(buffer), 0, disk^.sectorsize);

    status := puint32(kalloc(sizeof(uint32)));
    writeDirectory(volume, '', 'SYSTEM', $10, status);
    io.syslog.logln('FAT32', 'create_volume (sync): SYSTEM dir created');
    kfree(status);

    kfree(buffer);
    io.syslog.logln('FAT32', 'create_volume (sync): done');



end;

{ Count free clusters by scanning the FAT sector by sector.
  Returns the number of free clusters (FAT entries == 0). }
function countFreeFATClusters(volume : PStorage_Volume; bootRecord : PBootRecord) : uint32;
var
    fatStart       : uint32;
    maxCluster     : uint32;
    entriesPerSect : uint32;
    sectorIdx      : uint32;
    entryIdx       : uint32;
    clusterNum     : uint32;
    freeCount      : uint32;
    fatSectors     : uint32;
    fatBuffer      : puint32;
begin
    countFreeFATClusters := 0;
    if (bootRecord^.sectorsize = 0) or (bootRecord^.FATSize = 0) then exit;

    fatStart := volume^.sectorStart + 1 + bootRecord^.rsvSectors;
    maxCluster := (bootRecord^.FATSize * bootRecord^.sectorsize) div 4;
    entriesPerSect := bootRecord^.sectorsize div 4;
    fatSectors := bootRecord^.FATSize;

    fatBuffer := puint32(kalloc(bootRecord^.sectorsize));
    freeCount := 0;

    for sectorIdx := 0 to fatSectors - 1 do begin
        if sectorIdx * entriesPerSect >= maxCluster then break;
        driver.storage.mgr.storage_read(volume^.device, fatStart + sectorIdx, 1, fatBuffer);
        for entryIdx := 0 to entriesPerSect - 1 do begin
            clusterNum := sectorIdx * entriesPerSect + entryIdx;
            if clusterNum < 2 then continue;
            if clusterNum >= maxCluster then break;
            if fatBuffer[entryIdx] = 0 then
                freeCount := freeCount + 1;
        end;
    end;

    kfree(fatBuffer);
    countFreeFATClusters := freeCount;
end;

function identify_volume(volume : PStorage_Volume) : boolean;
var
    buffer     : puint32;
    bootRecord : PBootRecord;
    bufSize    : uint32;
begin
    push_trace('driver.storage.fs.fat32.identify_volume');
    io.syslog.logln('FAT32', 'identify_volume: enter');
    identify_volume := false;
    if volume^.device = nil then exit;
    if volume^.device^.dispatchRead = nil then exit;

    bufSize := volume^.device^.sectorSize;
    if bufSize < 512 then bufSize := 512;
    buffer := puint32(kalloc(bufSize));
    memset(uint32(buffer), 0, bufSize);

    driver.storage.mgr.storage_read(volume^.device, volume^.sectorStart + 1, 1, buffer);
    bootRecord := PBootRecord(buffer);

    if (bootRecord^.bsignature = $29) then begin
        io.syslog.logln('FAT32', 'identify_volume: FAT32 signature matched');
        identify_volume := true;
        volume^.freeSectors := countFreeFATClusters(volume, bootRecord) * bootRecord^.spc;
    end else begin
        io.syslog.logln('FAT32', 'identify_volume: not a FAT32 volume');
    end;

    kfree(buffer);
end;

procedure detect_volumes(disk : PStorage_Device);
var
    buffer : puint32;
    bufSize : uint32;
    i : uint8;
    volume : PStorage_volume;
begin
    push_trace('driver.storage.fs.fat32.detectVolumes()');

    bufSize := disk^.sectorSize;
    if bufSize < 512 then bufSize := 512;
    buffer := puint32(kalloc(bufSize));
    memset(uint32(buffer), 0, bufSize);

    { Read from sector 2 to check for FAT32 boot record }
    if disk^.dispatchRead = nil then begin
        io.syslog.writestringln('FAT32: detect_volumes: device has no read dispatch.');
        kfree(buffer);
        exit;
    end;

    driver.storage.mgr.storage_read(disk, 2, 1, buffer);

    if (puint32(buffer)[127] = $55AA) and (PBootRecord(buffer)^.bsignature = $29) then begin
        io.syslog.writestringln('FAT32: volume found!');
        volume := PStorage_volume(kalloc(sizeof(TStorage_Volume)));
        memset(uint32(volume), 0, sizeof(TStorage_Volume));
        volume^.device       := disk;
        volume^.sectorStart  := 1;
        volume^.sectorSize   := PBootRecord(buffer)^.sectorSize;
        volume^.sectorCount  := disk^.maxSectorCount;
        volume^.filesystem   := @filesystem;
        volume^.freeSectors  := countFreeFATClusters(volume, PBootRecord(buffer)) * PBootRecord(buffer)^.spc;
        volume^.isBootDrive  := false;

        driver.storage.vol.mgr.register_volume(disk, volume);
    end;

    kfree(buffer);
end;

{ ---- Per-file open / close for VFS metadata caching ---- }

{ Called by VFS on OpenFile.  Reads the boot record (cached per-volume),
  scans the directory for the file, and returns a TFATOpenFile context
  that writeFileAtOffset / readFileAtOffset can reuse on every call.
  Also populates fileSize so the VFS can skip calling fileSizeCallback. }
function fat32OpenFile(volume : PStorage_Volume; directory : pchar;
                       fileName : pchar; var fileSize : uint32) : pointer;
var
    ofi           : PFATOpenFile;
    bootRecord    : PBootRecord;
    dirs          : PLinkedListBase;
    status        : puint32;
    tempdir       : PDirectory;
    i             : uint32;
    cleanFileName : byteArray8;
    otherCFN      : byteArray8;
    namePart      : pchar;
    extPart       : pchar;
begin
    push_trace('driver.storage.fs.fat32.openFile.enter');
    fileSize := 0;

    bootRecord := getCachedBootRecord(volume);

    ofi := PFATOpenFile(kalloc(SizeOf(TFATOpenFile)));
    memset(uint32(ofi), 0, SizeOf(TFATOpenFile));
    ofi^.Volume := volume;
    ofi^.BootRecord := bootRecord;
    ofi^.DataStart := fatDataStartLBA(volume, bootRecord);
    ofi^.ScratchSize := bootRecord^.sectorSize;
    ofi^.ScratchSector := puint32(kalloc(ofi^.ScratchSize));
    if ofi^.ScratchSector <> nil then
        memset(uint32(ofi^.ScratchSector), 0, ofi^.ScratchSize);
    ofi^.Exists := false;

    { Read directory entries }
    status := puint32(kalloc(sizeof(uint32)));
    status^ := 0;
    dirs := readDirectory(volume, directory, status);

    { Determine parent cluster (Lesson 18: root has no '.' entry) }
    if (directory = nil) or (stringSize(directory) = 0) then
        ofi^.DirCluster := bootRecord^.rootCluster
    else begin
        if (dirs <> nil) and (LL_size(dirs) > 0) then begin
            tempdir := PDirectory(LL_get(dirs, 0));
            if tempdir^.fileName[0] = '.' then
                ofi^.DirCluster := dirFirstCluster(tempdir)
            else
                ofi^.DirCluster := bootRecord^.rootCluster;
        end else
            ofi^.DirCluster := bootRecord^.rootCluster;
    end;

    { Parse file name and compute cleaned 8.3 name }
    splitFileNameParts(fileName, namePart, extPart);
    cleanFileName := cleanString(namePart, status);
    ofi^.CleanName := cleanFileName;
    ofi^.ExtPart := stringCopy(extPart);

    { Search for file in directory entries }
        if (dirs <> nil) and (LL_size(dirs) > 0) then begin
            for i := 0 to LL_Size(dirs) - 1 do begin
                tempdir := PDirectory(LL_get(dirs, i));
                otherCFN := cleanString(tempdir^.filename, status);
                if compareByteArray8(cleanFileName, otherCFN) and matchExtension(tempdir^.fileExtension, extPart) then begin
                    ofi^.FirstCluster := dirFirstCluster(tempdir);
                    ofi^.ByteSize := tempdir^.byteSize;
                    ofi^.Exists := true;
                end;
            end;
        end;

    ofi^.AllocClusters := fatClustersForBytes(ofi^.ByteSize,
        uint32(bootRecord^.spc) * uint32(bootRecord^.sectorSize));
    if ofi^.Exists and (ofi^.FirstCluster >= 2) and (ofi^.ByteSize > 0) then
        ofi^.Extents := fatBuildExtentList(volume, ofi^.FirstCluster, bootRecord);

    kfree(void(namePart));
    kfree(void(extPart));
    if dirs <> nil then LL_Free(dirs);
    kfree(puint32(status));

    fileSize := ofi^.ByteSize;
    fat32OpenFile := pointer(ofi);
    push_trace('driver.storage.fs.fat32.openFile.exit');
end;

{ Called by VFS on CloseFile to free the per-file context. }
procedure fat32CloseFile(ctx : pointer);
var
    ofi      : PFATOpenFile;
    fatCache : PFATCache;
    dirBuf   : puint32;
    rawDir   : PDirectory;
    loc      : TDirEntryLocation;
begin
    if ctx = nil then exit;
    ofi := PFATOpenFile(ctx);
    if ofi^.FatDirty and (ofi^.Volume <> nil) then begin
        fatCache := fatCacheGet(ofi^.Volume);
        if fatCache <> nil then
            fatCacheFlush(fatCache, ofi^.Volume);
    end;
    if ofi^.MetaDirty and (ofi^.Volume <> nil) and (ofi^.BootRecord <> nil) then begin
        dirBuf := puint32(kalloc(ofi^.BootRecord^.sectorSize));
        if (dirBuf <> nil) and locateDirEntry(ofi^.Volume, ofi^.DirCluster, ofi^.BootRecord,
                ofi^.CleanName, ofi^.ExtPart, loc, dirBuf) then begin
            rawDir := @PDirectory(dirBuf)[loc.EntryIdx];
            rawDir^.byteSize := ofi^.ByteSize;
            if ofi^.FirstCluster <> 0 then
                setDirFirstCluster(rawDir, ofi^.FirstCluster);
            driver.storage.mgr.storage_write(ofi^.Volume^.device, loc.SectorLBA, 1, dirBuf);
        end;
        if dirBuf <> nil then
            kfree(dirBuf);
    end;
    if ofi^.ExtPart <> nil then
        kfree(void(ofi^.ExtPart));
    if ofi^.Extents <> nil then
        LL_Free(ofi^.Extents);
    if ofi^.ScratchSector <> nil then
        kfree(ofi^.ScratchSector);
    kfree(puint32(ofi));
end;

{ Write byteCount bytes to a file beginning at byte offset.
  If offset + byteCount exceeds the current file size, the file is extended
  by allocating new clusters.  Returns the number of bytes actually written. }
function writeFileAtOffset(volume : PStorage_Volume; directory : pchar;
                           fileName : pchar; offset : uint32;
                           buffer : puint32; byteCount : uint32;
                           ctx : pointer) : uint32;
const
    MAX_RUN_SECTORS = 2048;  { cap per multi-sector write = 1MB }
var
    lookup           : TFileLookup;
    run              : TRunInfo;
    ofi              : PFATOpenFile;
    i                : uint32;
    cluster          : uint32;
    dataStart        : uint32;
    cleanFileName    : byteArray8;
    otherCFN         : byteArray8;
    tempdir          : PDirectory;
    namePart         : pchar;
    extPart          : pchar;
    ioBuf            : puint32;
    bytesPerCluster  : uint32;
    startClusterIdx  : uint32;
    inClusterOffset  : uint32;
    chainPos         : uint32;
    curCluster       : uint32;
    srcPos           : uint32;
    remaining        : uint32;
    fileSize         : uint32;
    origByteSize     : uint32;
    newEnd           : uint32;
    oldClusters      : uint32;
    needClusters     : uint32;
    targetClusters   : uint32;
    extraClusters    : uint32;
    newExtents       : PLinkedListBase;
    lastCluster      : uint32;
    nextFat          : uint32;
    extent           : PClusterExtent;
    { dir entry update — raw sector scan (Lesson 18) }
    dirCluster       : uint32;
    dirBuf           : puint32;
    rawDir           : PDirectory;
    loc              : TDirEntryLocation;
    { Multi-sector write variables }
    spc              : uint32;
    secSize          : uint32;
    skipBytes        : uint32;
    copyBytes        : uint32;
    firstSectorOff   : uint32;
    partialBytes     : uint32;
    fullSectors      : uint32;
    batchBytes       : uint32;
    sectorLBA        : uint32;
    fatCache         : PFATCache;
    chainWalkLimit   : uint32;
    firstNewCluster  : uint32;
    reserveClusters  : uint32;
begin
    push_trace('driver.storage.fs.fat32.writeFileAtOffset.enter');
    writeFileAtOffset := 0;
    ofi := PFATOpenFile(ctx);

    if ofi <> nil then begin
        { Fast path: use cached open-file metadata }
        lookup.BootRecord := ofi^.BootRecord;
        lookup.Dirs := nil;
        lookup.Dir := nil;
        lookup.Status := nil;
        lookup.Exists := ofi^.Exists;
        dataStart := ofi^.DataStart;
        dirCluster := ofi^.DirCluster;
        cleanFileName := ofi^.CleanName;
        extPart := ofi^.ExtPart;
        namePart := nil;
        if lookup.Exists then begin
            origByteSize := ofi^.ByteSize;
            cluster := ofi^.FirstCluster;
        end else begin
            origByteSize := 0;
            cluster := 0;
        end;
    end else begin
        { Slow path: rediscover everything from disk }
        lookup.Status := puint32(kalloc(sizeof(uint32)));
        lookup.Status^ := 0;
        lookup.BootRecord := readBootRecord(volume);
        lookup.Dirs := readDirectory(volume, directory, lookup.Status);
        lookup.Exists := false;
        dataStart := fatDataStartLBA(volume, lookup.BootRecord);

        splitFileNameParts(fileName, namePart, extPart);
        cleanFileName := cleanString(namePart, lookup.Status);

        if LL_size(lookup.Dirs) > 0 then begin
            for i := 0 to LL_Size(lookup.Dirs) - 1 do begin
                tempdir := PDirectory(LL_get(lookup.Dirs, i));
                otherCFN := cleanString(tempdir^.filename, lookup.Status);
                if compareByteArray8(cleanFileName, otherCFN) and matchExtension(tempdir^.fileExtension, extPart) then begin
                    lookup.Dir := tempdir;
                    lookup.Exists := true;
                end;
            end;
        end;

        { Determine parent cluster (Lesson 18: root has no '.' entry) }
        if (directory = nil) or (stringSize(directory) = 0) then
            dirCluster := lookup.BootRecord^.rootCluster
        else begin
            if LL_size(lookup.Dirs) > 0 then begin
                tempdir := PDirectory(LL_get(lookup.Dirs, 0));
                if tempdir^.fileName[0] = '.' then
                    dirCluster := dirFirstCluster(tempdir)
                else
                    dirCluster := lookup.BootRecord^.rootCluster;
            end else
                dirCluster := lookup.BootRecord^.rootCluster;
        end;

        if lookup.Exists then begin
            origByteSize := lookup.Dir^.byteSize;
            cluster := dirFirstCluster(lookup.Dir);
        end else begin
            origByteSize := 0;
            cluster := 0;
        end;
    end;
    fileSize := origByteSize;
    if lookup.BootRecord^.sectorSize > 0 then
        chainWalkLimit := (lookup.BootRecord^.FATSize * lookup.BootRecord^.sectorSize) div 4
    else
        chainWalkLimit := 0;

    if not lookup.Exists then begin
        { --- Create a new zero-length file entry on disk --- }
        { dirCluster, cleanFileName, extPart already set above }

        dirBuf := puint32(kalloc(lookup.BootRecord^.sectorSize));

        if not locateFreeDirEntry(volume, dirCluster, lookup.BootRecord, loc, dirBuf) then begin
            kfree(dirBuf);
            io.syslog.logln('FAT32', 'writeFileAtOffset: exit-A no free dir slot');
            if ofi = nil then begin
                if namePart <> nil then kfree(void(namePart));
                if extPart <> nil then kfree(void(extPart));
                LL_Free(lookup.Dirs);
                kfree(puint32(lookup.BootRecord));
                kfree(puint32(lookup.Status));
            end;
            exit;
        end;

        rawDir := @PDirectory(dirBuf)[loc.EntryIdx];
        memset(uint32(rawDir), 0, sizeof(TDirectory));
        rawDir^.fileName := cleanFileName;
        rawDir^.attributes := 0; { regular file }
        fillFatExt(rawDir^.fileExtension, extPart);
        rawDir^.clusterLow := 0;
        rawDir^.clusterHigh := 0;
        rawDir^.byteSize := 0;
        driver.storage.mgr.storage_write(volume^.device, loc.SectorLBA, 1, dirBuf);

        kfree(dirBuf);

        { Invalidate chain cache — new file }
        sioc_valid := false;
    end;
    newEnd   := offset + byteCount;
    bytesPerCluster := uint32(lookup.BootRecord^.spc) * uint32(lookup.BootRecord^.sectorSize);

    { ---- Extend file if writing past EOF ---- }
    if newEnd > fileSize then begin
        if ofi <> nil then
            oldClusters := ofi^.AllocClusters
        else
            oldClusters := fatClustersForBytes(fileSize, bytesPerCluster);
        needClusters := fatClustersForBytes(newEnd, bytesPerCluster);
        targetClusters := needClusters;
        if (ofi <> nil) and (needClusters > oldClusters) then begin
            reserveClusters := fatPreallocClusterCount(bytesPerCluster);
            targetClusters := oldClusters + reserveClusters;
            if targetClusters < needClusters then
                targetClusters := needClusters;
        end;

        if targetClusters > oldClusters then begin
            extraClusters := targetClusters - oldClusters;
            if oldClusters > 0 then begin
                { Walk to last cluster using cache if available }
                if sioc_valid and (sioc_vol = volume) and (sioc_fileClust = cluster) then
                    lastCluster := sioc_chainClust
                else
                    lastCluster := cluster;
                nextFat := readFat(volume, lastCluster, lookup.BootRecord);
                while ((nextFat and $0FFFFFFF) < $0FFFFFF8) and (nextFat <> 0) do begin
                    if chainWalkLimit = 0 then
                        break;
                    chainWalkLimit := chainWalkLimit - 1;
                    if chainWalkLimit = 0 then begin
                        io.syslog.logln('FAT32', 'writeFileAtOffset: FAT loop detected while finding tail');
                        if ofi = nil then begin
                            if namePart <> nil then kfree(void(namePart));
                            if extPart <> nil then kfree(void(extPart));
                            LL_Free(lookup.Dirs);
                            kfree(puint32(lookup.BootRecord));
                            kfree(puint32(lookup.Status));
                        end;
                        exit;
                    end;
                    lastCluster := nextFat;
                    nextFat := readFat(volume, lastCluster, lookup.BootRecord);
                end;
            end else begin
                { Zero-length file: first new cluster becomes start cluster }
                lastCluster := 0;
            end;

            if fatFindContiguousFreeRange(volume, extraClusters, lookup.BootRecord, firstNewCluster) then begin
                fatLinkContiguousRange(volume, lookup.BootRecord, lastCluster, firstNewCluster, extraClusters, lastCluster);
                if oldClusters = 0 then
                    cluster := firstNewCluster;
                if ofi <> nil then begin
                    if ofi^.Extents = nil then
                        ofi^.Extents := LL_New(sizeof(TClusterExtent));
                    if ofi^.Extents <> nil then
                        fatAppendExtent(ofi^.Extents, firstNewCluster, extraClusters);
                end;
            end else begin
                newExtents := findFreeClusterExtents(volume, extraClusters, lookup.BootRecord);
                if newExtents = nil then begin
                    io.syslog.logln('FAT32', 'writeFileAtOffset: exit-B disk full');
                    { Undo just-created dir entry if file was new }
                    if not lookup.Exists then begin
                        dirBuf := puint32(kalloc(lookup.BootRecord^.sectorSize));
                        driver.storage.mgr.storage_read(volume^.device, loc.SectorLBA, 1, dirBuf);
                        PDirectory(dirBuf)[loc.EntryIdx].fileName[0] := char($E5);
                        driver.storage.mgr.storage_write(volume^.device, loc.SectorLBA, 1, dirBuf);
                        kfree(dirBuf);
                    end;
                    if ofi = nil then begin
                        if namePart <> nil then kfree(void(namePart));
                        if extPart <> nil then kfree(void(extPart));
                        LL_Free(lookup.Dirs);
                        kfree(puint32(lookup.BootRecord));
                        kfree(puint32(lookup.Status));
                    end;
                    exit;
                end;

                { Link new extents }
                if LL_Size(newExtents) > 0 then begin
                    for i := 0 to LL_Size(newExtents) - 1 do begin
                        extent := PClusterExtent(LL_Get(newExtents, i));
                        fatLinkContiguousRange(volume, lookup.BootRecord, lastCluster,
                            extent^.StartCluster, extent^.ClusterCount, lastCluster);
                        if (ofi <> nil) and (extent <> nil) then begin
                            if ofi^.Extents = nil then
                                ofi^.Extents := LL_New(sizeof(TClusterExtent));
                            if ofi^.Extents <> nil then
                                fatAppendExtent(ofi^.Extents, extent^.StartCluster, extent^.ClusterCount);
                        end;
                        if (oldClusters = 0) and (i = 0) then
                            cluster := extent^.StartCluster;
                    end;
                end;
                LL_Free(newExtents);
            end;

            if ofi <> nil then
                ofi^.FatDirty := true;

            if ofi <> nil then
                ofi^.AllocClusters := targetClusters;

            { Update chain cache: last new cluster is the new tail }
            updateSIOC(volume, cluster, targetClusters - 1, lastCluster);

        end;

        fileSize := newEnd;
    end;

    { ---- Walk to starting cluster using cache, then write sector by sector ---- }
    startClusterIdx := offset div bytesPerCluster;
    inClusterOffset := offset mod bytesPerCluster;

    if not seekToClusterIndex(volume, cluster, startClusterIdx, lookup.BootRecord, curCluster, chainPos) then begin
        io.syslog.logln('FAT32', 'writeFileAtOffset: exit-C chain broke seeking to start');
        if ofi = nil then begin
            if namePart <> nil then kfree(void(namePart));
            if extPart <> nil then kfree(void(extPart));
            LL_Free(lookup.Dirs);
            kfree(puint32(lookup.BootRecord));
            kfree(puint32(lookup.Status));
        end;
        exit;
    end;

    spc       := uint32(lookup.BootRecord^.spc);
    secSize   := uint32(lookup.BootRecord^.sectorSize);
    if (ofi <> nil) and (ofi^.ScratchSector <> nil) and (ofi^.ScratchSize >= secSize) then
        ioBuf := ofi^.ScratchSector
    else
        ioBuf := nil;
    remaining := byteCount;
    srcPos    := 0;

    while (remaining > 0) do begin
        { Build contiguous cluster run starting at curCluster }
        run.StartCluster := curCluster;
        buildContiguousRun(volume, curCluster, spc, MAX_RUN_SECTORS, lookup.BootRecord, run.RunLen, run.LastCluster);
        curCluster := run.LastCluster;

        run.RunSectors := run.RunLen * spc;
        run.RunBytes   := run.RunSectors * secSize;
        run.LBA        := clusterToLBA(dataStart, spc, run.StartCluster);

        if srcPos = 0 then
            skipBytes := inClusterOffset
        else
            skipBytes := 0;

        copyBytes := run.RunBytes - skipBytes;
        if copyBytes > remaining then
            copyBytes := remaining;

        firstSectorOff := skipBytes mod secSize;

        { Phase 1: Partial first sector — read-modify-write }
        if firstSectorOff > 0 then begin
            if ioBuf = nil then
                ioBuf := puint32(kalloc(secSize));
            if ioBuf = nil then
                break;
            sectorLBA := run.LBA + (skipBytes div secSize);
            partialBytes := secSize - firstSectorOff;
            if partialBytes > copyBytes then
                partialBytes := copyBytes;
            driver.storage.mgr.storage_read(volume^.device, sectorLBA, 1, ioBuf);
            core.util.memcpy(uint32(buffer) + srcPos, uint32(ioBuf) + firstSectorOff, partialBytes);
            driver.storage.mgr.storage_write(volume^.device, sectorLBA, 1, ioBuf);
            srcPos    := srcPos + partialBytes;
            remaining := remaining - partialBytes;
            copyBytes := copyBytes - partialBytes;
            skipBytes := skipBytes + partialBytes;
        end;

        { Phase 2: Full sectors — batch write directly from caller buffer }
        fullSectors := copyBytes div secSize;
        if fullSectors > 0 then begin
            sectorLBA := run.LBA + (skipBytes div secSize);
            batchBytes := fullSectors * secSize;
            driver.storage.mgr.storage_write(volume^.device, sectorLBA, fullSectors,
                puint32(uint32(buffer) + srcPos));
            srcPos    := srcPos + batchBytes;
            remaining := remaining - batchBytes;
            copyBytes := copyBytes - batchBytes;
            skipBytes := skipBytes + batchBytes;
        end;

        { Phase 3: Partial last sector — read-modify-write }
        if copyBytes > 0 then begin
            if ioBuf = nil then
                ioBuf := puint32(kalloc(secSize));
            if ioBuf = nil then
                break;
            sectorLBA := run.LBA + (skipBytes div secSize);
            driver.storage.mgr.storage_read(volume^.device, sectorLBA, 1, ioBuf);
            core.util.memcpy(uint32(buffer) + srcPos, uint32(ioBuf), copyBytes);
            driver.storage.mgr.storage_write(volume^.device, sectorLBA, 1, ioBuf);
            srcPos    := srcPos + copyBytes;
            remaining := remaining - copyBytes;
        end;

        { Update chain cache to last cluster in this run }
        updateSIOC(volume, cluster, chainPos + run.RunLen - 1, curCluster);
        chainPos := chainPos + run.RunLen;

        if remaining > 0 then begin
            nextFat := readFat(volume, curCluster, lookup.BootRecord);
            if ((nextFat and $0FFFFFFF) >= $0FFFFFF8) or (nextFat = 0) then begin
                io.syslog.log('FAT32', 'writeFileAtOffset: exit-D chain broke in write loop, srcPos=');
                io.syslog.writeint(srcPos);
                io.syslog.writestring(' remaining=');
                io.syslog.writeint(remaining);
                io.syslog.writestring(' cluster=');
                io.syslog.writeint(curCluster);
                io.syslog.writestring(' fat=');
                io.syslog.writehexln(nextFat);
                break;
            end;
            curCluster := nextFat;
        end;
    end;

    if (ioBuf <> nil) and ((ofi = nil) or (ioBuf <> ofi^.ScratchSector)) then
        kfree(ioBuf);

    { Flush dirty FAT cache entries to disk only for uncached callers.
      Open-file callers defer this to fat32CloseFile to avoid flushing on every chunk. }
    if ofi = nil then begin
        fatCache := fatCacheGet(volume);
        if fatCache <> nil then
            fatCacheFlush(fatCache, volume);
    end;

    { ---- Update directory entry byteSize if file was extended ---- }
    { Only commit actual bytes written — never advance size past what was really written (Lesson 22) }
    if (srcPos > 0) and ((offset + srcPos) > origByteSize) then begin
        if ofi <> nil then begin
            ofi^.MetaDirty := true;
        end else begin
        { Lesson 18: search raw directory sectors, don't use LL indices.
          dirCluster, cleanFileName, extPart were set once in the discovery phase. }
        dirBuf := puint32(kalloc(lookup.BootRecord^.sectorSize));

        if locateDirEntry(volume, dirCluster, lookup.BootRecord, cleanFileName, extPart, loc, dirBuf) then begin
            rawDir := @PDirectory(dirBuf)[loc.EntryIdx];
            rawDir^.byteSize := offset + srcPos;
            { If file was zero-length, update cluster pointers too }
            if origByteSize = 0 then
                setDirFirstCluster(rawDir, cluster);
            driver.storage.mgr.storage_write(volume^.device, loc.SectorLBA, 1, dirBuf);
        end;

        kfree(dirBuf);
        end;
    end;

    { Update cached open-file metadata so the next read/write sees the new state }
    if ofi <> nil then begin
        if (srcPos > 0) and ((offset + srcPos) > ofi^.ByteSize) then
            ofi^.ByteSize := offset + srcPos;
        if (ofi^.FirstCluster = 0) and (cluster <> 0) then begin
            ofi^.FirstCluster := cluster;
            ofi^.Exists := true;
            ofi^.MetaDirty := true;
        end;
    end;

    if ofi = nil then begin
        if namePart <> nil then kfree(void(namePart));
        if extPart <> nil then kfree(void(extPart));
        LL_Free(lookup.Dirs);
        kfree(puint32(lookup.BootRecord));
        kfree(puint32(lookup.Status));
    end;
    writeFileAtOffset := srcPos;
    push_trace('driver.storage.fs.fat32.writeFileAtOffset.exit');
end;

{ Read byteCount bytes from a file beginning at byte offset 'offset'.
  Returns the number of bytes actually read (may be less than byteCount if EOF reached).

  NOTE: This implementation reads sectors sequentially from the first cluster of the
  file, consistent with the existing readFile behaviour.  It does NOT follow the FAT
  chain between clusters \u2014 it assumes contiguous allocation.  This is acceptable for
  the initial streaming implementation.  A future improvement should cache the last
  visited (offset, cluster) pair in the open-file entry to make sequential chunked
  reads O(1) per call instead of O(n) in the FAT chain length. }

function getFileSize(volume : PStorage_Volume; directory : pchar; fileName : pchar) : uint32;
var
    bootRecord       : PBootRecord;
    dirs             : PLinkedListBase;
    tempdir          : PDirectory;
    statusOut        : puint32;
    i                : uint32;
    cleanFileName    : byteArray8;
    otherCFN         : byteArray8;
    namePart         : pchar;
    extPart          : pchar;
    fsize            : uint32;
begin
    push_trace('driver.storage.fs.fat32.getFileSize.enter');
    getFileSize := 0;

    statusOut := puint32(kalloc(sizeof(uint32)));
    statusOut^ := 0;
    bootRecord := readBootRecord(volume);
    dirs := readDirectory(volume, directory, statusOut);

    splitFileNameParts(fileName, namePart, extPart);

    fsize := 0;
    if LL_size(dirs) > 0 then begin
        cleanFileName := cleanString(namePart, statusOut);
        for i := 0 to LL_Size(dirs) - 1 do begin
            tempdir := PDirectory(LL_get(dirs, i));
            otherCFN := cleanString(tempdir^.filename, statusOut);
            if compareByteArray8(cleanFileName, otherCFN) and matchExtension(tempdir^.fileExtension, extPart) then begin
                fsize := tempdir^.byteSize;
                break;
            end;
        end;
    end;

    kfree(void(namePart));
    kfree(void(extPart));
    LL_Free(dirs);
    kfree(puint32(bootRecord));
    kfree(puint32(statusOut));
    getFileSize := fsize;
    push_trace('driver.storage.fs.fat32.getFileSize.exit');
end;

function readFileAtOffset(volume : PStorage_Volume; directory : pchar; fileName : pchar; offset : uint32; buffer : puint32; byteCount : uint32; ctx : pointer) : uint32;
const
    MAX_RUN_SECTORS = 2048;  { cap per multi-sector read = 1 MB }
var
    lookup           : TFileLookup;
    run              : TRunInfo;
    ofi              : PFATOpenFile;
    i                : uint32;
    cluster          : uint32;
    dataStart        : uint32;
    cleanFileName    : byteArray8;
    otherCFN         : byteArray8;
    tempdir          : PDirectory;
    namePart         : pchar;
    extPart          : pchar;
    bytesPerCluster  : uint32;
    startClusterIdx  : uint32;
    inClusterOffset  : uint32;
    chainPos         : uint32;
    curCluster       : uint32;
    destPos          : uint32;
    remaining        : uint32;
    fileSize         : uint32;
    nextFat          : uint32;
    spc              : uint32;
    secSize          : uint32;
    { Multi-sector run variables }
    runBuf           : puint32;
    skipBytes        : uint32;  { bytes to skip at start of run buffer }
    copyBytes        : uint32;
    chunkSectors     : uint32;
    chunkBytes       : uint32;
begin
    push_trace('driver.storage.fs.fat32.readFileAtOffset.enter');
    readFileAtOffset := 0;
    ofi := PFATOpenFile(ctx);

    if ofi <> nil then begin
        { Fast path: use cached open-file metadata }
        lookup.BootRecord := ofi^.BootRecord;
        lookup.Dirs := nil;
        lookup.Dir := nil;
        lookup.Status := nil;
        lookup.Exists := ofi^.Exists;
        dataStart := ofi^.DataStart;
        if lookup.Exists then begin
            fileSize := ofi^.ByteSize;
            cluster := ofi^.FirstCluster;
        end else begin
            fileSize := 0;
            cluster := 0;
        end;
    end else begin
        { Slow path: rediscover everything from disk }
        lookup.Status := puint32(kalloc(sizeof(uint32)));
        lookup.Status^ := 0;
        lookup.BootRecord := readBootRecord(volume);
        lookup.Dirs := readDirectory(volume, directory, lookup.Status);
        lookup.Exists := false;
        dataStart := fatDataStartLBA(volume, lookup.BootRecord);

        splitFileNameParts(fileName, namePart, extPart);

        if LL_size(lookup.Dirs) > 0 then begin
            cleanFileName := cleanString(namePart, lookup.Status);
            for i := 0 to LL_Size(lookup.Dirs) - 1 do begin
                tempdir := PDirectory(LL_get(lookup.Dirs, i));
                otherCFN := cleanString(tempdir^.filename, lookup.Status);
                if compareByteArray8(cleanFileName, otherCFN) and matchExtension(tempdir^.fileExtension, extPart) then begin
                    lookup.Dir := tempdir;
                    lookup.Exists := true;
                end;
            end;
        end;

        kfree(void(namePart));
        kfree(void(extPart));

        if lookup.Exists then begin
            fileSize := lookup.Dir^.byteSize;
            cluster := dirFirstCluster(lookup.Dir);
        end else begin
            fileSize := 0;
            cluster := 0;
        end;
    end;

    if not lookup.Exists then begin
        if ofi = nil then begin
            LL_Free(lookup.Dirs);
            kfree(puint32(lookup.BootRecord));
            kfree(puint32(lookup.Status));
        end;
        push_trace('driver.storage.fs.fat32.readFileAtOffset.notFound');
        exit;
    end;

    if offset >= fileSize then begin
        if ofi = nil then begin
            LL_Free(lookup.Dirs);
            kfree(puint32(lookup.BootRecord));
            kfree(puint32(lookup.Status));
        end;
        exit;
    end;

    { Clamp read length to not exceed file size }
    remaining := byteCount;
    if offset + remaining > fileSize then
        remaining := fileSize - offset;

    spc     := uint32(lookup.BootRecord^.spc);
    secSize := uint32(lookup.BootRecord^.sectorSize);
    bytesPerCluster := spc * secSize;
    startClusterIdx := offset div bytesPerCluster;
    inClusterOffset := offset mod bytesPerCluster;

    { Determine curCluster at startClusterIdx using SIOC cache }
    if not seekToClusterIndex(volume, cluster, startClusterIdx, lookup.BootRecord, curCluster, chainPos) then begin
        if ofi = nil then begin
            LL_Free(lookup.Dirs);
            kfree(puint32(lookup.BootRecord));
            kfree(puint32(lookup.Status));
        end;
        exit;
    end;

    destPos := 0;

    while (remaining > 0) do begin
        { Build a contiguous cluster run starting at curCluster }
        run.StartCluster := curCluster;
        buildContiguousRun(volume, curCluster, spc, MAX_RUN_SECTORS, lookup.BootRecord, run.RunLen, curCluster);

        run.RunSectors := run.RunLen * spc;
        run.RunBytes   := run.RunSectors * secSize;
        run.LBA        := clusterToLBA(dataStart, spc, run.StartCluster);

        { Calculate how many bytes from this run we actually need }
        if destPos = 0 then
            skipBytes := inClusterOffset
        else
            skipBytes := 0;

        copyBytes := run.RunBytes - skipBytes;
        if copyBytes > remaining then
            copyBytes := remaining;

        { Determine if we can read directly into caller's buffer (aligned, full run) }
        if (skipBytes = 0) and (copyBytes >= run.RunBytes) then begin
            { Direct read into output buffer — no temp allocation }
            driver.storage.mgr.storage_read(volume^.device, run.LBA, run.RunSectors,
                puint32(uint32(buffer) + destPos));
            destPos   := destPos + copyBytes;
            remaining := remaining - copyBytes;
        end else if (skipBytes = 0) and ((copyBytes mod secSize) = 0) then begin
            { Partial run but sector-aligned — read only needed sectors }
            chunkSectors := copyBytes div secSize;
            driver.storage.mgr.storage_read(volume^.device, run.LBA, chunkSectors,
                puint32(uint32(buffer) + destPos));
            destPos   := destPos + copyBytes;
            remaining := remaining - copyBytes;
        end else begin
            { Unaligned — need temp buffer for partial first/last sectors }
            { Only allocate for sectors we actually touch }
            chunkSectors := (skipBytes + copyBytes + secSize - 1) div secSize;
            if chunkSectors > run.RunSectors then chunkSectors := run.RunSectors;
            chunkBytes := chunkSectors * secSize;
            runBuf := puint32(kalloc(chunkBytes));
            run.LBA := clusterToLBA(dataStart, spc, run.StartCluster) + (skipBytes div secSize);

            { Adjust skipBytes for sectors we're skipping entirely }
            skipBytes := skipBytes mod secSize;
            driver.storage.mgr.storage_read(volume^.device, run.LBA, chunkSectors, runBuf);
            core.util.memcpy(uint32(runBuf) + skipBytes, uint32(buffer) + destPos, copyBytes);
            kfree(runBuf);
            destPos   := destPos + copyBytes;
            remaining := remaining - copyBytes;
        end;

        { Update SIOC chain cache to last cluster in this run }
        updateSIOC(volume, cluster, chainPos + run.RunLen - 1, curCluster);
        chainPos := chainPos + run.RunLen;

        { Advance to next cluster beyond this run }
        if remaining > 0 then begin
            nextFat := readFat(volume, curCluster, lookup.BootRecord);
            if ((nextFat and $0FFFFFFF) >= $0FFFFFF8) or (nextFat = 0) then
                break;
            curCluster := nextFat;
        end;
    end;

    if ofi = nil then begin
        LL_Free(lookup.Dirs);
        kfree(puint32(lookup.BootRecord));
        kfree(puint32(lookup.Status));
    end;
    readFileAtOffset := destPos;
    push_trace('driver.storage.fs.fat32.readFileAtOffset.exit');
end;

procedure readFileAtOffsetAsync(volume : PStorage_Volume; directory : pchar; fileName : pchar;
                                offset : uint32; buffer : puint32; byteCount : uint32;
                                ctx : pointer; bytesRead : puint32;
                                callback : TIOCallback; callbackData : pointer);
var
    ofi             : PFATOpenFile;
    asyncCtx        : PFATFileIOAsyncCtx;
    sectorLBA       : uint32;
    chunkSectors    : uint32;
    err             : TError;
begin
    if bytesRead <> nil then bytesRead^ := 0;
    ofi := PFATOpenFile(ctx);

    if (ofi = nil) or (buffer = nil) or (byteCount = 0) then begin
        if callback <> nil then callback(eInvalidArgument, callbackData);
        exit;
    end;

    if not ofi^.Exists then begin
        if callback <> nil then callback(eFileDoesNotExist, callbackData);
        exit;
    end;

    if offset >= ofi^.ByteSize then begin
        if callback <> nil then callback(eNone, callbackData);
        exit;
    end;

    if offset + byteCount > ofi^.ByteSize then
        byteCount := ofi^.ByteSize - offset;

    if ((offset mod ofi^.BootRecord^.sectorSize) <> 0) or ((byteCount mod ofi^.BootRecord^.sectorSize) <> 0) then begin
        if bytesRead <> nil then
            bytesRead^ := readFileAtOffset(volume, directory, fileName, offset, buffer, byteCount, ctx);
        if callback <> nil then callback(eNone, callbackData);
        exit;
    end;

    asyncCtx := fatTransferAlloc(volume);
    if asyncCtx = nil then begin
        if callback <> nil then callback(eOutOfMemory, callbackData);
        exit;
    end;
    asyncCtx^.Mode := famRead;
    asyncCtx^.State := ftsPrepare;
    asyncCtx^.Volume := volume;
    asyncCtx^.OpenFile := ofi;
    asyncCtx^.Buffer := buffer;
    asyncCtx^.Offset := offset;
    asyncCtx^.ByteCount := byteCount;
    asyncCtx^.BytesOut := bytesRead;
    asyncCtx^.Callback := callback;
    asyncCtx^.CallbackData := callbackData;
    asyncCtx^.Cluster := ofi^.FirstCluster;
    asyncCtx^.DataStart := ofi^.DataStart;
    asyncCtx^.BootRecord := ofi^.BootRecord;
    asyncCtx^.LastError := eNone;
    asyncCtx^.CursorValid := false;
    asyncCtx^.ExtentValid := false;
    if fat32_fileio_prepare_single_run(asyncCtx, sectorLBA, chunkSectors) and
       (asyncCtx^.ChunkBytes = asyncCtx^.ByteCount) then begin
        err := driver.storage.mgr.storage_read_async(
            volume^.device, sectorLBA, chunkSectors, buffer,
            @fat32_fileio_direct_complete, asyncCtx);
        if err <> eNone then begin
            fatTransferFree(asyncCtx);
            if callback <> nil then callback(err, callbackData);
        end;
        exit;
    end;
    fatWorkerEnsure(volume);
    if not fatScheduleTransfer(asyncCtx) then begin
        fatTransferFree(asyncCtx);
        if callback <> nil then callback(eQueueFull, callbackData);
    end;
end;

procedure writeFileAtOffsetAsync(volume : PStorage_Volume; directory : pchar; fileName : pchar;
                                 offset : uint32; buffer : puint32; byteCount : uint32;
                                 ctx : pointer; bytesWritten : puint32;
                                 callback : TIOCallback; callbackData : pointer);
var
    ofi             : PFATOpenFile;
    asyncCtx        : PFATFileIOAsyncCtx;
    cluster         : uint32;
    dataStart       : uint32;
    origByteSize    : uint32;
    newEnd          : uint32;
    bytesPerCluster : uint32;
    oldClusters     : uint32;
    needClusters    : uint32;
    targetClusters  : uint32;
    extraClusters   : uint32;
    newExtents      : PLinkedListBase;
    lastCluster     : uint32;
    nextFat         : uint32;
    i               : uint32;
    extent          : PClusterExtent;
    dirBuf          : puint32;
    rawDir          : PDirectory;
    loc             : TDirEntryLocation;
    chainWalkLimit  : uint32;
    firstNewCluster : uint32;
    reserveClusters : uint32;
    sectorLBA       : uint32;
    chunkSectors    : uint32;
    err             : TError;
begin
    if bytesWritten <> nil then bytesWritten^ := 0;
    ofi := PFATOpenFile(ctx);

    if (ofi = nil) or (buffer = nil) or (byteCount = 0) then begin
        if callback <> nil then callback(eInvalidArgument, callbackData);
        exit;
    end;

    if ((offset mod ofi^.BootRecord^.sectorSize) <> 0) or ((byteCount mod ofi^.BootRecord^.sectorSize) <> 0) then begin
        if bytesWritten <> nil then
            bytesWritten^ := writeFileAtOffset(volume, directory, fileName, offset, buffer, byteCount, ctx);
        if callback <> nil then callback(eNone, callbackData);
        exit;
    end;

    dataStart := ofi^.DataStart;
    origByteSize := ofi^.ByteSize;
    if ofi^.BootRecord^.sectorSize > 0 then
        chainWalkLimit := (ofi^.BootRecord^.FATSize * ofi^.BootRecord^.sectorSize) div 4
    else
        chainWalkLimit := 0;
    if ofi^.Exists then
        cluster := ofi^.FirstCluster
    else
        cluster := 0;

    if not ofi^.Exists then begin
        dirBuf := puint32(kalloc(ofi^.BootRecord^.sectorSize));
        if dirBuf = nil then begin
            if callback <> nil then callback(eOutOfMemory, callbackData);
            exit;
        end;
        if not locateFreeDirEntry(volume, ofi^.DirCluster, ofi^.BootRecord, loc, dirBuf) then begin
            kfree(dirBuf);
            if callback <> nil then callback(eDirectoryFull, callbackData);
            exit;
        end;
        rawDir := @PDirectory(dirBuf)[loc.EntryIdx];
        memset(uint32(rawDir), 0, sizeof(TDirectory));
        rawDir^.fileName := ofi^.CleanName;
        rawDir^.attributes := 0;
        fillFatExt(rawDir^.fileExtension, ofi^.ExtPart);
        rawDir^.clusterLow := 0;
        rawDir^.clusterHigh := 0;
        rawDir^.byteSize := 0;
        driver.storage.mgr.storage_write(volume^.device, loc.SectorLBA, 1, dirBuf);
        kfree(dirBuf);
        ofi^.Exists := true;
        sioc_valid := false;
    end;

    newEnd := offset + byteCount;
    bytesPerCluster := uint32(ofi^.BootRecord^.spc) * uint32(ofi^.BootRecord^.sectorSize);

    if newEnd > origByteSize then begin
        oldClusters := ofi^.AllocClusters;
        needClusters := fatClustersForBytes(newEnd, bytesPerCluster);
        targetClusters := needClusters;
        if needClusters > oldClusters then begin
            reserveClusters := fatPreallocClusterCount(bytesPerCluster);
            targetClusters := oldClusters + reserveClusters;
            if targetClusters < needClusters then
                targetClusters := needClusters;
        end;

        if targetClusters > oldClusters then begin
            extraClusters := targetClusters - oldClusters;
            if oldClusters > 0 then begin
                if sioc_valid and (sioc_vol = volume) and (sioc_fileClust = cluster) then
                    lastCluster := sioc_chainClust
                else
                    lastCluster := cluster;
                nextFat := readFat(volume, lastCluster, ofi^.BootRecord);
                while ((nextFat and $0FFFFFFF) < $0FFFFFF8) and (nextFat <> 0) do begin
                    if chainWalkLimit = 0 then begin
                        if callback <> nil then callback(eCorruptFilesystem, callbackData);
                        exit;
                    end;
                    chainWalkLimit := chainWalkLimit - 1;
                    lastCluster := nextFat;
                    nextFat := readFat(volume, lastCluster, ofi^.BootRecord);
                end;
            end else
                lastCluster := 0;

            if fatFindContiguousFreeRange(volume, extraClusters, ofi^.BootRecord, firstNewCluster) then begin
                fatLinkContiguousRange(volume, ofi^.BootRecord, lastCluster, firstNewCluster, extraClusters, lastCluster);
                if oldClusters = 0 then
                    cluster := firstNewCluster;
                if ofi^.Extents = nil then
                    ofi^.Extents := LL_New(sizeof(TClusterExtent));
                if ofi^.Extents <> nil then
                    fatAppendExtent(ofi^.Extents, firstNewCluster, extraClusters);
            end else begin
                newExtents := findFreeClusterExtents(volume, extraClusters, ofi^.BootRecord);
                if newExtents = nil then begin
                    if callback <> nil then callback(eDiskFull, callbackData);
                    exit;
                end;

                if LL_Size(newExtents) > 0 then begin
                    for i := 0 to LL_Size(newExtents) - 1 do begin
                        extent := PClusterExtent(LL_Get(newExtents, i));
                        fatLinkContiguousRange(volume, ofi^.BootRecord, lastCluster,
                            extent^.StartCluster, extent^.ClusterCount, lastCluster);
                        if extent <> nil then begin
                            if ofi^.Extents = nil then
                                ofi^.Extents := LL_New(sizeof(TClusterExtent));
                            if ofi^.Extents <> nil then
                                fatAppendExtent(ofi^.Extents, extent^.StartCluster, extent^.ClusterCount);
                        end;
                        if (oldClusters = 0) and (i = 0) then
                            cluster := extent^.StartCluster;
                    end;
                end;
                LL_Free(newExtents);
            end;

            ofi^.FatDirty := true;
            ofi^.AllocClusters := targetClusters;
            updateSIOC(volume, cluster, targetClusters - 1, lastCluster);
        end;
    end;

    asyncCtx := fatTransferAlloc(volume);
    if asyncCtx = nil then begin
        if callback <> nil then callback(eOutOfMemory, callbackData);
        exit;
    end;
    asyncCtx^.Mode := famWrite;
    asyncCtx^.State := ftsPrepare;
    asyncCtx^.Volume := volume;
    asyncCtx^.OpenFile := ofi;
    asyncCtx^.Buffer := buffer;
    asyncCtx^.Offset := offset;
    asyncCtx^.ByteCount := byteCount;
    asyncCtx^.BytesOut := bytesWritten;
    asyncCtx^.Callback := callback;
    asyncCtx^.CallbackData := callbackData;
    asyncCtx^.Cluster := cluster;
    asyncCtx^.OrigByteSize := origByteSize;
    asyncCtx^.DataStart := dataStart;
    asyncCtx^.BootRecord := ofi^.BootRecord;

    if (cluster <> 0) and ((offset + byteCount) > ofi^.ByteSize) then
        ofi^.MetaDirty := true;

    asyncCtx^.LastError := eNone;
    asyncCtx^.CursorValid := false;
    asyncCtx^.ExtentValid := false;
    if fat32_fileio_prepare_single_run(asyncCtx, sectorLBA, chunkSectors) and
       (asyncCtx^.ChunkBytes = asyncCtx^.ByteCount) then begin
        err := driver.storage.mgr.storage_write_async(
            volume^.device, sectorLBA, chunkSectors, buffer,
            @fat32_fileio_direct_complete, asyncCtx);
        if err <> eNone then begin
            fatTransferFree(asyncCtx);
            if callback <> nil then callback(err, callbackData);
        end;
        exit;
    end;
    fatWorkerEnsure(volume);
    if not fatScheduleTransfer(asyncCtx) then begin
        fatTransferFree(asyncCtx);
        if callback <> nil then callback(eQueueFull, callbackData);
    end;
end;

procedure init();
begin
    push_trace('driver.storage.fs.fat32.init()');
    io.syslog.logln('FAT32', 'init: registering FAT32 filesystem');
    filesystem.sName:= 'FAT32'; 
    filesystem.system_id:= $01; 
    filesystem.readDirCallback:= @readDirectoryGen;
    filesystem.createDirCallback:= @writeDirectoryGen;
    filesystem.createcallback:= @create_volume;
    filesystem.createAsyncCallback := @create_volume_async;
    filesystem.detectcallback:= @detect_volumes;
    filesystem.readOffsetCallback := @readFileAtOffset;
    filesystem.writeOffsetCallback := @writeFileAtOffset;
    filesystem.readOffsetAsyncCallback := @readFileAtOffsetAsync;
    filesystem.writeOffsetAsyncCallback := @writeFileAtOffsetAsync;
    filesystem.fileSizeCallback := @getFileSize;
    filesystem.identifyCallback := @identify_volume;
    filesystem.deleteFileCallback := @deleteFile;
    filesystem.deleteDirCallback := @deleteDir;
    filesystem.renameFileCallback := @renameFile;
    filesystem.openFileCallback := @fat32OpenFile;
    filesystem.closeFileCallback := @fat32CloseFile;
    { Async callbacks: nil - VFS falls through to the sync callbacks above.
      All disk I/O uses psAwaiting in submit_io_wait: the calling process is
      parked cleanly (CPU-free) while the driver.storage.ctl.ahci ISR completes the request. }
    filesystem.createDirAsyncCallback  := nil;
    filesystem.readDirAsyncCallback    := nil;

    driver.storage.fs.mgr.register_filesystem(@filesystem);
    io.syslog.logln('FAT32', 'init: done');
end;

initialization
    boot.mgr.registerBoot('driver.storage.fs.fat32', @Init, 'FAT32 Filesystem', 'driver.storage.fs.mgr');

end.
