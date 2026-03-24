unit driver.storage.fs.fat32.core;

interface

uses
    core.ds.lists,
    memory.heap,
    driver.storage.mgr,
    driver.storage.types,
    core.strings,

    core.util, arch.x86.util,
    debug.tracer,
    io.syslog,
    driver.storage.fs.fat32.types;

function FAT32GetVolumeCtx(volume : PStorage_Volume) : PFATVolumeCtx;
function FAT32GetVolumeInfo(volume : PStorage_Volume) : PFATVolumeInfo;
procedure FAT32Flush(volume : PStorage_Volume);
procedure FAT32ReleaseVolumeCtx(volume : PStorage_Volume);

function FAT32OpenFile(volume : PStorage_Volume; directory : pchar; fileName : pchar; var fileSize : uint32) : pointer;
procedure FAT32CloseFile(ctx : pointer);
function FAT32GetFileSize(volume : PStorage_Volume; directory : pchar; fileName : pchar) : uint32;
function FAT32ReadDirectory(volume : PStorage_Volume; directory : pchar; statusOut : puint32) : PLinkedListBase;
procedure FAT32CreateDirectory(volume : PStorage_Volume; directory : pchar; dirName : pchar; attributes : uint32; statusOut : puint32);
procedure FAT32DeleteFile(volume : PStorage_Volume; filePath : pchar; statusOut : puint32);
procedure FAT32DeleteDir(volume : PStorage_Volume; path : pchar; statusOut : puint32);
procedure FAT32RenameFile(volume : PStorage_Volume; filePath : pchar; newName : pchar; statusOut : puint32);

function FAT32TransferAlloc(volume : PStorage_Volume) : PFATTransferCtx;
procedure FAT32TransferFree(ctx : PFATTransferCtx);

function FAT32FindRunForOffset(ofi : PFATOpenFile; fileOffset : uint32;
    hintValid : boolean; hintRunIdx : uint32; hintFileCluster : uint32;
    var outRunIdx : uint32; var outRunFileCluster : uint32;
    var outStartCluster : uint32; var outClusterOffset : uint32;
    var outAvailableBytes : uint32) : boolean;

function FAT32EnsureCapacityForWrite(ofi : PFATOpenFile; offset : uint32; byteCount : uint32) : TError;
function FAT32EnsureDirEntry(ofi : PFATOpenFile) : TError;
function FAT32GetReadLimit(ofi : PFATOpenFile; offset : uint32; byteCount : uint32) : uint32;
function FAT32ClusterToLBA(info : PFATVolumeInfo; cluster : uint32) : uint32;

implementation

type
    PFATTempRun = ^TFATRun;
    PFATVolumeCtxNode = ^TFATVolumeCtxNode;
    TFATVolumeCtxNode = record
        Volume : PStorage_Volume;
        Ctx    : PFATVolumeCtx;
        Next   : PFATVolumeCtxNode;
    end;

var
    sioc_allocHint : uint32 = 2;
    sioc_allocVol  : PStorage_Volume = nil;
    fatCtxListHead : PFATVolumeCtxNode = nil;

function readFat(volume : PStorage_Volume; cluster : uint32; bootRecord : PBootRecord) : uint32; forward;
procedure writeFat(volume : PStorage_Volume; cluster : uint32; value : uint32; bootRecord : PBootRecord); forward;
procedure fatFreeClusterChain(volume : PStorage_Volume; info : PFATVolumeInfo; startCluster : uint32); forward;
function fatInitDirectoryCluster(volume : PStorage_Volume; info : PFATVolumeInfo; cluster : uint32; parentCluster : uint32) : boolean; forward;

function isEndOfChain(value : uint32) : boolean;
begin
    isEndOfChain := (value and $0FFFFFFF) >= $0FFFFFF8;
end;

function isBadCluster(value : uint32) : boolean;
begin
    isBadCluster := (value and $0FFFFFFF) = $0FFFFFF7;
end;

function FAT32ClusterToLBA(info : PFATVolumeInfo; cluster : uint32) : uint32;
begin
    if cluster < 2 then
        FAT32ClusterToLBA := info^.DataStart
    else
        FAT32ClusterToLBA := info^.DataStart + ((cluster - 2) * info^.BootRecord.spc);
end;

function dirFirstCluster(dir : PDirectory) : uint32;
begin
    dirFirstCluster := uint32(dir^.clusterLow) or (uint32(dir^.clusterHigh) shl 16);
end;

procedure setDirFirstCluster(dir : PDirectory; cluster : uint32);
begin
    dir^.clusterLow := uint16(cluster and $FFFF);
    dir^.clusterHigh := uint16((cluster shr 16) and $FFFF);
end;

function fatMaxClusterCount(bootRecord : PBootRecord) : uint32;
begin
    if (bootRecord = nil) or (bootRecord^.sectorSize = 0) then
        fatMaxClusterCount := 0
    else
        fatMaxClusterCount := (bootRecord^.FATSize * bootRecord^.sectorSize) div 4;
end;

function fatClustersForBytes(byteCount : uint32; bytesPerCluster : uint32) : uint32;
begin
    if (byteCount = 0) or (bytesPerCluster = 0) then
        fatClustersForBytes := 0
    else
        fatClustersForBytes := (byteCount + bytesPerCluster - 1) div bytesPerCluster;
end;

{ Register ofi in the volume write-ref table (call once DirLoc is valid). }
procedure fatRegisterWriteHandle(volCtx : PFATVolumeCtx; ofi : PFATOpenFile);
var
    i        : uint32;
    freeSlot : sint32;
begin
    if (volCtx = nil) or (ofi = nil) or ofi^.Registered then exit;
    asm pushf; cli end;
    freeSlot := -1;
    for i := 0 to FAT_OPEN_HANDLE_SLOTS - 1 do begin
        if (volCtx^.WriteRefs[i].Count > 0) and
           (volCtx^.WriteRefs[i].SectorLBA = ofi^.DirLoc.SectorLBA) and
           (volCtx^.WriteRefs[i].EntryIdx  = ofi^.DirLoc.EntryIdx) then begin
            volCtx^.WriteRefs[i].Count := volCtx^.WriteRefs[i].Count + 1;
            ofi^.Registered := true;
            asm popf end;
            exit;
        end;
        if (freeSlot < 0) and (volCtx^.WriteRefs[i].Count = 0) then
            freeSlot := sint32(i);
    end;
    if freeSlot >= 0 then begin
        volCtx^.WriteRefs[uint32(freeSlot)].SectorLBA := ofi^.DirLoc.SectorLBA;
        volCtx^.WriteRefs[uint32(freeSlot)].EntryIdx  := ofi^.DirLoc.EntryIdx;
        volCtx^.WriteRefs[uint32(freeSlot)].Count     := 1;
        ofi^.Registered := true;
    end;
    { If all slots are full, Registered stays false → truncation skipped for safety }
    asm popf end;
end;

{ Unregister ofi and return the count that was present before decrement. }
function fatUnregisterWriteHandle(volCtx : PFATVolumeCtx; ofi : PFATOpenFile) : uint32;
var
    i : uint32;
begin
    fatUnregisterWriteHandle := 0;
    if (volCtx = nil) or (ofi = nil) or not ofi^.Registered then exit;
    asm pushf; cli end;
    for i := 0 to FAT_OPEN_HANDLE_SLOTS - 1 do begin
        if (volCtx^.WriteRefs[i].Count > 0) and
           (volCtx^.WriteRefs[i].SectorLBA = ofi^.DirLoc.SectorLBA) and
           (volCtx^.WriteRefs[i].EntryIdx  = ofi^.DirLoc.EntryIdx) then begin
            fatUnregisterWriteHandle := volCtx^.WriteRefs[i].Count;
            volCtx^.WriteRefs[i].Count := volCtx^.WriteRefs[i].Count - 1;
            ofi^.Registered := false;
            asm popf end;
            exit;
        end;
    end;
    asm popf end;
end;

function fatPreallocClusterCount(bytesPerCluster : uint32) : uint32;
begin
    { Always pre-allocate FAT_WRITE_PREALLOC_MAX_CLUSTERS.  The MIN guard
      keeps the value sane if the constant is ever lowered below MIN. }
    fatPreallocClusterCount := FAT_WRITE_PREALLOC_MAX_CLUSTERS;
    if fatPreallocClusterCount < FAT_WRITE_PREALLOC_MIN_CLUSTERS then
        fatPreallocClusterCount := FAT_WRITE_PREALLOC_MIN_CLUSTERS;
end;

function isValidFAT32Name(fullName : pchar) : boolean;
var
    i, fnLen, dotPos, nameLen, extLen : uint32;
    c : char;
begin
    isValidFAT32Name := false;
    if fullName = nil then exit;
    fnLen := stringSize(fullName);
    if fnLen = 0 then exit;

    dotPos := fnLen;
    if fnLen > 0 then
    for i := 0 to fnLen - 1 do
        if fullName[i] = '.' then
            dotPos := i;

    nameLen := dotPos;
    if dotPos < fnLen then
        extLen := fnLen - dotPos - 1
    else
        extLen := 0;

    if (nameLen < 1) or (nameLen > 8) then exit;
    if extLen > 3 then exit;

    if fnLen > 0 then
    for i := 0 to fnLen - 1 do begin
        c := fullName[i];
        if i = dotPos then continue;
        if uint8(c) < $20 then exit;
        case c of
            '"', '*', '/', ':', '<', '>', '?', '\', '|': exit;
        end;
    end;

    isValidFAT32Name := true;
end;

function matchExtension(dirExt : TFATExtArray; ext : pchar) : boolean;
var
    j : uint32;
    c : char;
    extDone : boolean;
begin
    matchExtension := true;
    extDone := false;
    for j := 0 to 2 do begin
        if (not extDone) and (ext <> nil) and (ext[j] <> char(0)) then begin
            c := ext[j];
            if (c >= 'a') and (c <= 'z') then
                c := char(uint8(c) - 32);
        end else begin
            c := ' ';
            extDone := true;
        end;
        if dirExt[j] <> c then begin
            matchExtension := false;
            exit;
        end;
    end;
end;

function compareByteArray8(str1 : byteArray8; str2 : byteArray8) : boolean;
var
    i : uint32;
begin
    compareByteArray8 := true;
    for i := 0 to 7 do
        if str1[i] <> str2[i] then begin
            compareByteArray8 := false;
            exit;
        end;
end;

function cleanString(str : pchar) : byteArray8;
var
    i : uint32;
begin
    for i := 0 to 7 do
        cleanString[i] := ' ';
    if str = nil then exit;
    for i := 0 to 7 do begin
        if str[i] = char(0) then
            exit;
        if (str[i] >= 'a') and (str[i] <= 'z') then
            cleanString[i] := char(uint8(str[i]) - 32)
        else
            cleanString[i] := str[i];
    end;
end;

procedure splitFileNameParts(fullName : pchar; var nameOut : pchar; var extOut : pchar);
var
    fnLen, dotPos, i : uint32;
begin
    nameOut := nil;
    extOut := nil;
    if fullName = nil then begin
        nameOut := stringNew(0);
        extOut := stringNew(0);
        exit;
    end;
    fnLen := stringSize(fullName);
    dotPos := fnLen;
    if fnLen > 0 then
    for i := 0 to fnLen - 1 do
        if fullName[i] = '.' then
            dotPos := i;
    nameOut := stringTrim(fullName, dotPos);
    if dotPos < fnLen then
        extOut := stringCopy(pchar(@fullName[dotPos + 1]))
    else
        extOut := stringNew(0);
end;

procedure fillFatExt(var dest : TFATExtArray; extPart : pchar);
var
    j : uint32;
begin
    dest[0] := ' ';
    dest[1] := ' ';
    dest[2] := ' ';
    if extPart = nil then exit;
    for j := 0 to 2 do begin
        if extPart[j] = char(0) then exit;
        if (extPart[j] >= 'a') and (extPart[j] <= 'z') then
            dest[j] := char(uint8(extPart[j]) - 32)
        else
            dest[j] := extPart[j];
    end;
end;

procedure splitPathParts(fullPath : pchar; var parentOut : pchar; var nameOut : pchar);
var
    pathLen   : uint32;
    lastSlash : uint32;
    i         : uint32;
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

    lastSlash := pathLen;
    for i := 0 to pathLen - 1 do
        if fullPath[i] = '/' then
            lastSlash := i;

    if lastSlash < pathLen then begin
        parentOut := stringTrim(fullPath, lastSlash);
        nameOut := stringCopy(pchar(@fullPath[lastSlash + 1]));
    end else begin
        parentOut := stringNew(0);
        nameOut := stringCopy(fullPath);
    end;
