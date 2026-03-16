unit driver.storage.fs.fat32.transfer;

interface

uses
    driver.storage.types;

function FAT32ReadFileAtOffset(volume : PStorage_Volume; directory : pchar; fileName : pchar;
    offset : uint32; buffer : puint32; byteCount : uint32; ctx : pointer) : uint32;
function FAT32WriteFileAtOffset(volume : PStorage_Volume; directory : pchar; fileName : pchar;
    offset : uint32; buffer : puint32; byteCount : uint32; ctx : pointer) : uint32;
procedure FAT32ReadFileAtOffsetAsync(volume : PStorage_Volume; directory : pchar; fileName : pchar;
    offset : uint32; buffer : puint32; byteCount : uint32; ctx : pointer; bytesRead : puint32;
    callback : TIOCallback; callbackData : pointer);
procedure FAT32WriteFileAtOffsetAsync(volume : PStorage_Volume; directory : pchar; fileName : pchar;
    offset : uint32; buffer : puint32; byteCount : uint32; ctx : pointer; bytesWritten : puint32;
    callback : TIOCallback; callbackData : pointer);

implementation

uses
    driver.storage.mgr,
    core.util, arch.x86.util,
    memory.heap,
    driver.storage.fs.fat32.types,
    driver.storage.fs.fat32.core;

procedure noteWriteProgress(ofi : PFATOpenFile; completedEnd : uint32);
begin
    if ofi = nil then exit;
    if (ofi^.FirstCluster = 0) and (ofi^.RunMap.Count > 0) then
        ofi^.FirstCluster := ofi^.RunMap.Runs[0].StartCluster;
    if completedEnd > ofi^.ByteSize then begin
        ofi^.ByteSize := completedEnd;
        ofi^.MetaDirty := true;
    end;
end;

function transferSync(ofi : PFATOpenFile; buffer : puint32; offset : uint32; byteCount : uint32;
    mode : TFATTransferMode; scratch : puint32; scratchSize : uint32) : uint32;
var
    remaining        : uint32;
    bytesDone        : uint32;
    runIdx           : uint32;
    runFileCluster   : uint32;
    startCluster     : uint32;
    clusterOffset    : uint32;
    availableBytes   : uint32;
    hintValid        : boolean;
    hintRunIdx       : uint32;
    hintFileCluster  : uint32;
    bytesPerCluster  : uint32;
    sectorSize       : uint32;
    currentOffset    : uint32;
    runByteOffset    : uint32;
    sectorOffset     : uint32;
    chunkBytes       : uint32;
    chunkSectors     : uint32;
    sectorLBA        : uint32;
begin
    transferSync := 0;
    if (ofi = nil) or (buffer = nil) or (byteCount = 0) then exit;

    remaining := byteCount;
    bytesDone := 0;
    hintValid := false;
    hintRunIdx := 0;
    hintFileCluster := 0;
    bytesPerCluster := ofi^.VolumeInfo^.BytesPerCluster;
    sectorSize := ofi^.VolumeInfo^.BootRecord.sectorSize;

    while remaining > 0 do begin
        currentOffset := offset + bytesDone;
        if not FAT32FindRunForOffset(ofi, currentOffset, hintValid, hintRunIdx, hintFileCluster,
            runIdx, runFileCluster, startCluster, clusterOffset, availableBytes) then
            break;

        hintValid := true;
        hintRunIdx := runIdx;
        hintFileCluster := runFileCluster;

        runByteOffset := currentOffset - (runFileCluster * bytesPerCluster);
        sectorOffset := runByteOffset mod sectorSize;
        sectorLBA := FAT32ClusterToLBA(ofi^.VolumeInfo, startCluster) + (runByteOffset div sectorSize);

        if (sectorOffset <> 0) or (remaining < sectorSize) then begin
            if scratch = nil then break;
            chunkBytes := sectorSize - sectorOffset;
            if chunkBytes > remaining then
                chunkBytes := remaining;
            driver.storage.mgr.storage_read(ofi^.Volume^.device, sectorLBA, 1, scratch);
            if mode = ftmRead then
                memcpy(uint32(scratch) + sectorOffset, uint32(buffer) + bytesDone, chunkBytes)
            else begin
                memcpy(uint32(buffer) + bytesDone, uint32(scratch) + sectorOffset, chunkBytes);
                driver.storage.mgr.storage_write(ofi^.Volume^.device, sectorLBA, 1, scratch);
            end;
        end else begin
            chunkBytes := remaining;
            if chunkBytes > availableBytes then
                chunkBytes := availableBytes;
            chunkBytes := (chunkBytes div sectorSize) * sectorSize;
            if chunkBytes = 0 then break;
            chunkSectors := chunkBytes div sectorSize;
            if chunkSectors > FAT_MAX_IO_SECTORS then
                chunkSectors := FAT_MAX_IO_SECTORS;
            chunkBytes := chunkSectors * sectorSize;
            if mode = ftmRead then
                driver.storage.mgr.storage_read(ofi^.Volume^.device, sectorLBA, chunkSectors,
                    puint32(uint32(buffer) + bytesDone))
            else
                driver.storage.mgr.storage_write(ofi^.Volume^.device, sectorLBA, chunkSectors,
                    puint32(uint32(buffer) + bytesDone));
        end;

        bytesDone := bytesDone + chunkBytes;
        remaining := remaining - chunkBytes;
        if mode = ftmWrite then
            noteWriteProgress(ofi, offset + bytesDone);
    end;

    transferSync := bytesDone;