end;

function fatEntryName(dir : PDirectory) : pchar;
var
    nameLen : uint32;
    extLen  : uint32;
    nameBuf : pchar;
begin
    fatEntryName := nil;
    if dir = nil then exit;

    nameLen := 8;
    while (nameLen > 0) and (dir^.fileName[nameLen - 1] = ' ') do
        nameLen := nameLen - 1;

    extLen := 3;
    while (extLen > 0) and (dir^.fileExtension[extLen - 1] = ' ') do
        extLen := extLen - 1;

    if extLen > 0 then begin
        nameBuf := pchar(kalloc(nameLen + extLen + 2));
        if nameBuf = nil then exit;
        memcpy(uint32(@dir^.fileName[0]), uint32(nameBuf), nameLen);
        nameBuf[nameLen] := '.';
        memcpy(uint32(@dir^.fileExtension[0]), uint32(@nameBuf[nameLen + 1]), extLen);
        nameBuf[nameLen + extLen + 1] := char(0);
    end else begin
        nameBuf := pchar(kalloc(nameLen + 1));
        if nameBuf = nil then exit;
        memcpy(uint32(@dir^.fileName[0]), uint32(nameBuf), nameLen);
        nameBuf[nameLen] := char(0);
    end;

    fatEntryName := nameBuf;
end;

function fatIsDotEntry(dir : PDirectory) : boolean;
begin
    fatIsDotEntry := false;
    if dir = nil then exit;
    if dir^.fileName[0] <> '.' then exit;
    if (dir^.fileName[1] = ' ') or (dir^.fileName[1] = '.') then
        fatIsDotEntry := true;
end;

function readBootRecordRaw(volume : PStorage_Volume; var bootRecord : TBootRecord) : boolean;
var
    sectorBuf : puint32;
    bufSize   : uint32;
begin
    readBootRecordRaw := false;
    bufSize := volume^.device^.sectorSize;
    if bufSize < 512 then bufSize := 512;
    sectorBuf := puint32(kalloc(bufSize));
    if sectorBuf = nil then exit;
    memset(uint32(sectorBuf), 0, bufSize);
    driver.storage.mgr.storage_read(volume^.device, volume^.sectorStart, 1, sectorBuf);
    bootRecord := PBootRecord(sectorBuf)^;
    kfree(sectorBuf);
    readBootRecordRaw := true;
end;

function fatNextHintStamp(ctx : PFATVolumeCtx) : uint32;
begin
    fatNextHintStamp := 0;
    if ctx = nil then exit;
    ctx^.HintStamp := ctx^.HintStamp + 1;
    if ctx^.HintStamp = 0 then
        ctx^.HintStamp := 1;
    fatNextHintStamp := ctx^.HintStamp;
end;

procedure fatRememberAllocHint(volume : PStorage_Volume; startCluster : uint32; clusterCount : uint32);
var
    ctx       : PFATVolumeCtx;
    slot      : uint32;
    replace   : uint32;
    bestStamp : uint32;
    stamp     : uint32;
begin
    if (volume = nil) or (startCluster < 2) or (clusterCount = 0) then exit;
    ctx := FAT32GetVolumeCtx(volume);
    if ctx = nil then exit;

    stamp := fatNextHintStamp(ctx);
    replace := 0;
    bestStamp := $FFFFFFFF;
    for slot := 0 to FAT_ALLOC_HINT_SLOTS - 1 do begin
        if ctx^.AllocHints[slot].Valid and (ctx^.AllocHints[slot].StartCluster = startCluster) then begin
            ctx^.AllocHints[slot].ClusterCount := clusterCount;
            ctx^.AllocHints[slot].Stamp := stamp;
            exit;
        end;
        if not ctx^.AllocHints[slot].Valid then begin
            replace := slot;
            bestStamp := 0;
            break;
        end;
        if ctx^.AllocHints[slot].Stamp < bestStamp then begin
            bestStamp := ctx^.AllocHints[slot].Stamp;
            replace := slot;
        end;
    end;

    ctx^.AllocHints[replace].Valid := true;
    ctx^.AllocHints[replace].StartCluster := startCluster;
    ctx^.AllocHints[replace].ClusterCount := clusterCount;
    ctx^.AllocHints[replace].Stamp := stamp;
end;

procedure fatInvalidateAllocRange(volume : PStorage_Volume; startCluster : uint32; clusterCount : uint32);
var
    ctx      : PFATVolumeCtx;
    slot     : uint32;
    endCluster : uint32;
    hintEnd  : uint32;
    overlapStart : uint32;
begin
    if (volume = nil) or (startCluster < 2) or (clusterCount = 0) then exit;
    ctx := FAT32GetVolumeCtx(volume);
    if ctx = nil then exit;
    endCluster := startCluster + clusterCount;

    for slot := 0 to FAT_ALLOC_HINT_SLOTS - 1 do begin
        if not ctx^.AllocHints[slot].Valid then
            continue;
        hintEnd := ctx^.AllocHints[slot].StartCluster + ctx^.AllocHints[slot].ClusterCount;
        if (endCluster <= ctx^.AllocHints[slot].StartCluster) or (startCluster >= hintEnd) then
            continue;
        if (startCluster <= ctx^.AllocHints[slot].StartCluster) and (endCluster >= hintEnd) then begin
            ctx^.AllocHints[slot].Valid := false;
            continue;
        end;
        if startCluster <= ctx^.AllocHints[slot].StartCluster then begin
            ctx^.AllocHints[slot].StartCluster := endCluster;
            ctx^.AllocHints[slot].ClusterCount := hintEnd - endCluster;
            continue;
        end;
        overlapStart := startCluster - ctx^.AllocHints[slot].StartCluster;
        ctx^.AllocHints[slot].ClusterCount := overlapStart;
    end;
end;

function fatRangeIsFree(volume : PStorage_Volume; info : PFATVolumeInfo; startCluster : uint32; clusterCount : uint32) : boolean;
var
    cluster : uint32;
begin
    fatRangeIsFree := false;
    if (volume = nil) or (info = nil) or (clusterCount = 0) then exit;
    if (startCluster < 2) or ((startCluster + clusterCount) > info^.MaxCluster) then exit;
    for cluster := 0 to clusterCount - 1 do
        if readFat(volume, startCluster + cluster, @info^.BootRecord) <> 0 then
            exit;
    fatRangeIsFree := true;
end;

function fatTakeAllocHint(volume : PStorage_Volume; info : PFATVolumeInfo; amount : uint32; var runStart : uint32) : boolean;
var
    ctx       : PFATVolumeCtx;
    slot      : uint32;
    bestSlot  : sint32;
    bestStamp : uint32;
    stamp     : uint32;
begin
    fatTakeAllocHint := false;
    if (volume = nil) or (info = nil) or (amount = 0) then exit;
    ctx := FAT32GetVolumeCtx(volume);
    if ctx = nil then exit;

    bestSlot := -1;
    bestStamp := 0;
    for slot := 0 to FAT_ALLOC_HINT_SLOTS - 1 do begin
        if not ctx^.AllocHints[slot].Valid then
            continue;
        if ctx^.AllocHints[slot].ClusterCount < amount then
            continue;
        if (bestSlot < 0) or (ctx^.AllocHints[slot].Stamp > bestStamp) then begin
            bestSlot := sint32(slot);
            bestStamp := ctx^.AllocHints[slot].Stamp;
        end;
    end;

    while bestSlot >= 0 do begin
        if fatRangeIsFree(volume, info, ctx^.AllocHints[uint32(bestSlot)].StartCluster, amount) then begin
            runStart := ctx^.AllocHints[uint32(bestSlot)].StartCluster;
            ctx^.AllocHints[uint32(bestSlot)].StartCluster := runStart + amount;
            ctx^.AllocHints[uint32(bestSlot)].ClusterCount := ctx^.AllocHints[uint32(bestSlot)].ClusterCount - amount;
            if ctx^.AllocHints[uint32(bestSlot)].ClusterCount = 0 then
                ctx^.AllocHints[uint32(bestSlot)].Valid := false
            else begin
                stamp := fatNextHintStamp(ctx);
                ctx^.AllocHints[uint32(bestSlot)].Stamp := stamp;
            end;
            fatTakeAllocHint := true;
            exit;
        end;
        ctx^.AllocHints[uint32(bestSlot)].Valid := false;
        bestSlot := -1;
        bestStamp := 0;
        for slot := 0 to FAT_ALLOC_HINT_SLOTS - 1 do begin
            if not ctx^.AllocHints[slot].Valid then
                continue;
            if ctx^.AllocHints[slot].ClusterCount < amount then
                continue;
            if (bestSlot < 0) or (ctx^.AllocHints[slot].Stamp > bestStamp) then begin
                bestSlot := sint32(slot);
                bestStamp := ctx^.AllocHints[slot].Stamp;
            end;
        end;
    end;
end;

procedure fatRememberDirHint(volume : PStorage_Volume; parentCluster : uint32; sectorLBA : uint32; entryIdx : uint32);
var
    ctx       : PFATVolumeCtx;
    slot      : uint32;
    replace   : uint32;
    bestStamp : uint32;
    stamp     : uint32;
begin
    if (volume = nil) or (parentCluster < 2) then exit;
    ctx := FAT32GetVolumeCtx(volume);
    if ctx = nil then exit;

    stamp := fatNextHintStamp(ctx);
    replace := 0;
    bestStamp := $FFFFFFFF;
    for slot := 0 to FAT_DIR_HINT_SLOTS - 1 do begin
        if ctx^.DirHints[slot].Valid
           and (ctx^.DirHints[slot].ParentCluster = parentCluster)
           and (ctx^.DirHints[slot].SectorLBA = sectorLBA)
           and (ctx^.DirHints[slot].EntryIdx = entryIdx) then begin
            ctx^.DirHints[slot].Stamp := stamp;
            exit;
        end;
        if not ctx^.DirHints[slot].Valid then begin
            replace := slot;
            bestStamp := 0;
            break;
        end;
        if ctx^.DirHints[slot].Stamp < bestStamp then begin
            bestStamp := ctx^.DirHints[slot].Stamp;
            replace := slot;
        end;
    end;

    ctx^.DirHints[replace].Valid := true;
    ctx^.DirHints[replace].ParentCluster := parentCluster;
    ctx^.DirHints[replace].SectorLBA := sectorLBA;
    ctx^.DirHints[replace].EntryIdx := entryIdx;
    ctx^.DirHints[replace].Stamp := stamp;
end;

procedure fatForgetDirHintsForParent(volume : PStorage_Volume; parentCluster : uint32);
var
    ctx  : PFATVolumeCtx;
    slot : uint32;
begin
    if (volume = nil) or (parentCluster < 2) then exit;
    ctx := FAT32GetVolumeCtx(volume);
    if ctx = nil then exit;
    for slot := 0 to FAT_DIR_HINT_SLOTS - 1 do
        if ctx^.DirHints[slot].Valid and (ctx^.DirHints[slot].ParentCluster = parentCluster) then
            ctx^.DirHints[slot].Valid := false;
end;

function fatCtxLookup(volume : PStorage_Volume) : PFATVolumeCtx;
var
    node : PFATVolumeCtxNode;
begin
    fatCtxLookup := nil;
    node := fatCtxListHead;
    while node <> nil do begin
        if node^.Volume = volume then begin
            fatCtxLookup := node^.Ctx;
            exit;
        end;
        node := node^.Next;
    end;
end;

function fatCtxRegister(volume : PStorage_Volume; ctx : PFATVolumeCtx) : boolean;
var
    node : PFATVolumeCtxNode;
begin
    fatCtxRegister := false;
    node := PFATVolumeCtxNode(kalloc(sizeof(TFATVolumeCtxNode)));
    if node = nil then exit;
    memset(uint32(node), 0, sizeof(TFATVolumeCtxNode));
    node^.Volume := volume;
    node^.Ctx := ctx;
    node^.Next := fatCtxListHead;
    fatCtxListHead := node;
    fatCtxRegister := true;
end;

function fatCtxDetach(volume : PStorage_Volume) : PFATVolumeCtx;
var
    prev : PFATVolumeCtxNode;
    node : PFATVolumeCtxNode;
begin
    fatCtxDetach := nil;
    prev := nil;
    asm pushf; cli end;
    node := fatCtxListHead;
    while node <> nil do begin
        if node^.Volume = volume then begin
            fatCtxDetach := node^.Ctx;
            if prev = nil then
                fatCtxListHead := node^.Next
            else
                prev^.Next := node^.Next;
            kfree(void(node));
            asm popf end;
            exit;
        end;
        prev := node;
        node := node^.Next;
    end;
    asm popf end;
end;

procedure fatCtxFree(ctx : PFATVolumeCtx);
begin
    if ctx = nil then exit;
    if ctx^.Cache.Data <> nil then
        kfree(ctx^.Cache.Data);
    if ctx^.Cache.EvictBuf <> nil then
        kfree(ctx^.Cache.EvictBuf);
    if ctx^.TransferPoolBuf <> nil then
        kfree(ctx^.TransferPoolBuf);
    if ctx^.TransferScratchBuf <> nil then
        kfree(ctx^.TransferScratchBuf);
    kfree(void(ctx));
end;

function FAT32GetVolumeCtx(volume : PStorage_Volume) : PFATVolumeCtx;
var
    ctx        : PFATVolumeCtx;
    i          : uint32;
    transfer   : PFATTransferCtx;
    poolBase   : uint32;
    scratchBase: uint32;
begin
    FAT32GetVolumeCtx := nil;
    if volume = nil then exit;

    ctx := fatCtxLookup(volume);
    if ctx <> nil then begin
        FAT32GetVolumeCtx := ctx;
        exit;
    end;

    ctx := PFATVolumeCtx(kalloc(sizeof(TFATVolumeCtx)));
    if ctx = nil then exit;
    memset(uint32(ctx), 0, sizeof(TFATVolumeCtx));

    if not readBootRecordRaw(volume, ctx^.Info.BootRecord) then begin
        fatCtxFree(ctx);
        exit;
    end;

    { Keep runtime addressing compatible with the legacy formatter and metadata paths. }
    ctx^.Info.DataStart := volume^.sectorStart + ctx^.Info.BootRecord.rsvSectors +
        ctx^.Info.BootRecord.FATSize;
    ctx^.Info.BytesPerCluster := uint32(ctx^.Info.BootRecord.spc) * uint32(ctx^.Info.BootRecord.sectorSize);
    ctx^.Info.MaxCluster := fatMaxClusterCount(@ctx^.Info.BootRecord);
    ctx^.InfoValid := true;

    ctx^.Cache.Data := puint32(kalloc(FAT_CACHE_LINES * 512));
    ctx^.Cache.EvictBuf := puint32(kalloc(512));
    if (ctx^.Cache.Data = nil) or (ctx^.Cache.EvictBuf = nil) then begin
        fatCtxFree(ctx);
        exit;
    end;
    memset(uint32(ctx^.Cache.Data), 0, FAT_CACHE_LINES * 512);
    memset(uint32(ctx^.Cache.EvictBuf), 0, 512);
    ctx^.Cache.Busy := false;
    ctx^.Cache.FatStart := volume^.sectorStart + ctx^.Info.BootRecord.rsvSectors;
    ctx^.Cache.Device := volume^.device;
    for i := 0 to FAT_CACHE_LINES - 1 do begin
        ctx^.Cache.Lines[i].Valid := false;
        ctx^.Cache.Lines[i].Dirty := false;
        ctx^.Cache.Lines[i].LRU := uint8(i mod FAT_CACHE_WAYS);
    end;

    ctx^.TransferPoolBuf := kalloc(FAT_TRANSFER_POOL_CAPACITY * sizeof(TFATTransferCtx));
    ctx^.TransferScratchBuf := kalloc(FAT_TRANSFER_POOL_CAPACITY * ctx^.Info.BootRecord.sectorSize);
    if (ctx^.TransferPoolBuf <> nil) and (ctx^.TransferScratchBuf <> nil) then begin
        memset(uint32(ctx^.TransferPoolBuf), 0, FAT_TRANSFER_POOL_CAPACITY * sizeof(TFATTransferCtx));
        memset(uint32(ctx^.TransferScratchBuf), 0, FAT_TRANSFER_POOL_CAPACITY * ctx^.Info.BootRecord.sectorSize);
        poolBase := uint32(ctx^.TransferPoolBuf);
        scratchBase := uint32(ctx^.TransferScratchBuf);
        if FAT_TRANSFER_POOL_CAPACITY > 0 then
        for i := 0 to FAT_TRANSFER_POOL_CAPACITY - 1 do begin
            transfer := PFATTransferCtx(poolBase + (i * sizeof(TFATTransferCtx)));
            transfer^.Next := PFATTransferCtx(ctx^.TransferFreeList);
            transfer^.VolumeCtx := ctx;
            transfer^.ScratchSector := puint32(scratchBase + (i * ctx^.Info.BootRecord.sectorSize));
            transfer^.ScratchSize := ctx^.Info.BootRecord.sectorSize;
            ctx^.TransferFreeList := pointer(transfer);
        end;
    end;

    if not fatCtxRegister(volume, ctx) then begin
        fatCtxFree(ctx);
        exit;
    end;
    FAT32GetVolumeCtx := ctx;
end;

function FAT32GetVolumeInfo(volume : PStorage_Volume) : PFATVolumeInfo;
var
    ctx : PFATVolumeCtx;
begin
    ctx := FAT32GetVolumeCtx(volume);
    if ctx = nil then
        FAT32GetVolumeInfo := nil
    else
        FAT32GetVolumeInfo := @ctx^.Info;
end;

procedure fatCacheFlush(cache : PFATCache; volume : PStorage_Volume);
var
    i       : uint32;
    lba     : uint32;
    doFlush : boolean;
begin
    if cache = nil then exit;

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
        doFlush := cache^.Lines[i].Valid and cache^.Lines[i].Dirty;
        if doFlush then begin
            lba := cache^.FatStart + cache^.Lines[i].SectorIdx;
            cache^.Lines[i].Dirty := false;
            memcpy(uint32(cache^.Data) + (i * 512), uint32(cache^.EvictBuf), 512);
        end;
        asm popf end;
        if doFlush then
            driver.storage.mgr.storage_write(volume^.device, lba, 1, cache^.EvictBuf);
    end;

    asm pushf; cli end;
    cache^.Busy := false;
    asm popf end;
end;

procedure FAT32Flush(volume : PStorage_Volume);
var
    ctx : PFATVolumeCtx;
begin
    ctx := FAT32GetVolumeCtx(volume);
    if ctx = nil then exit;
    fatCacheFlush(@ctx^.Cache, volume);
end;

procedure FAT32ReleaseVolumeCtx(volume : PStorage_Volume);
var
    ctx : PFATVolumeCtx;
begin
    if volume = nil then exit;
    ctx := fatCtxDetach(volume);
    if ctx = nil then exit;
    fatCacheFlush(@ctx^.Cache, volume);
    fatCtxFree(ctx);
end;

function readFat(volume : PStorage_Volume; cluster : uint32; bootRecord : PBootRecord) : uint32;
var
    ctx        : PFATVolumeCtx;
    cache      : PFATCache;
    fatSecIdx  : uint32;
    setIdx     : uint32;
    baseSlot   : uint32;
    entryOff   : uint32;
    dataPtr    : puint32;
    lba        : uint32;
    doEvict    : boolean;
    evictLBA   : uint32;
    victim     : uint32;
    w          : uint32;
begin
    ctx := FAT32GetVolumeCtx(volume);
    if ctx = nil then begin
        readFat := 0;
        exit;
    end;
    cache := @ctx^.Cache;
    fatSecIdx := cluster div 128;
    setIdx := fatSecIdx mod FAT_CACHE_SETS;
    baseSlot := setIdx * FAT_CACHE_WAYS;
    entryOff := cluster mod 128;

    asm pushf; cli end;
    for w := 0 to FAT_CACHE_WAYS - 1 do
        if cache^.Lines[baseSlot + w].Valid and (cache^.Lines[baseSlot + w].SectorIdx = fatSecIdx) then begin
            dataPtr := puint32(uint32(cache^.Data) + ((baseSlot + w) * 512));
            readFat := dataPtr[entryOff] and $0FFFFFFF;
            cache^.Lines[baseSlot + w].LRU := 0;
            cache^.Lines[baseSlot + (1 - w)].LRU := 1;
            asm popf end;
            exit;
        end;
    asm popf end;

    while true do begin
        asm pushf; cli end;
        if not cache^.Busy then begin
            for w := 0 to FAT_CACHE_WAYS - 1 do
                if cache^.Lines[baseSlot + w].Valid and (cache^.Lines[baseSlot + w].SectorIdx = fatSecIdx) then begin
                    dataPtr := puint32(uint32(cache^.Data) + ((baseSlot + w) * 512));
                    readFat := dataPtr[entryOff] and $0FFFFFFF;
                    cache^.Lines[baseSlot + w].LRU := 0;
                    cache^.Lines[baseSlot + (1 - w)].LRU := 1;
                    asm popf end;
                    exit;
                end;
            cache^.Busy := true;
            victim := baseSlot;
            if not cache^.Lines[baseSlot].Valid then
                victim := baseSlot
            else if not cache^.Lines[baseSlot + 1].Valid then
                victim := baseSlot + 1
            else if cache^.Lines[baseSlot + 1].LRU >= cache^.Lines[baseSlot].LRU then
                victim := baseSlot + 1
            else
                victim := baseSlot;
            dataPtr := puint32(uint32(cache^.Data) + (victim * 512));
            doEvict := cache^.Lines[victim].Valid and cache^.Lines[victim].Dirty;
            if doEvict then begin
                evictLBA := cache^.FatStart + cache^.Lines[victim].SectorIdx;
                memcpy(uint32(dataPtr), uint32(cache^.EvictBuf), 512);
            end;
            cache^.Lines[victim].Valid := false;
            asm popf end;
            break;
        end;
        asm popf end;
        asm hlt end;
    end;

    if doEvict then
        driver.storage.mgr.storage_write(cache^.Device, evictLBA, 1, cache^.EvictBuf);
    lba := cache^.FatStart + fatSecIdx;
    driver.storage.mgr.storage_read(cache^.Device, lba, 1, dataPtr);

    asm pushf; cli end;
    cache^.Lines[victim].SectorIdx := fatSecIdx;
    cache^.Lines[victim].Valid := true;
    cache^.Lines[victim].Dirty := false;
    cache^.Lines[victim].LRU := 0;
    if victim = baseSlot then
        cache^.Lines[baseSlot + 1].LRU := 1
    else
        cache^.Lines[baseSlot].LRU := 1;
    readFat := dataPtr[entryOff] and $0FFFFFFF;
    cache^.Busy := false;
    asm popf end;
end;

procedure writeFat(volume : PStorage_Volume; cluster : uint32; value : uint32; bootRecord : PBootRecord);
var
    ctx        : PFATVolumeCtx;
    cache      : PFATCache;
    fatSecIdx  : uint32;
    setIdx     : uint32;
    baseSlot   : uint32;
    entryOff   : uint32;
    dataPtr    : puint32;
    lba        : uint32;
    doEvict    : boolean;
    evictLBA   : uint32;
    victim     : uint32;
    w          : uint32;
begin
    ctx := FAT32GetVolumeCtx(volume);
    if ctx = nil then exit;
    cache := @ctx^.Cache;
    fatSecIdx := cluster div 128;
    setIdx := fatSecIdx mod FAT_CACHE_SETS;
    baseSlot := setIdx * FAT_CACHE_WAYS;
    entryOff := cluster mod 128;

    asm pushf; cli end;
    for w := 0 to FAT_CACHE_WAYS - 1 do
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
    asm popf end;

    while true do begin
        asm pushf; cli end;
        if not cache^.Busy then begin
            for w := 0 to FAT_CACHE_WAYS - 1 do
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
            cache^.Busy := true;
            victim := baseSlot;
            if not cache^.Lines[baseSlot].Valid then
                victim := baseSlot
            else if not cache^.Lines[baseSlot + 1].Valid then
                victim := baseSlot + 1
            else if cache^.Lines[baseSlot + 1].LRU >= cache^.Lines[baseSlot].LRU then
                victim := baseSlot + 1
            else
                victim := baseSlot;
            dataPtr := puint32(uint32(cache^.Data) + (victim * 512));
            doEvict := cache^.Lines[victim].Valid and cache^.Lines[victim].Dirty;
            if doEvict then begin
                evictLBA := cache^.FatStart + cache^.Lines[victim].SectorIdx;
                memcpy(uint32(dataPtr), uint32(cache^.EvictBuf), 512);
            end;
            cache^.Lines[victim].Valid := false;
            asm popf end;
            break;
        end;
        asm popf end;
        asm hlt end;
    end;

    if doEvict then
        driver.storage.mgr.storage_write(cache^.Device, evictLBA, 1, cache^.EvictBuf);
    lba := cache^.FatStart + fatSecIdx;
    driver.storage.mgr.storage_read(cache^.Device, lba, 1, dataPtr);

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