end;

procedure asyncComplete(ctx : PFATTransferCtx; error : TError);
begin
    if ctx = nil then exit;
    if ctx^.BytesOut <> nil then
        ctx^.BytesOut^ := ctx^.BytesDone;
    if ctx^.Callback <> nil then
        ctx^.Callback(error, ctx^.CallbackData);
    FAT32TransferFree(ctx);
end;

procedure asyncContinue(ctx : PFATTransferCtx); forward;

procedure asyncStep(error : TError; userdata : pointer);
var
    ctx : PFATTransferCtx;
begin
    ctx := PFATTransferCtx(userdata);
    if ctx = nil then exit;

    if error <> eNone then begin
        asyncComplete(ctx, error);
        exit;
    end;

    case ctx^.Phase of
        ftpAwaitDirect: begin
            ctx^.BytesDone := ctx^.BytesDone + ctx^.PendingAdvanceBytes;
            if ctx^.Mode = ftmWrite then
                noteWriteProgress(ctx^.OpenFile, ctx^.Offset + ctx^.BytesDone);
            asyncContinue(ctx);
        end;
        ftpAwaitScratchRead: begin
            if ctx^.Mode = ftmRead then begin
                memcpy(uint32(ctx^.ScratchSector) + ctx^.PendingScratchOffset,
                    uint32(ctx^.Buffer) + ctx^.PendingBufferOffset, ctx^.PendingScratchBytes);
                ctx^.BytesDone := ctx^.BytesDone + ctx^.PendingScratchBytes;
                asyncContinue(ctx);
            end else begin
                memcpy(uint32(ctx^.Buffer) + ctx^.PendingBufferOffset,
                    uint32(ctx^.ScratchSector) + ctx^.PendingScratchOffset, ctx^.PendingScratchBytes);
                ctx^.Phase := ftpAwaitScratchWrite;
                if driver.storage.mgr.storage_write_async(
                    ctx^.Volume^.device, ctx^.PendingLBA, 1, ctx^.ScratchSector, @asyncStep, ctx) <> eNone then
                    asyncComplete(ctx, eIOError);
            end;
        end;
        ftpAwaitScratchWrite: begin
            ctx^.BytesDone := ctx^.BytesDone + ctx^.PendingScratchBytes;
            noteWriteProgress(ctx^.OpenFile, ctx^.Offset + ctx^.BytesDone);
            asyncContinue(ctx);
        end;
    else
        asyncComplete(ctx, eUnknown);
    end;
end;

procedure asyncContinue(ctx : PFATTransferCtx);
var
    runIdx          : uint32;
    runFileCluster  : uint32;
    startCluster    : uint32;
    clusterOffset   : uint32;
    availableBytes  : uint32;
    bytesPerCluster : uint32;
    sectorSize      : uint32;
    currentOffset   : uint32;
    remaining       : uint32;
    runByteOffset   : uint32;
    sectorOffset    : uint32;
    chunkBytes      : uint32;
    chunkSectors    : uint32;
    err             : TError;