function runMapEnsureCapacity(var runMap : TFATRunMap; needed : uint32) : boolean;
var
    newCapacity : uint32;
    newRuns     : PFATRun;
begin
    runMapEnsureCapacity := true;
    if needed <= runMap.Capacity then exit;
    newCapacity := runMap.Capacity;
    if newCapacity = 0 then
        newCapacity := 4;
    while newCapacity < needed do
        newCapacity := newCapacity * 2;
    newRuns := PFATRun(kalloc(newCapacity * sizeof(TFATRun)));
    if newRuns = nil then begin
        runMapEnsureCapacity := false;
        exit;
    end;
    memset(uint32(newRuns), 0, newCapacity * sizeof(TFATRun));
    if (runMap.Runs <> nil) and (runMap.Count > 0) then
        memcpy(uint32(runMap.Runs), uint32(newRuns), runMap.Count * sizeof(TFATRun));
    if runMap.Runs <> nil then
        kfree(void(runMap.Runs));
    runMap.Runs := newRuns;
    runMap.Capacity := newCapacity;
end;

procedure runMapFree(var runMap : TFATRunMap);
begin
    if runMap.Runs <> nil then
        kfree(void(runMap.Runs));
    runMap.Runs := nil;
    runMap.Count := 0;
    runMap.Capacity := 0;
    runMap.TotalClusters := 0;
end;

function runMapAppend(var runMap : TFATRunMap; startCluster : uint32; clusterCount : uint32) : boolean;
var
    lastRun : PFATRun;
begin
    runMapAppend := false;
    if clusterCount = 0 then exit;
    if runMap.Count > 0 then begin
        lastRun := @runMap.Runs[runMap.Count - 1];
        if (lastRun^.StartCluster + lastRun^.ClusterCount) = startCluster then begin
            lastRun^.ClusterCount := lastRun^.ClusterCount + clusterCount;
            runMap.TotalClusters := runMap.TotalClusters + clusterCount;
            runMapAppend := true;
            exit;
        end;
    end;
    if not runMapEnsureCapacity(runMap, runMap.Count + 1) then exit;
    runMap.Runs[runMap.Count].StartCluster := startCluster;
    runMap.Runs[runMap.Count].ClusterCount := clusterCount;
    runMap.Count := runMap.Count + 1;
    runMap.TotalClusters := runMap.TotalClusters + clusterCount;
    runMapAppend := true;
end;

function buildRunMap(volume : PStorage_Volume; info : PFATVolumeInfo; firstCluster : uint32; var runMap : TFATRunMap) : boolean;
var
    currentCluster : uint32;
    nextCluster    : uint32;
    runStart       : uint32;
    runCount       : uint32;
    iterCount      : uint32;
begin
    buildRunMap := false;
    runMapFree(runMap);
    if (info = nil) or (firstCluster < 2) then begin
        buildRunMap := true;
        exit;
    end;

    currentCluster := firstCluster;
    runStart := firstCluster;
    runCount := 1;
    iterCount := 0;

    while true do begin
        if (info^.MaxCluster > 0) and (iterCount >= info^.MaxCluster) then
            exit;
        if (currentCluster < 2) or ((info^.MaxCluster > 0) and (currentCluster >= info^.MaxCluster)) then
            exit;

        nextCluster := readFat(volume, currentCluster, @info^.BootRecord);
        if isBadCluster(nextCluster) then exit;

        if isEndOfChain(nextCluster) then begin
            if not runMapAppend(runMap, runStart, runCount) then exit;
            buildRunMap := true;
            exit;
        end;

        if nextCluster = 0 then exit;

        if nextCluster = (currentCluster + 1) then
            runCount := runCount + 1
        else begin
            if not runMapAppend(runMap, runStart, runCount) then exit;
            runStart := nextCluster;
            runCount := 1;
        end;

        currentCluster := nextCluster;
        iterCount := iterCount + 1;
    end;
end;

function findEntryInSector(buffer : puint32; entriesPerSector : uint32;
    cleanName : byteArray8; ext : pchar; var hitEnd : boolean) : integer;
var
    idx : uint32;
    dir : PDirectory;
begin
    findEntryInSector := -1;
    hitEnd := false;
    if entriesPerSector = 0 then exit;
    for idx := 0 to entriesPerSector - 1 do begin
        dir := @PDirectory(buffer)[idx];
        if dir^.fileName[0] = char(0) then begin
            hitEnd := true;
            exit;
        end;
        if dir^.fileName[0] = char($E5) then
            continue;
        if compareByteArray8(dir^.fileName, cleanName) and matchExtension(dir^.fileExtension, ext) then begin
            findEntryInSector := integer(idx);
            exit;
        end;
    end;
end;

function findFreeEntryInSector(buffer : puint32; entriesPerSector : uint32) : integer;
var
    idx : uint32;
    dir : PDirectory;
begin
    findFreeEntryInSector := -1;
    if entriesPerSector = 0 then exit;
    for idx := 0 to entriesPerSector - 1 do begin
        dir := @PDirectory(buffer)[idx];
        if (dir^.fileName[0] = char(0)) or (dir^.fileName[0] = char($E5)) then begin
            findFreeEntryInSector := integer(idx);
            exit;
        end;
    end;
end;

function locateFreeDirEntryFromHint(volume : PStorage_Volume; info : PFATVolumeInfo; parentCluster : uint32;
    var loc : TFATDirEntryLocation; buffer : puint32) : boolean;
var
    ctx       : PFATVolumeCtx;
    slot      : uint32;
    bestSlot  : sint32;
    bestStamp : uint32;
    entryIdx  : integer;
begin
    locateFreeDirEntryFromHint := false;
    if (volume = nil) or (info = nil) or (parentCluster < 2) or (buffer = nil) then exit;
    ctx := FAT32GetVolumeCtx(volume);
    if ctx = nil then exit;

    bestSlot := -1;
    bestStamp := 0;
    for slot := 0 to FAT_DIR_HINT_SLOTS - 1 do begin
        if not ctx^.DirHints[slot].Valid then
            continue;
        if ctx^.DirHints[slot].ParentCluster <> parentCluster then
            continue;
        if (bestSlot < 0) or (ctx^.DirHints[slot].Stamp > bestStamp) then begin
            bestSlot := sint32(slot);
            bestStamp := ctx^.DirHints[slot].Stamp;
        end;
    end;

    while bestSlot >= 0 do begin
        driver.storage.mgr.storage_read(volume^.device, ctx^.DirHints[uint32(bestSlot)].SectorLBA, 1, buffer);
        entryIdx := findFreeEntryInSector(buffer, info^.BootRecord.sectorSize div sizeof(TDirectory));
        if (entryIdx >= 0) and (uint32(entryIdx) = ctx^.DirHints[uint32(bestSlot)].EntryIdx) then begin
            loc.Valid := true;
            loc.ParentCluster := parentCluster;
            loc.SectorLBA := ctx^.DirHints[uint32(bestSlot)].SectorLBA;
            loc.EntryIdx := uint32(entryIdx);
            ctx^.DirHints[uint32(bestSlot)].Stamp := fatNextHintStamp(ctx);
            locateFreeDirEntryFromHint := true;
            exit;
        end;

        ctx^.DirHints[uint32(bestSlot)].Valid := false;
        bestSlot := -1;
        bestStamp := 0;
        for slot := 0 to FAT_DIR_HINT_SLOTS - 1 do begin
            if not ctx^.DirHints[slot].Valid then
                continue;
            if ctx^.DirHints[slot].ParentCluster <> parentCluster then
                continue;
            if (bestSlot < 0) or (ctx^.DirHints[slot].Stamp > bestStamp) then begin
                bestSlot := sint32(slot);
                bestStamp := ctx^.DirHints[slot].Stamp;
            end;
        end;
    end;
end;

procedure fatRememberFreeEntryFromBuffer(volume : PStorage_Volume; parentCluster : uint32; sectorLBA : uint32;
    buffer : puint32; entriesPerSec : uint32);
var
    entryIdx : integer;
begin
    if buffer = nil then exit;
    entryIdx := findFreeEntryInSector(buffer, entriesPerSec);
    if entryIdx >= 0 then
        fatRememberDirHint(volume, parentCluster, sectorLBA, uint32(entryIdx))
    else
        fatForgetDirHintsForParent(volume, parentCluster);
end;

function locateDirEntry(volume : PStorage_Volume; info : PFATVolumeInfo; parentCluster : uint32;
    cleanName : byteArray8; ext : pchar; var loc : TFATDirEntryLocation; buffer : puint32) : boolean;
var
    currentCluster : uint32;
    nextCluster    : uint32;
    ds             : uint32;
    entryIdx       : integer;
    hitEnd         : boolean;
    entriesPerSec  : uint32;
    clusterLBA     : uint32;
    iterCount      : uint32;
begin
    locateDirEntry := false;
    loc.Valid := false;
    if (info = nil) or (parentCluster < 2) then exit;

    currentCluster := parentCluster;
    entriesPerSec := info^.BootRecord.sectorSize div sizeof(TDirectory);
    iterCount := 0;

    while currentCluster >= 2 do begin
        if (info^.MaxCluster > 0) and (iterCount >= info^.MaxCluster) then
            exit;
        if (info^.MaxCluster > 0) and (currentCluster >= info^.MaxCluster) then
            exit;

        clusterLBA := FAT32ClusterToLBA(info, currentCluster);
        for ds := 0 to info^.BootRecord.spc - 1 do begin
            driver.storage.mgr.storage_read(volume^.device, clusterLBA + ds, 1, buffer);
            entryIdx := findEntryInSector(buffer, entriesPerSec, cleanName, ext, hitEnd);
            if entryIdx >= 0 then begin
                loc.Valid := true;
                loc.ParentCluster := parentCluster;
                loc.SectorLBA := clusterLBA + ds;
                loc.EntryIdx := uint32(entryIdx);
                locateDirEntry := true;
                exit;
            end;
            if hitEnd then
                exit;
        end;

        nextCluster := readFat(volume, currentCluster, @info^.BootRecord);
        if isEndOfChain(nextCluster) or isBadCluster(nextCluster) or (nextCluster = 0) then
            exit;
        currentCluster := nextCluster;
        iterCount := iterCount + 1;
    end;
end;

function locateFreeDirEntry(volume : PStorage_Volume; info : PFATVolumeInfo; parentCluster : uint32;
    var loc : TFATDirEntryLocation; buffer : puint32) : boolean;
var
    currentCluster : uint32;
    nextCluster    : uint32;
    ds             : uint32;
    entryIdx       : integer;
    entriesPerSec  : uint32;
    clusterLBA     : uint32;
    iterCount      : uint32;
begin
    locateFreeDirEntry := false;
    loc.Valid := false;
    if (info = nil) or (parentCluster < 2) then exit;
    if locateFreeDirEntryFromHint(volume, info, parentCluster, loc, buffer) then begin
        locateFreeDirEntry := true;
        exit;
    end;

    currentCluster := parentCluster;
    entriesPerSec := info^.BootRecord.sectorSize div sizeof(TDirectory);
    iterCount := 0;

    while currentCluster >= 2 do begin
        if (info^.MaxCluster > 0) and (iterCount >= info^.MaxCluster) then
            exit;
        if (info^.MaxCluster > 0) and (currentCluster >= info^.MaxCluster) then
            exit;

        clusterLBA := FAT32ClusterToLBA(info, currentCluster);
        for ds := 0 to info^.BootRecord.spc - 1 do begin
            driver.storage.mgr.storage_read(volume^.device, clusterLBA + ds, 1, buffer);
            entryIdx := findFreeEntryInSector(buffer, entriesPerSec);
            if entryIdx >= 0 then begin
                loc.Valid := true;
                loc.ParentCluster := parentCluster;
                loc.SectorLBA := clusterLBA + ds;
                loc.EntryIdx := uint32(entryIdx);
                fatRememberDirHint(volume, parentCluster, loc.SectorLBA, loc.EntryIdx);
                locateFreeDirEntry := true;
                exit;
            end;
        end;

        nextCluster := readFat(volume, currentCluster, @info^.BootRecord);
        if isEndOfChain(nextCluster) or isBadCluster(nextCluster) or (nextCluster = 0) then
            exit;
        currentCluster := nextCluster;
        iterCount := iterCount + 1;
    end;
end;

function resolveDirectoryCluster(volume : PStorage_Volume; info : PFATVolumeInfo;
    directory : pchar; var parentCluster : uint32) : boolean;
var
    parts      : PLinkedListBase;
    partName   : pchar;
    namePart   : pchar;
    extPart    : pchar;
    cleanName  : byteArray8;
    sectorBuf  : puint32;
    loc        : TFATDirEntryLocation;
    rawDir     : PDirectory;
    i          : uint32;
begin
    resolveDirectoryCluster := false;
    parentCluster := info^.BootRecord.rootCluster;
    if (directory = nil) or (stringSize(directory) = 0) then begin
        resolveDirectoryCluster := true;
        exit;
    end;

    sectorBuf := puint32(kalloc(info^.BootRecord.sectorSize));
    if sectorBuf = nil then exit;
    parts := LL_fromString(directory, '/');

    if (parts <> nil) and (LL_Size(parts) > 0) then
    for i := 0 to LL_Size(parts) - 1 do begin
        partName := pchar(puint32(LL_Get(parts, i))^);
        if (partName = nil) or (partName[0] = char(0)) then
            continue;
        splitFileNameParts(partName, namePart, extPart);
        cleanName := cleanString(namePart);
        if not locateDirEntry(volume, info, parentCluster, cleanName, extPart, loc, sectorBuf) then begin
            if namePart <> nil then kfree(void(namePart));
            if extPart <> nil then kfree(void(extPart));
            LL_Free(parts);
            kfree(sectorBuf);
            exit;
        end;
        rawDir := @PDirectory(sectorBuf)[loc.EntryIdx];
        if (rawDir^.attributes and $10) <> $10 then begin
            if namePart <> nil then kfree(void(namePart));
            if extPart <> nil then kfree(void(extPart));
            LL_Free(parts);
            kfree(sectorBuf);
            exit;
        end;
        parentCluster := dirFirstCluster(rawDir);
        if namePart <> nil then kfree(void(namePart));
        if extPart <> nil then kfree(void(extPart));
    end;

    if parts <> nil then LL_Free(parts);
    kfree(sectorBuf);
    resolveDirectoryCluster := true;
end;

function FAT32EnsureDirEntry(ofi : PFATOpenFile) : TError;
var
    sectorBuf : puint32;
    rawDir    : PDirectory;
begin
    FAT32EnsureDirEntry := eNone;
    if ofi = nil then begin
        FAT32EnsureDirEntry := eInvalidArgument;
        exit;
    end;
    if ofi^.DirLoc.Valid then exit;

    sectorBuf := puint32(kalloc(ofi^.VolumeInfo^.BootRecord.sectorSize));
    if sectorBuf = nil then begin
        FAT32EnsureDirEntry := eOutOfMemory;
        exit;
    end;

    if not locateFreeDirEntry(ofi^.Volume, ofi^.VolumeInfo, ofi^.DirLoc.ParentCluster, ofi^.DirLoc, sectorBuf) then begin
        kfree(sectorBuf);
        FAT32EnsureDirEntry := eDirectoryFull;
        exit;
    end;

    rawDir := @PDirectory(sectorBuf)[ofi^.DirLoc.EntryIdx];
    memset(uint32(rawDir), 0, sizeof(TDirectory));
    rawDir^.fileName := ofi^.CleanName;
    rawDir^.attributes := 0;
    fillFatExt(rawDir^.fileExtension, ofi^.ExtPart);
    rawDir^.byteSize := 0;
    setDirFirstCluster(rawDir, 0);
    fatRememberFreeEntryFromBuffer(ofi^.Volume, ofi^.DirLoc.ParentCluster, ofi^.DirLoc.SectorLBA,
        sectorBuf, ofi^.VolumeInfo^.BootRecord.sectorSize div sizeof(TDirectory));
    driver.storage.mgr.storage_write(ofi^.Volume^.device, ofi^.DirLoc.SectorLBA, 1, sectorBuf);
    kfree(sectorBuf);
    ofi^.Exists := true;
end;

procedure fatUpdateAllocHint(volume : PStorage_Volume; info : PFATVolumeInfo; nextCluster : uint32);
begin
    if info^.MaxCluster <= 2 then begin
        sioc_allocHint := 2;
        sioc_allocVol := volume;
        exit;
    end;
    if nextCluster < 2 then
        nextCluster := 2;
    if nextCluster >= info^.MaxCluster then
        nextCluster := 2;
    sioc_allocHint := nextCluster;
    sioc_allocVol := volume;
end;

function fatTryContiguousRange(volume : PStorage_Volume; info : PFATVolumeInfo;
    rangeStart : uint32; rangeEnd : uint32; needed : uint32; var foundStart : uint32) : boolean;
var
    scanPos : uint32;
    runLen  : uint32;
    runPos  : uint32;
    fatVal  : uint32;
begin
    fatTryContiguousRange := false;
    if (needed = 0) or (rangeStart >= rangeEnd) then exit;
    scanPos := rangeStart;
    runLen := 0;
    runPos := 0;
    while scanPos < rangeEnd do begin
        fatVal := readFat(volume, scanPos, @info^.BootRecord);
        if fatVal = 0 then begin
            if runLen = 0 then
                runPos := scanPos;
            runLen := runLen + 1;
            if runLen >= needed then begin
                fatRememberAllocHint(volume, runPos, runLen);
                foundStart := runPos;
                fatTryContiguousRange := true;
                exit;
            end;
        end else begin
            if runLen > 0 then
                fatRememberAllocHint(volume, runPos, runLen);
            runLen := 0;
        end;
        scanPos := scanPos + 1;
    end;
    if runLen > 0 then
        fatRememberAllocHint(volume, runPos, runLen);
end;

function fatFindContiguousFreeRange(volume : PStorage_Volume; info : PFATVolumeInfo;
    amount : uint32; var runStart : uint32) : boolean;
var
    scanStart : uint32;
begin
    fatFindContiguousFreeRange := false;
    if amount = 0 then exit;
    if info^.MaxCluster <= 2 then exit;
    if fatTakeAllocHint(volume, info, amount, runStart) then begin
        fatFindContiguousFreeRange := true;
        exit;
    end;

    if (sioc_allocVol = volume) and (sioc_allocHint >= 2) and (sioc_allocHint < info^.MaxCluster) then
        scanStart := sioc_allocHint
    else
        scanStart := 2;

    if fatTryContiguousRange(volume, info, scanStart, info^.MaxCluster, amount, runStart) or
       ((scanStart > 2) and fatTryContiguousRange(volume, info, 2, scanStart, amount, runStart)) then
        fatFindContiguousFreeRange := true;
end;

procedure fatLinkContiguousRange(volume : PStorage_Volume; info : PFATVolumeInfo;
    previousTail : uint32; firstCluster : uint32; clusterCount : uint32; var lastCluster : uint32);
var
    cur : uint32;
    i   : uint32;
begin
    lastCluster := previousTail;
    if clusterCount = 0 then exit;
    fatInvalidateAllocRange(volume, firstCluster, clusterCount);
    if previousTail <> 0 then
        writeFat(volume, previousTail, firstCluster, @info^.BootRecord);
    cur := firstCluster;
    i := 1;
    while i < clusterCount do begin
        writeFat(volume, cur, cur + 1, @info^.BootRecord);
        cur := cur + 1;
        i := i + 1;
    end;
    writeFat(volume, cur, $0FFFFFF8, @info^.BootRecord);
    lastCluster := cur;
    fatUpdateAllocHint(volume, info, lastCluster + 1);
end;

function findFreeClusterRuns(volume : PStorage_Volume; info : PFATVolumeInfo; amount : uint32) : PLinkedListBase;
var
    runs          : PLinkedListBase;
    currentAmount : uint32;
    lastAllocated : uint32;
    scanStart     : uint32;

    procedure appendRun(firstCluster : uint32; clusterCount : uint32);
    var
        tempRun : PFATTempRun;
    begin
        fatRememberAllocHint(volume, firstCluster, clusterCount);
        tempRun := PFATTempRun(LL_Add(runs));
        tempRun^.StartCluster := firstCluster;
        tempRun^.ClusterCount := clusterCount;
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
            fatVal := readFat(volume, scanPos, @info^.BootRecord);
            if fatVal <> 0 then begin
                scanPos := scanPos + 1;
                continue;
            end;
            runStart := scanPos;
            runLen := 0;
            while scanPos < rangeEnd do begin
                fatVal := readFat(volume, scanPos, @info^.BootRecord);
                if fatVal <> 0 then break;
                runLen := runLen + 1;
                scanPos := scanPos + 1;
            end;
            takeCount := amount - currentAmount;
            if runLen < takeCount then
                takeCount := runLen;
            appendRun(runStart, takeCount);
        end;
    end;
begin
    runs := LL_New(sizeof(TFATRun));
    currentAmount := 0;
    lastAllocated := 0;
    if amount = 0 then begin
        findFreeClusterRuns := runs;
        exit;
    end;
    if info^.MaxCluster <= 2 then begin
        LL_Free(runs);
        findFreeClusterRuns := nil;
        exit;
    end;

    if (sioc_allocVol = volume) and (sioc_allocHint >= 2) and (sioc_allocHint < info^.MaxCluster) then
        scanStart := sioc_allocHint
    else
        scanStart := 2;

    scanRange(scanStart, info^.MaxCluster);
    if (currentAmount < amount) and (scanStart > 2) then
        scanRange(2, scanStart);

    if currentAmount < amount then begin
        LL_Free(runs);
        findFreeClusterRuns := nil;
        exit;
    end;
    fatUpdateAllocHint(volume, info, lastAllocated + 1);
    findFreeClusterRuns := runs;
end;

function FAT32FindRunForOffset(ofi : PFATOpenFile; fileOffset : uint32;
    hintValid : boolean; hintRunIdx : uint32; hintFileCluster : uint32;
    var outRunIdx : uint32; var outRunFileCluster : uint32;
    var outStartCluster : uint32; var outClusterOffset : uint32;
    var outAvailableBytes : uint32) : boolean;
var
    targetCluster   : uint32;
    clusterBase     : uint32;
    i               : uint32;
    bytesPerCluster : uint32;
    byteOffsetInCl  : uint32;
begin
    FAT32FindRunForOffset := false;
    if (ofi = nil) or (ofi^.VolumeInfo = nil) or (ofi^.RunMap.Count = 0) then
        exit;

    bytesPerCluster := ofi^.VolumeInfo^.BytesPerCluster;
    if bytesPerCluster = 0 then exit;

    targetCluster := fileOffset div bytesPerCluster;
    byteOffsetInCl := fileOffset mod bytesPerCluster;

    if hintValid and (hintRunIdx < ofi^.RunMap.Count) and (hintFileCluster <= targetCluster) then begin
        i := hintRunIdx;
        clusterBase := hintFileCluster;
    end else begin
        i := 0;
        clusterBase := 0;
    end;

    while i < ofi^.RunMap.Count do begin
        if targetCluster < (clusterBase + ofi^.RunMap.Runs[i].ClusterCount) then begin
            outRunIdx := i;
            outRunFileCluster := clusterBase;
            outClusterOffset := targetCluster - clusterBase;
            outStartCluster := ofi^.RunMap.Runs[i].StartCluster + outClusterOffset;
            outAvailableBytes := ((ofi^.RunMap.Runs[i].ClusterCount - outClusterOffset) * bytesPerCluster) - byteOffsetInCl;
            FAT32FindRunForOffset := true;
            exit;
        end;
        clusterBase := clusterBase + ofi^.RunMap.Runs[i].ClusterCount;
        i := i + 1;
    end;
end;

function FAT32EnsureCapacityForWrite(ofi : PFATOpenFile; offset : uint32; byteCount : uint32) : TError;
var
    newEnd         : uint32;
    needClusters   : uint32;
    targetClusters : uint32;
    reserve        : uint32;
    extraClusters    : uint32;
    lastCluster      : uint32;
    firstNew         : uint32;
    tempRuns         : PLinkedListBase;
    tempRun          : PFATTempRun;
    i                : uint32;
    lastTail         : uint32;
    prevLastCluster  : uint32;