begin
    if ctx = nil then exit;
    if ctx^.BytesDone >= ctx^.ByteCount then begin
        asyncComplete(ctx, eNone);
        exit;
    end;

    bytesPerCluster := ctx^.OpenFile^.VolumeInfo^.BytesPerCluster;
    sectorSize := ctx^.OpenFile^.VolumeInfo^.BootRecord.sectorSize;
    currentOffset := ctx^.Offset + ctx^.BytesDone;
    remaining := ctx^.ByteCount - ctx^.BytesDone;

    if not FAT32FindRunForOffset(ctx^.OpenFile, currentOffset, ctx^.RunHintValid, ctx^.RunHintIndex,
        ctx^.RunHintFileCluster, runIdx, runFileCluster, startCluster, clusterOffset, availableBytes) then begin
        asyncComplete(ctx, eCorruptFilesystem);
        exit;
    end;

    ctx^.RunHintValid := true;
    ctx^.RunHintIndex := runIdx;
    ctx^.RunHintFileCluster := runFileCluster;

    runByteOffset := currentOffset - (runFileCluster * bytesPerCluster);
    sectorOffset := runByteOffset mod sectorSize;
    ctx^.PendingLBA := FAT32ClusterToLBA(ctx^.OpenFile^.VolumeInfo, startCluster) + (runByteOffset div sectorSize);
    ctx^.PendingBufferOffset := ctx^.BytesDone;

    if (sectorOffset <> 0) or (remaining < sectorSize) then begin
        chunkBytes := sectorSize - sectorOffset;
        if chunkBytes > remaining then
            chunkBytes := remaining;
        ctx^.PendingScratchOffset := sectorOffset;
        ctx^.PendingScratchBytes := chunkBytes;
        ctx^.Phase := ftpAwaitScratchRead;
        err := driver.storage.mgr.storage_read_async(ctx^.Volume^.device, ctx^.PendingLBA, 1,
            ctx^.ScratchSector, @asyncStep, ctx);
        if err <> eNone then
            asyncComplete(ctx, err);
        exit;
    end;

    chunkBytes := remaining;
    if chunkBytes > availableBytes then
        chunkBytes := availableBytes;
    chunkBytes := (chunkBytes div sectorSize) * sectorSize;
    if chunkBytes = 0 then begin
        asyncComplete(ctx, eInvalidArgument);
        exit;
    end;
    chunkSectors := chunkBytes div sectorSize;
    if chunkSectors > FAT_MAX_IO_SECTORS then
        chunkSectors := FAT_MAX_IO_SECTORS;
    ctx^.PendingAdvanceBytes := chunkSectors * sectorSize;
    ctx^.PendingSectors := chunkSectors;
    ctx^.Phase := ftpAwaitDirect;

    if ctx^.Mode = ftmRead then
        err := driver.storage.mgr.storage_read_async(ctx^.Volume^.device, ctx^.PendingLBA, chunkSectors,
            puint32(uint32(ctx^.Buffer) + ctx^.PendingBufferOffset), @asyncStep, ctx)
    else
        err := driver.storage.mgr.storage_write_async(ctx^.Volume^.device, ctx^.PendingLBA, chunkSectors,
            puint32(uint32(ctx^.Buffer) + ctx^.PendingBufferOffset), @asyncStep, ctx);
    if err <> eNone then
        asyncComplete(ctx, err);
end;

function FAT32ReadFileAtOffset(volume : PStorage_Volume; directory : pchar; fileName : pchar;
    offset : uint32; buffer : puint32; byteCount : uint32; ctx : pointer) : uint32;
var
    ofi       : PFATOpenFile;
    tempCtx   : pointer;
    fileSize  : uint32;
    readLimit : uint32;
begin
    FAT32ReadFileAtOffset := 0;
    if (buffer = nil) or (byteCount = 0) then exit;

    ofi := PFATOpenFile(ctx);
    tempCtx := nil;
    if ofi = nil then begin
        tempCtx := FAT32OpenFile(volume, directory, fileName, fileSize);
        ofi := PFATOpenFile(tempCtx);
    end;
    if ofi = nil then exit;

    readLimit := FAT32GetReadLimit(ofi, offset, byteCount);
    if readLimit > 0 then
        FAT32ReadFileAtOffset := transferSync(ofi, buffer, offset, readLimit, ftmRead,
            ofi^.ScratchSector, ofi^.ScratchSize);

    if tempCtx <> nil then
        FAT32CloseFile(tempCtx);
end;

function FAT32WriteFileAtOffset(volume : PStorage_Volume; directory : pchar; fileName : pchar;
    offset : uint32; buffer : puint32; byteCount : uint32; ctx : pointer) : uint32;