begin
    FAT32EnsureCapacityForWrite := eNone;
    if (ofi = nil) or (ofi^.VolumeInfo = nil) then begin
        FAT32EnsureCapacityForWrite := eInvalidArgument;
        exit;
    end;

    if byteCount = 0 then exit;

    FAT32EnsureCapacityForWrite := FAT32EnsureDirEntry(ofi);
    if FAT32EnsureCapacityForWrite <> eNone then
        exit;

    { Register as a writer the first time we extend this file (DirLoc is now valid) }
    if not ofi^.Registered then
        fatRegisterWriteHandle(FAT32GetVolumeCtx(ofi^.Volume), ofi);

    newEnd := offset + byteCount;
    needClusters := fatClustersForBytes(newEnd, ofi^.VolumeInfo^.BytesPerCluster);
    targetClusters := needClusters;
    if needClusters > ofi^.AllocClusters then begin
        reserve := fatPreallocClusterCount(ofi^.VolumeInfo^.BytesPerCluster);
        targetClusters := ofi^.AllocClusters + reserve;
        if targetClusters < needClusters then
            targetClusters := needClusters;
    end;

    if targetClusters <= ofi^.AllocClusters then exit;

    extraClusters := targetClusters - ofi^.AllocClusters;
    if ofi^.RunMap.Count > 0 then
        lastCluster := ofi^.RunMap.Runs[ofi^.RunMap.Count - 1].StartCluster +
            ofi^.RunMap.Runs[ofi^.RunMap.Count - 1].ClusterCount - 1
    else
        lastCluster := 0;

    if fatFindContiguousFreeRange(ofi^.Volume, ofi^.VolumeInfo, extraClusters, firstNew) then begin
        fatLinkContiguousRange(ofi^.Volume, ofi^.VolumeInfo, lastCluster, firstNew, extraClusters, lastTail);
        if not runMapAppend(ofi^.RunMap, firstNew, extraClusters) then begin
            { Undo: free the newly linked clusters and restore the previous chain tail to EOC }
            fatFreeClusterChain(ofi^.Volume, ofi^.VolumeInfo, firstNew);
            if lastCluster >= 2 then
                writeFat(ofi^.Volume, lastCluster, $0FFFFFF8, @ofi^.VolumeInfo^.BootRecord);
            FAT32EnsureCapacityForWrite := eOutOfMemory;
            exit;
        end;
        if ofi^.FirstCluster = 0 then
            ofi^.FirstCluster := firstNew;
    end else begin
        tempRuns := findFreeClusterRuns(ofi^.Volume, ofi^.VolumeInfo, extraClusters);
        if tempRuns = nil then begin
            FAT32EnsureCapacityForWrite := eDiskFull;
            exit;
        end;
        for i := 0 to LL_Size(tempRuns) - 1 do begin
            tempRun := PFATTempRun(LL_Get(tempRuns, i));
            prevLastCluster := lastCluster;
            fatLinkContiguousRange(ofi^.Volume, ofi^.VolumeInfo, lastCluster,
                tempRun^.StartCluster, tempRun^.ClusterCount, lastTail);
            lastCluster := lastTail;
            if not runMapAppend(ofi^.RunMap, tempRun^.StartCluster, tempRun^.ClusterCount) then begin
                { Undo: free the current run and restore the previous tail to EOC }
                fatFreeClusterChain(ofi^.Volume, ofi^.VolumeInfo, tempRun^.StartCluster);
                if prevLastCluster >= 2 then
                    writeFat(ofi^.Volume, prevLastCluster, $0FFFFFF8, @ofi^.VolumeInfo^.BootRecord);
                { Sync AllocClusters with what actually made it into the RunMap }
                ofi^.AllocClusters := ofi^.RunMap.TotalClusters;
                if ofi^.AllocClusters > 0 then begin
                    ofi^.FatDirty := true;
                    ofi^.MetaDirty := true;
                end;
                LL_Free(tempRuns);
                FAT32EnsureCapacityForWrite := eOutOfMemory;
                exit;
            end;
            if ofi^.FirstCluster = 0 then
                ofi^.FirstCluster := tempRun^.StartCluster;
        end;
        LL_Free(tempRuns);
    end;

    ofi^.AllocClusters := ofi^.RunMap.TotalClusters;
    ofi^.FatDirty := true;
    ofi^.MetaDirty := true;
end;

function FAT32TransferAlloc(volume : PStorage_Volume) : PFATTransferCtx;
var
    volCtx : PFATVolumeCtx;
    ctx    : PFATTransferCtx;
    idx    : uint32;
begin
    FAT32TransferAlloc := nil;
    volCtx := FAT32GetVolumeCtx(volume);
    if volCtx = nil then exit;

    asm pushf; cli end;
    ctx := PFATTransferCtx(volCtx^.TransferFreeList);
    if ctx <> nil then
        volCtx^.TransferFreeList := pointer(ctx^.Next);
    asm popf end;

    if ctx = nil then exit;
    idx := (uint32(ctx) - uint32(volCtx^.TransferPoolBuf)) div sizeof(TFATTransferCtx);
    memset(uint32(ctx), 0, sizeof(TFATTransferCtx));
    ctx^.VolumeCtx := volCtx;
    ctx^.ScratchSector := puint32(uint32(volCtx^.TransferScratchBuf) + (idx * volCtx^.Info.BootRecord.sectorSize));
    ctx^.ScratchSize := volCtx^.Info.BootRecord.sectorSize;
    FAT32TransferAlloc := ctx;
end;

procedure FAT32TransferFree(ctx : PFATTransferCtx);
var
    volCtx : PFATVolumeCtx;
begin
    if ctx = nil then exit;
    volCtx := ctx^.VolumeCtx;
    if volCtx = nil then exit;
    asm pushf; cli end;
    ctx^.Next := PFATTransferCtx(volCtx^.TransferFreeList);
    volCtx^.TransferFreeList := pointer(ctx);
    asm popf end;
end;

function FAT32OpenFile(volume : PStorage_Volume; directory : pchar; fileName : pchar; var fileSize : uint32) : pointer;
var
    ofi           : PFATOpenFile;
    info          : PFATVolumeInfo;
    sectorBuf     : puint32;
    namePart      : pchar;
    extPart       : pchar;
    cleanName     : byteArray8;
    parentCluster : uint32;
begin
    fileSize := 0;
    FAT32OpenFile := nil;
    info := FAT32GetVolumeInfo(volume);
    if info = nil then exit;

    if not isValidFAT32Name(fileName) then
        exit;

    ofi := PFATOpenFile(kalloc(sizeof(TFATOpenFile)));
    if ofi = nil then exit;
    memset(uint32(ofi), 0, sizeof(TFATOpenFile));
    ofi^.Volume := volume;
    ofi^.VolumeInfo := info;
    ofi^.ScratchSize := info^.BootRecord.sectorSize;
    if ofi^.ScratchSize > 0 then begin
        ofi^.ScratchSector := puint32(kalloc(ofi^.ScratchSize));
        if ofi^.ScratchSector <> nil then
            memset(uint32(ofi^.ScratchSector), 0, ofi^.ScratchSize);
    end;

    splitFileNameParts(fileName, namePart, extPart);
    cleanName := cleanString(namePart);
    ofi^.CleanName := cleanName;
    ofi^.ExtPart := stringCopy(extPart);

    if not resolveDirectoryCluster(volume, info, directory, parentCluster) then begin
        if namePart <> nil then kfree(void(namePart));
        if extPart <> nil then kfree(void(extPart));
        FAT32CloseFile(ofi);
        exit;
    end;
    ofi^.DirLoc.ParentCluster := parentCluster;

    sectorBuf := puint32(kalloc(info^.BootRecord.sectorSize));
    if (sectorBuf = nil) and (info^.BootRecord.sectorSize > 0) then begin
        { OOM: cannot probe the directory — fail rather than silently treating an existing file as new }
        if namePart <> nil then kfree(void(namePart));
        if extPart <> nil then kfree(void(extPart));
        FAT32CloseFile(ofi);
        exit;
    end;
    if sectorBuf <> nil then begin
        if locateDirEntry(volume, info, parentCluster, cleanName, extPart, ofi^.DirLoc, sectorBuf) then begin
            ofi^.Exists := true;
            ofi^.FirstCluster := dirFirstCluster(@PDirectory(sectorBuf)[ofi^.DirLoc.EntryIdx]);
            ofi^.ByteSize := PDirectory(sectorBuf)[ofi^.DirLoc.EntryIdx].byteSize;
            if (ofi^.FirstCluster >= 2) and not buildRunMap(volume, info, ofi^.FirstCluster, ofi^.RunMap) then begin
                kfree(sectorBuf);
                if namePart <> nil then kfree(void(namePart));
                if extPart <> nil then kfree(void(extPart));
                FAT32CloseFile(ofi);
                exit;
            end;
            ofi^.AllocClusters := ofi^.RunMap.TotalClusters;
        end;
        kfree(sectorBuf);
    end;

    if namePart <> nil then kfree(void(namePart));
    if extPart <> nil then kfree(void(extPart));
    fileSize := ofi^.ByteSize;
    FAT32OpenFile := ofi;
end;

procedure FAT32CloseFile(ctx : pointer);
var
    ofi          : PFATOpenFile;
    rawDir       : PDirectory;
    keepClusters : uint32;
    walked       : uint32;
    ri           : uint32;
    tailCluster  : uint32;
    nextCluster  : uint32;
    runOff       : uint32;
    volCtx       : PFATVolumeCtx;
    oldCount     : uint32;
    isLastWriter : boolean;
begin
    if ctx = nil then exit;
    ofi := PFATOpenFile(ctx);

    { Determine whether this is the last writer for this file.
      Unregister unconditionally so the slot is freed even when we skip truncation. }
    isLastWriter := true;
    if ofi^.Registered then begin
        volCtx := FAT32GetVolumeCtx(ofi^.Volume);
        oldCount := fatUnregisterWriteHandle(volCtx, ofi);
        isLastWriter := (oldCount <= 1);
    end;

    { Truncate pre-allocated tail clusters back to ByteSize before flushing.
      Only done when this is the last writer — another open handle may still
      be expanding the file and relies on the pre-allocated chain. }
    if isLastWriter and (ofi^.VolumeInfo <> nil) and (ofi^.FatDirty) and
       (ofi^.Volume <> nil) and (ofi^.AllocClusters > 0) then begin
        keepClusters := fatClustersForBytes(ofi^.ByteSize, ofi^.VolumeInfo^.BytesPerCluster);
        if keepClusters < ofi^.AllocClusters then begin
            { Walk RunMap to find the last cluster we are keeping (1-based) }
            walked := 0;
            tailCluster := 0;
            nextCluster := 0;
            if keepClusters = 0 then begin
                { File has no data — free the entire chain }
                if ofi^.RunMap.Count > 0 then begin
                    nextCluster := ofi^.RunMap.Runs[0].StartCluster;
                    fatFreeClusterChain(ofi^.Volume, ofi^.VolumeInfo, nextCluster);
                end;
                ofi^.FirstCluster := 0;
            end else begin
                ri := 0;
                while ri < ofi^.RunMap.Count do begin
                    if walked + ofi^.RunMap.Runs[ri].ClusterCount >= keepClusters then begin
                        { The new tail is inside this run }
                        runOff := keepClusters - walked - 1;
                        tailCluster := ofi^.RunMap.Runs[ri].StartCluster + runOff;
                        { First cluster to free is the one after the new tail }
                        if runOff + 1 < ofi^.RunMap.Runs[ri].ClusterCount then
                            nextCluster := ofi^.RunMap.Runs[ri].StartCluster + runOff + 1
                        else if ri + 1 < ofi^.RunMap.Count then
                            nextCluster := ofi^.RunMap.Runs[ri + 1].StartCluster
                        else
                            nextCluster := 0;
                        break;
                    end;
                    walked := walked + ofi^.RunMap.Runs[ri].ClusterCount;
                    ri := ri + 1;
                end;
                if tailCluster >= 2 then
                    writeFat(ofi^.Volume, tailCluster, $0FFFFFF8, @ofi^.VolumeInfo^.BootRecord);
                if nextCluster >= 2 then
                    fatFreeClusterChain(ofi^.Volume, ofi^.VolumeInfo, nextCluster);
            end;
            ofi^.AllocClusters := keepClusters;
            ofi^.FatDirty := true;
        end;
    end;

    if ofi^.FatDirty and (ofi^.Volume <> nil) then
        FAT32Flush(ofi^.Volume);

    { Use the already-allocated ScratchSector (same size as a disk sector) to avoid
      a kalloc in close; an allocation failure here would silently lose metadata. }
    if ofi^.MetaDirty and ofi^.DirLoc.Valid and (ofi^.ScratchSector <> nil) then begin
        driver.storage.mgr.storage_read(ofi^.Volume^.device, ofi^.DirLoc.SectorLBA, 1, ofi^.ScratchSector);
        rawDir := @PDirectory(ofi^.ScratchSector)[ofi^.DirLoc.EntryIdx];
        rawDir^.byteSize := ofi^.ByteSize;
        setDirFirstCluster(rawDir, ofi^.FirstCluster);
        driver.storage.mgr.storage_write(ofi^.Volume^.device, ofi^.DirLoc.SectorLBA, 1, ofi^.ScratchSector);
    end;

    runMapFree(ofi^.RunMap);
    if ofi^.ExtPart <> nil then
        kfree(void(ofi^.ExtPart));
    if ofi^.ScratchSector <> nil then
        kfree(ofi^.ScratchSector);
    kfree(void(ofi));
end;

procedure fatFreeGenericEntries(entries : PLinkedListBase);
var
    i     : uint32;
    entry : PDirectory_Entry;
begin
    if entries = nil then exit;
    for i := 0 to LL_Size(entries) - 1 do begin
        entry := PDirectory_Entry(LL_Get(entries, i));
        if (entry <> nil) and (entry^.fileName <> nil) then
            kfree(void(entry^.fileName));
    end;
    LL_Free(entries);
end;

procedure fatFreeClusterChain(volume : PStorage_Volume; info : PFATVolumeInfo; startCluster : uint32);
var
    currentCluster : uint32;
    nextCluster    : uint32;
    runStart       : uint32;
    runCount       : uint32;
    iterCount      : uint32;
begin
    if (volume = nil) or (info = nil) or (startCluster < 2) then exit;
    currentCluster := startCluster;
    runStart := 0;
    runCount := 0;
    iterCount := 0;

    while true do begin
        if (currentCluster < 2) or (currentCluster >= info^.MaxCluster) then
            break;
        if iterCount >= info^.MaxCluster then
            break;

        nextCluster := readFat(volume, currentCluster, @info^.BootRecord);
        writeFat(volume, currentCluster, 0, @info^.BootRecord);

        if runCount = 0 then begin
            runStart := currentCluster;
            runCount := 1;
        end else if currentCluster = (runStart + runCount) then
            runCount := runCount + 1
        else begin
            fatRememberAllocHint(volume, runStart, runCount);
            runStart := currentCluster;
            runCount := 1;
        end;

        iterCount := iterCount + 1;
        if isEndOfChain(nextCluster) or isBadCluster(nextCluster) or (nextCluster = 0) then
            break;
        currentCluster := nextCluster;
    end;

    if runCount > 0 then
        fatRememberAllocHint(volume, runStart, runCount);
end;

function fatDirectoryHasChildren(volume : PStorage_Volume; info : PFATVolumeInfo; firstCluster : uint32) : boolean;
var
    buffer       : puint32;
    currentCluster : uint32;
    nextCluster  : uint32;
    clusterLBA   : uint32;
    ds           : uint32;
    idx          : uint32;
    iterCount    : uint32;
    entriesPerSec: uint32;
    dir          : PDirectory;
begin
    fatDirectoryHasChildren := false;
    if (volume = nil) or (info = nil) or (firstCluster < 2) then exit;

    buffer := puint32(kalloc(info^.BootRecord.sectorSize));
    if buffer = nil then begin
        fatDirectoryHasChildren := true;
        exit;
    end;

    entriesPerSec := info^.BootRecord.sectorSize div sizeof(TDirectory);
    currentCluster := firstCluster;
    iterCount := 0;

    while currentCluster >= 2 do begin
        if (currentCluster >= info^.MaxCluster) or (iterCount >= info^.MaxCluster) then
            break;
        clusterLBA := FAT32ClusterToLBA(info, currentCluster);
        for ds := 0 to info^.BootRecord.spc - 1 do begin
            driver.storage.mgr.storage_read(volume^.device, clusterLBA + ds, 1, buffer);
            for idx := 0 to entriesPerSec - 1 do begin
                dir := @PDirectory(buffer)[idx];
                if dir^.fileName[0] = char(0) then begin
                    kfree(buffer);
                    exit;
                end;
                if dir^.fileName[0] = char($E5) then
                    continue;
                if dir^.attributes = $0F then
                    continue;
                if fatIsDotEntry(dir) then
                    continue;
                fatDirectoryHasChildren := true;
                kfree(buffer);
                exit;
            end;
        end;
        nextCluster := readFat(volume, currentCluster, @info^.BootRecord);
        if isEndOfChain(nextCluster) or isBadCluster(nextCluster) or (nextCluster = 0) then
            break;
        currentCluster := nextCluster;
        iterCount := iterCount + 1;
    end;

    kfree(buffer);
end;

function fatResolveLeafPath(volume : PStorage_Volume; info : PFATVolumeInfo; fullPath : pchar;
    var parentDir : pchar; var leafName : pchar; var parentCluster : uint32; var statusOut : TError) : boolean;
begin
    fatResolveLeafPath := false;
    parentDir := nil;
    leafName := nil;
    parentCluster := 0;
    statusOut := eDirectoryDoesNotExist;

    splitPathParts(fullPath, parentDir, leafName);
    if (leafName = nil) or (leafName[0] = char(0)) then begin
        statusOut := eInvalidFileName;
        exit;
    end;

    if not resolveDirectoryCluster(volume, info, parentDir, parentCluster) then begin
        statusOut := eDirectoryDoesNotExist;
        exit;
    end;

    fatResolveLeafPath := true;
    statusOut := eNone;
end;

function fatInitDirectoryCluster(volume : PStorage_Volume; info : PFATVolumeInfo; cluster : uint32; parentCluster : uint32) : boolean;
var
    buffer   : puint32;
    ds       : uint32;
    clusterLBA : uint32;
    dir      : PDirectory;
begin
    fatInitDirectoryCluster := false;
    if (volume = nil) or (info = nil) or (cluster < 2) then exit;
    buffer := puint32(kalloc(info^.BootRecord.sectorSize));
    if buffer = nil then exit;
    clusterLBA := FAT32ClusterToLBA(info, cluster);

    for ds := 0 to info^.BootRecord.spc - 1 do begin
        memset(uint32(buffer), 0, info^.BootRecord.sectorSize);
        if ds = 0 then begin
            dir := @PDirectory(buffer)[0];
            dir^.fileName[0] := '.';
            dir^.fileName[1] := ' ';
            dir^.fileName[2] := ' ';
            dir^.fileName[3] := ' ';
            dir^.fileName[4] := ' ';
            dir^.fileName[5] := ' ';
            dir^.fileName[6] := ' ';
            dir^.fileName[7] := ' ';
            dir^.attributes := $10;
            setDirFirstCluster(dir, cluster);

            dir := @PDirectory(buffer)[1];
            dir^.fileName[0] := '.';
            dir^.fileName[1] := '.';
            dir^.fileName[2] := ' ';
            dir^.fileName[3] := ' ';
            dir^.fileName[4] := ' ';
            dir^.fileName[5] := ' ';
            dir^.fileName[6] := ' ';
            dir^.fileName[7] := ' ';
            dir^.attributes := $10;
            setDirFirstCluster(dir, parentCluster);
        end;
        driver.storage.mgr.storage_write(volume^.device, clusterLBA + ds, 1, buffer);
    end;

    kfree(buffer);
    fatInitDirectoryCluster := true;
end;

function FAT32ReadDirectory(volume : PStorage_Volume; directory : pchar; statusOut : puint32) : PLinkedListBase;
var
    info          : PFATVolumeInfo;
    entries       : PLinkedListBase;
    buffer        : puint32;
    parentCluster : uint32;
    currentCluster: uint32;
    nextCluster   : uint32;
    clusterLBA    : uint32;
    entriesPerSec : uint32;
    iterCount     : uint32;
    ds            : uint32;
    idx           : uint32;
    rawDir        : PDirectory;
    outEntry      : PDirectory_Entry;
    slot          : puint32;
    stopScan      : boolean;
begin
    FAT32ReadDirectory := nil;
    if statusOut <> nil then statusOut^ := ord(eUnknown);
    info := FAT32GetVolumeInfo(volume);
    if info = nil then exit;
    if not resolveDirectoryCluster(volume, info, directory, parentCluster) then begin
        if statusOut <> nil then statusOut^ := ord(eDirectoryDoesNotExist);
        exit;
    end;

    entries := LL_New(sizeof(TDirectory_Entry));
    if entries = nil then begin
        if statusOut <> nil then statusOut^ := ord(eOutOfMemory);
        exit;
    end;

    buffer := puint32(kalloc(info^.BootRecord.sectorSize));
    if buffer = nil then begin
        LL_Free(entries);
        if statusOut <> nil then statusOut^ := ord(eOutOfMemory);
        exit;
    end;

    currentCluster := parentCluster;
    entriesPerSec := info^.BootRecord.sectorSize div sizeof(TDirectory);
    iterCount := 0;
    stopScan := false;

    while (currentCluster >= 2) and not stopScan do begin
        if (currentCluster >= info^.MaxCluster) or (iterCount >= info^.MaxCluster) then begin
            fatFreeGenericEntries(entries);
            kfree(buffer);
            if statusOut <> nil then statusOut^ := ord(eCorruptFilesystem);
            exit;
        end;

        clusterLBA := FAT32ClusterToLBA(info, currentCluster);
        for ds := 0 to info^.BootRecord.spc - 1 do begin
            driver.storage.mgr.storage_read(volume^.device, clusterLBA + ds, 1, buffer);
            for idx := 0 to entriesPerSec - 1 do begin
                rawDir := @PDirectory(buffer)[idx];
                if rawDir^.fileName[0] = char(0) then begin
                    stopScan := true;
                    break;
                end;
                if rawDir^.fileName[0] = char($E5) then
                    continue;
                if rawDir^.attributes = $0F then
                    continue;
                if (rawDir^.attributes and $08) = $08 then
                    continue;

                slot := LL_Add(entries);
                if slot = nil then begin
                    fatFreeGenericEntries(entries);
                    kfree(buffer);
                    if statusOut <> nil then statusOut^ := ord(eOutOfMemory);
                    exit;
                end;
                outEntry := PDirectory_Entry(slot);
                memset(uint32(outEntry), 0, sizeof(TDirectory_Entry));
                outEntry^.fileName := fatEntryName(rawDir);
                if outEntry^.fileName = nil then begin
                    fatFreeGenericEntries(entries);
                    kfree(buffer);
                    if statusOut <> nil then statusOut^ := ord(eOutOfMemory);
                    exit;
                end;
                if (rawDir^.attributes and $10) = $10 then
                    outEntry^.entryType := directoryEntry
                else
                    outEntry^.entryType := fileEntry;
                outEntry^.fileSize := rawDir^.byteSize;
                outEntry^.modifiedDate := rawDir^.modifiedDate;
                outEntry^.modifiedTime := rawDir^.modifiedTime;
                outEntry^.attributes := rawDir^.attributes;
            end;
            if stopScan then
                break;
        end;

        nextCluster := readFat(volume, currentCluster, @info^.BootRecord);
        if isEndOfChain(nextCluster) or isBadCluster(nextCluster) or (nextCluster = 0) then
            break;
        currentCluster := nextCluster;
        iterCount := iterCount + 1;
    end;

    kfree(buffer);
    if statusOut <> nil then statusOut^ := ord(eNone);
    FAT32ReadDirectory := entries;
end;

procedure FAT32CreateDirectory(volume : PStorage_Volume; directory : pchar; dirName : pchar; attributes : uint32; statusOut : puint32);
var
    info          : PFATVolumeInfo;
    parentCluster : uint32;
    namePart      : pchar;
    extPart       : pchar;
    cleanName     : byteArray8;
    sectorBuf     : puint32;
    loc           : TFATDirEntryLocation;
    rawDir        : PDirectory;
    cluster       : uint32;
    lastTail      : uint32;
    tempRuns      : PLinkedListBase;
    tempRun       : PFATTempRun;