var
    ofi      : PFATOpenFile;
    tempCtx  : pointer;
    fileSize : uint32;
    err      : TError;
begin
    FAT32WriteFileAtOffset := 0;
    if buffer = nil then exit;

    ofi := PFATOpenFile(ctx);
    tempCtx := nil;
    if ofi = nil then begin
        tempCtx := FAT32OpenFile(volume, directory, fileName, fileSize);
        ofi := PFATOpenFile(tempCtx);
    end;
    if ofi = nil then exit;

    if byteCount = 0 then begin
        FAT32EnsureDirEntry(ofi);
        if tempCtx <> nil then
            FAT32CloseFile(tempCtx);
        exit;
    end;

    err := FAT32EnsureCapacityForWrite(ofi, offset, byteCount);
    if err = eNone then
        FAT32WriteFileAtOffset := transferSync(ofi, buffer, offset, byteCount, ftmWrite,
            ofi^.ScratchSector, ofi^.ScratchSize);

    if tempCtx <> nil then
        FAT32CloseFile(tempCtx);
end;

procedure FAT32ReadFileAtOffsetAsync(volume : PStorage_Volume; directory : pchar; fileName : pchar;
    offset : uint32; buffer : puint32; byteCount : uint32; ctx : pointer; bytesRead : puint32;
    callback : TIOCallback; callbackData : pointer);
var
    ofi       : PFATOpenFile;
    asyncCtx  : PFATTransferCtx;
    readLimit : uint32;
begin
    if bytesRead <> nil then bytesRead^ := 0;
    ofi := PFATOpenFile(ctx);
    if (ofi = nil) or (buffer = nil) or (byteCount = 0) then begin
        if callback <> nil then callback(eInvalidArgument, callbackData);
        exit;
    end;

    readLimit := FAT32GetReadLimit(ofi, offset, byteCount);
    if readLimit = 0 then begin
        if callback <> nil then callback(eNone, callbackData);
        exit;
    end;

    asyncCtx := FAT32TransferAlloc(volume);
    if asyncCtx = nil then begin
        if callback <> nil then callback(eOutOfMemory, callbackData);
        exit;
    end;

    asyncCtx^.Mode := ftmRead;
    asyncCtx^.Volume := volume;
    asyncCtx^.OpenFile := ofi;
    asyncCtx^.Buffer := buffer;
    asyncCtx^.Offset := offset;
    asyncCtx^.ByteCount := readLimit;
    asyncCtx^.BytesOut := bytesRead;
    asyncCtx^.Callback := callback;
    asyncCtx^.CallbackData := callbackData;
    asyncContinue(asyncCtx);
end;

procedure FAT32WriteFileAtOffsetAsync(volume : PStorage_Volume; directory : pchar; fileName : pchar;
    offset : uint32; buffer : puint32; byteCount : uint32; ctx : pointer; bytesWritten : puint32;
    callback : TIOCallback; callbackData : pointer);
var
    ofi      : PFATOpenFile;
    asyncCtx : PFATTransferCtx;
    err      : TError;
begin
    if bytesWritten <> nil then bytesWritten^ := 0;
    ofi := PFATOpenFile(ctx);
    if (ofi = nil) or (buffer = nil) then begin
        if callback <> nil then callback(eInvalidArgument, callbackData);
        exit;
    end;

    if byteCount = 0 then begin
        err := FAT32EnsureDirEntry(ofi);
        if callback <> nil then callback(err, callbackData);
        exit;
    end;

    err := FAT32EnsureCapacityForWrite(ofi, offset, byteCount);
    if err <> eNone then begin
        if callback <> nil then callback(err, callbackData);
        exit;
    end;

    asyncCtx := FAT32TransferAlloc(volume);
    if asyncCtx = nil then begin
        if callback <> nil then callback(eOutOfMemory, callbackData);
        exit;
    end;

    asyncCtx^.Mode := ftmWrite;
    asyncCtx^.Volume := volume;
    asyncCtx^.OpenFile := ofi;
    asyncCtx^.Buffer := buffer;
    asyncCtx^.Offset := offset;
    asyncCtx^.ByteCount := byteCount;
    asyncCtx^.BytesOut := bytesWritten;
    asyncCtx^.Callback := callback;
    asyncCtx^.CallbackData := callbackData;
    asyncContinue(asyncCtx);
end;

end.