begin
    if statusOut <> nil then statusOut^ := ord(eUnknown);
    info := FAT32GetVolumeInfo(volume);
    if info = nil then exit;

    if (dirName = nil) or not isValidFAT32Name(dirName) then begin
        if statusOut <> nil then statusOut^ := ord(eInvalidFileName);
        exit;
    end;

    if not resolveDirectoryCluster(volume, info, directory, parentCluster) then begin
        if statusOut <> nil then statusOut^ := ord(eDirectoryDoesNotExist);
        exit;
    end;

    splitFileNameParts(dirName, namePart, extPart);
    cleanName := cleanString(namePart);

    sectorBuf := puint32(kalloc(info^.BootRecord.sectorSize));
    if sectorBuf = nil then begin
        if statusOut <> nil then statusOut^ := ord(eOutOfMemory);
        if namePart <> nil then kfree(void(namePart));
        if extPart <> nil then kfree(void(extPart));
        exit;
    end;

    if locateDirEntry(volume, info, parentCluster, cleanName, extPart, loc, sectorBuf) then begin
        if statusOut <> nil then statusOut^ := ord(eDirectoryAlreadyExists);
        kfree(sectorBuf);
        if namePart <> nil then kfree(void(namePart));
        if extPart <> nil then kfree(void(extPart));
        exit;
    end;

    if not locateFreeDirEntry(volume, info, parentCluster, loc, sectorBuf) then begin
        if statusOut <> nil then statusOut^ := ord(eDirectoryFull);
        kfree(sectorBuf);
        if namePart <> nil then kfree(void(namePart));
        if extPart <> nil then kfree(void(extPart));
        exit;
    end;

    cluster := 0;
    if fatFindContiguousFreeRange(volume, info, 1, cluster) then
        fatLinkContiguousRange(volume, info, 0, cluster, 1, lastTail)
    else begin
        tempRuns := findFreeClusterRuns(volume, info, 1);
        if (tempRuns = nil) or (LL_Size(tempRuns) = 0) then begin
            if tempRuns <> nil then LL_Free(tempRuns);
            if statusOut <> nil then statusOut^ := ord(eDiskFull);
            kfree(sectorBuf);
            if namePart <> nil then kfree(void(namePart));
            if extPart <> nil then kfree(void(extPart));
            exit;
        end;
        tempRun := PFATTempRun(LL_Get(tempRuns, 0));
        cluster := tempRun^.StartCluster;
        fatLinkContiguousRange(volume, info, 0, cluster, 1, lastTail);
        LL_Free(tempRuns);
    end;

    if not fatInitDirectoryCluster(volume, info, cluster, parentCluster) then begin
        { OOM in fatInitDirectoryCluster: free the allocated cluster and bail out }
        fatFreeClusterChain(volume, info, cluster);
        if statusOut <> nil then statusOut^ := ord(eOutOfMemory);
        kfree(sectorBuf);
        if namePart <> nil then kfree(void(namePart));
        if extPart <> nil then kfree(void(extPart));
        exit;
    end;

    rawDir := @PDirectory(sectorBuf)[loc.EntryIdx];
    memset(uint32(rawDir), 0, sizeof(TDirectory));
    rawDir^.fileName := cleanName;
    rawDir^.attributes := attributes;
    fillFatExt(rawDir^.fileExtension, extPart);
    rawDir^.byteSize := 0;
    setDirFirstCluster(rawDir, cluster);
    fatRememberFreeEntryFromBuffer(volume, parentCluster, loc.SectorLBA, sectorBuf,
        info^.BootRecord.sectorSize div sizeof(TDirectory));
    driver.storage.mgr.storage_write(volume^.device, loc.SectorLBA, 1, sectorBuf);
    FAT32Flush(volume);

    if statusOut <> nil then statusOut^ := ord(eNone);
    kfree(sectorBuf);
    if namePart <> nil then kfree(void(namePart));
    if extPart <> nil then kfree(void(extPart));
end;

procedure FAT32DeleteFile(volume : PStorage_Volume; filePath : pchar; statusOut : puint32);
var
    info          : PFATVolumeInfo;
    parentDir     : pchar = nil;
    fileName      : pchar = nil;
    namePart      : pchar = nil;
    extPart       : pchar = nil;
    parentCluster : uint32;
    err           : TError;
    cleanName     : byteArray8;
    sectorBuf     : puint32 = nil;
    loc           : TFATDirEntryLocation;
    rawDir        : PDirectory;
    firstCluster  : uint32;
    resultErr     : TError;
begin
    resultErr := eUnknown;
    if statusOut <> nil then statusOut^ := ord(resultErr);
    info := FAT32GetVolumeInfo(volume);
    if info = nil then begin
        if statusOut <> nil then statusOut^ := ord(resultErr);
        exit;
    end;

    if not fatResolveLeafPath(volume, info, filePath, parentDir, fileName, parentCluster, err) then begin
        resultErr := err;
    end else begin
        splitFileNameParts(fileName, namePart, extPart);
        cleanName := cleanString(namePart);
        sectorBuf := puint32(kalloc(info^.BootRecord.sectorSize));
        if sectorBuf = nil then
            resultErr := eOutOfMemory
        else if not locateDirEntry(volume, info, parentCluster, cleanName, extPart, loc, sectorBuf) then
            resultErr := eFileDoesNotExist
        else begin
            rawDir := @PDirectory(sectorBuf)[loc.EntryIdx];
            if (rawDir^.attributes and $10) = $10 then
                resultErr := eNotADirectory
            else begin
                firstCluster := dirFirstCluster(rawDir);
                if firstCluster >= 2 then
                    fatFreeClusterChain(volume, info, firstCluster);
                rawDir^.fileName[0] := char($E5);
                fatRememberDirHint(volume, parentCluster, loc.SectorLBA, loc.EntryIdx);
                driver.storage.mgr.storage_write(volume^.device, loc.SectorLBA, 1, sectorBuf);
                if firstCluster >= 2 then
                    FAT32Flush(volume);
                resultErr := eNone;
            end;
        end;
    end;
    if sectorBuf <> nil then kfree(sectorBuf);
    if parentDir <> nil then kfree(void(parentDir));
    if fileName <> nil then kfree(void(fileName));
    if namePart <> nil then kfree(void(namePart));
    if extPart <> nil then kfree(void(extPart));
    if statusOut <> nil then statusOut^ := ord(resultErr);
end;

procedure FAT32DeleteDir(volume : PStorage_Volume; path : pchar; statusOut : puint32);
var
    info          : PFATVolumeInfo;
    parentDir     : pchar = nil;
    dirName       : pchar = nil;
    namePart      : pchar = nil;
    extPart       : pchar = nil;
    parentCluster : uint32;
    err           : TError;
    cleanName     : byteArray8;
    sectorBuf     : puint32 = nil;
    loc           : TFATDirEntryLocation;
    rawDir        : PDirectory;
    firstCluster  : uint32;
    resultErr     : TError;
begin
    resultErr := eUnknown;
    if statusOut <> nil then statusOut^ := ord(resultErr);
    info := FAT32GetVolumeInfo(volume);
    if info = nil then begin
        if statusOut <> nil then statusOut^ := ord(resultErr);
        exit;
    end;

    if not fatResolveLeafPath(volume, info, path, parentDir, dirName, parentCluster, err) then begin
        resultErr := err;
    end else begin
        splitFileNameParts(dirName, namePart, extPart);
        cleanName := cleanString(namePart);
        sectorBuf := puint32(kalloc(info^.BootRecord.sectorSize));
        if sectorBuf = nil then
            resultErr := eOutOfMemory
        else if not locateDirEntry(volume, info, parentCluster, cleanName, extPart, loc, sectorBuf) then
            resultErr := eDirectoryDoesNotExist
        else begin
            rawDir := @PDirectory(sectorBuf)[loc.EntryIdx];
            if (rawDir^.attributes and $10) <> $10 then
                resultErr := eNotADirectory
            else begin
                firstCluster := dirFirstCluster(rawDir);
                if fatDirectoryHasChildren(volume, info, firstCluster) then
                    resultErr := eDirectoryNotEmpty
                else begin
                    if firstCluster >= 2 then
                        fatFreeClusterChain(volume, info, firstCluster);
                    rawDir^.fileName[0] := char($E5);
                    fatRememberDirHint(volume, parentCluster, loc.SectorLBA, loc.EntryIdx);
                    driver.storage.mgr.storage_write(volume^.device, loc.SectorLBA, 1, sectorBuf);
                    if firstCluster >= 2 then
                        FAT32Flush(volume);
                    resultErr := eNone;
                end;
            end;
        end;
    end;
    if sectorBuf <> nil then kfree(sectorBuf);
    if parentDir <> nil then kfree(void(parentDir));
    if dirName <> nil then kfree(void(dirName));
    if namePart <> nil then kfree(void(namePart));
    if extPart <> nil then kfree(void(extPart));
    if statusOut <> nil then statusOut^ := ord(resultErr);
end;

procedure FAT32RenameFile(volume : PStorage_Volume; filePath : pchar; newName : pchar; statusOut : puint32);
var
    info          : PFATVolumeInfo;
    parentDir     : pchar = nil;
    fileName      : pchar = nil;
    namePart      : pchar = nil;
    extPart       : pchar = nil;
    newNamePart   : pchar = nil;
    newExtPart    : pchar = nil;
    parentCluster : uint32;
    err           : TError;
    cleanName     : byteArray8;
    newCleanName  : byteArray8;
    sectorBuf     : puint32 = nil;
    loc           : TFATDirEntryLocation;
    rawDir        : PDirectory;
    resultErr     : TError;
begin
    resultErr := eUnknown;
    if statusOut <> nil then statusOut^ := ord(resultErr);
    info := FAT32GetVolumeInfo(volume);
    if info = nil then begin
        if statusOut <> nil then statusOut^ := ord(resultErr);
        exit;
    end;

    if (newName = nil) or not isValidFAT32Name(newName) then begin
        if statusOut <> nil then statusOut^ := ord(eInvalidFileName);
        exit;
    end;

    if not fatResolveLeafPath(volume, info, filePath, parentDir, fileName, parentCluster, err) then begin
        resultErr := err;
    end else begin
        splitFileNameParts(fileName, namePart, extPart);
        cleanName := cleanString(namePart);
        sectorBuf := puint32(kalloc(info^.BootRecord.sectorSize));
        if sectorBuf = nil then
            resultErr := eOutOfMemory
        else if not locateDirEntry(volume, info, parentCluster, cleanName, extPart, loc, sectorBuf) then
            resultErr := eFileDoesNotExist
        else begin
            rawDir := @PDirectory(sectorBuf)[loc.EntryIdx];
            splitFileNameParts(newName, newNamePart, newExtPart);
            newCleanName := cleanString(newNamePart);
            rawDir^.fileName := newCleanName;
            fillFatExt(rawDir^.fileExtension, newExtPart);
            driver.storage.mgr.storage_write(volume^.device, loc.SectorLBA, 1, sectorBuf);
            resultErr := eNone;
        end;
    end;
    if sectorBuf <> nil then kfree(sectorBuf);
    if parentDir <> nil then kfree(void(parentDir));
    if fileName <> nil then kfree(void(fileName));
    if namePart <> nil then kfree(void(namePart));
    if extPart <> nil then kfree(void(extPart));
    if newNamePart <> nil then kfree(void(newNamePart));
    if newExtPart <> nil then kfree(void(newExtPart));
    if statusOut <> nil then statusOut^ := ord(resultErr);
end;

function FAT32GetFileSize(volume : PStorage_Volume; directory : pchar; fileName : pchar) : uint32;
var
    ctx : pointer;
begin
    FAT32GetFileSize := 0;
    ctx := FAT32OpenFile(volume, directory, fileName, FAT32GetFileSize);
    if ctx <> nil then
        FAT32CloseFile(ctx);
end;

function FAT32GetReadLimit(ofi : PFATOpenFile; offset : uint32; byteCount : uint32) : uint32;
begin
    FAT32GetReadLimit := 0;
    if (ofi = nil) or (offset >= ofi^.ByteSize) then exit;
    FAT32GetReadLimit := ofi^.ByteSize - offset;
    if byteCount < FAT32GetReadLimit then
        FAT32GetReadLimit := byteCount;
end;

end.
