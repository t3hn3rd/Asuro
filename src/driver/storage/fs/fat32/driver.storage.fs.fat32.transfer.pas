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
    proc.mgr, proc.types,
    driver.storage.mgr,
    core.util, arch.platform.cpu,
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
    err : TError;
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

        runByteOffset := currentOffset mod bytesPerCluster;
        sectorOffset := runByteOffset mod sectorSize;
        sectorLBA := FAT32ClusterToLBA(ofi^.VolumeInfo, startCluster) + (runByteOffset div sectorSize);

        if (sectorOffset <> 0) or (remaining < sectorSize) or
           (((PtrUInt(buffer)+bytesDone) and 1) <> 0) then begin
            if (scratch = nil) or (scratchSize < sectorSize) then break;
            chunkBytes := sectorSize - sectorOffset;
            if chunkBytes > remaining then
                chunkBytes := remaining;
            err := driver.storage.mgr.storage_read(ofi^.Volume^.device, sectorLBA, 1, scratch);
            if err <> eNone then break;
            if mode = ftmRead then
                memcpy(PtrUInt(scratch) + sectorOffset, PtrUInt(buffer) + bytesDone, chunkBytes)
            else begin
                memcpy(PtrUInt(buffer) + bytesDone, PtrUInt(scratch) + sectorOffset, chunkBytes);
                err := driver.storage.mgr.storage_write(ofi^.Volume^.device, sectorLBA, 1, scratch);
                if err <> eNone then break;
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
                err := driver.storage.mgr.storage_read(ofi^.Volume^.device, sectorLBA, chunkSectors,
                    puint32(PtrUInt(buffer) + bytesDone))
            else
                err := driver.storage.mgr.storage_write(ofi^.Volume^.device, sectorLBA, chunkSectors,
                    puint32(PtrUInt(buffer) + bytesDone));
        end;

        if err <> eNone then break;
        bytesDone := bytesDone + chunkBytes;
        remaining := remaining - chunkBytes;
        if mode = ftmWrite then
            noteWriteProgress(ofi, offset + bytesDone);
    end;

    transferSync := bytesDone;
end;

procedure asyncComplete(ctx : PFATTransferCtx; error : TError);
var callback : TIOCallback; data : pointer;
begin
    if ctx = nil then exit;
    if ctx^.Pumping then begin
        ctx^.Finished := true; ctx^.LastError := error; exit;
    end;
    if ctx^.BytesOut <> nil then
        ctx^.BytesOut^ := ctx^.BytesDone;
    callback := ctx^.Callback; data := ctx^.CallbackData;
    { Return the context before user code can close the volume or submit again. }
    FAT32TransferFree(ctx);
    if callback <> nil then callback(error,data);
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
                memcpy(PtrUInt(ctx^.ScratchSector) + ctx^.PendingScratchOffset,
                    PtrUInt(ctx^.Buffer) + ctx^.PendingBufferOffset, ctx^.PendingScratchBytes);
                ctx^.BytesDone := ctx^.BytesDone + ctx^.PendingScratchBytes;
                asyncContinue(ctx);
            end else begin
                memcpy(PtrUInt(ctx^.Buffer) + ctx^.PendingBufferOffset,
                    PtrUInt(ctx^.ScratchSector) + ctx^.PendingScratchOffset, ctx^.PendingScratchBytes);
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

{ A batch owns four disjoint destination slices. On failure, drain every
  accepted DMA before releasing context and report only the successful prefix. }
procedure readBatchFinish(ctx : PFATTransferCtx);
var i : uint32; err : TError;
begin
    err := eNone;
    if ctx^.ReadCount > 0 then for i := 0 to ctx^.ReadCount-1 do begin
        if ctx^.ReadSlots[i].Error <> eNone then begin err := ctx^.ReadSlots[i].Error; break; end;
        Inc(ctx^.BytesDone,ctx^.ReadSlots[i].Bytes);
    end;
    ctx^.ReadCount := 0;
    if err <> eNone then asyncComplete(ctx,err) else asyncContinue(ctx);
end;

procedure readSlotDone(error : TError; data : pointer);
var slot : PFATReadSlot; ctx : PFATTransferCtx;
begin
    slot := PFATReadSlot(data); ctx := slot^.Owner;
    slot^.Error := error; Dec(ctx^.ReadPending);
    if (ctx^.ReadPending = 0) and not ctx^.ReadSubmitting then readBatchFinish(ctx);
end;

procedure readBatch(ctx : PFATTransferCtx);
var pos, remaining, idx, base, cluster, off, available, sectors, bytes, lba, size, depth : uint32;
    slot : PFATReadSlot; err : TError;
begin
    ctx^.ReadSubmitting := true; ctx^.ReadCount := 0; ctx^.ReadPending := 0;
    pos := ctx^.BytesDone; size := ctx^.OpenFile^.VolumeInfo^.BootRecord.sectorSize;
    depth := ctx^.Volume^.device^.maxActive;
    if depth > 4 then depth := 4;
    if depth = 0 then depth := 1;
    while (ctx^.ReadCount < depth) and (pos < ctx^.ByteCount) do begin
        remaining := ctx^.ByteCount-pos;
        if remaining < size then break;
        slot := @ctx^.ReadSlots[ctx^.ReadCount];
        slot^.Owner := ctx; slot^.Bytes := 0; slot^.Error := eNone;
        Inc(ctx^.ReadCount);
        if not FAT32FindRunForOffset(ctx^.OpenFile,ctx^.Offset+pos,false,0,0,
            idx,base,cluster,off,available) then begin slot^.Error := eCorruptFilesystem; break; end;
        bytes := remaining; if bytes > available then bytes := available;
        sectors := bytes div size;
        if sectors > FAT_MAX_IO_SECTORS then sectors := FAT_MAX_IO_SECTORS;
        if sectors = 0 then begin slot^.Error := eInvalidArgument; break; end;
        bytes := sectors*size; slot^.Bytes := bytes;
        lba := FAT32ClusterToLBA(ctx^.OpenFile^.VolumeInfo,cluster) +
            ((ctx^.Offset+pos) mod ctx^.OpenFile^.VolumeInfo^.BytesPerCluster) div size;
        Inc(ctx^.ReadPending);
        err := driver.storage.mgr.storage_read_async(ctx^.Volume^.device,lba,sectors,
            puint32(PtrUInt(ctx^.Buffer)+pos),@readSlotDone,slot);
        if err <> eNone then begin Dec(ctx^.ReadPending); slot^.Error := err; break; end;
        if slot^.Error <> eNone then break; { synchronous completion failure }
        Inc(pos,bytes);
    end;
    ctx^.ReadSubmitting := false;
    if ctx^.ReadPending = 0 then readBatchFinish(ctx);
end;

procedure asyncAdvance(ctx : PFATTransferCtx);
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

    runByteOffset := currentOffset mod bytesPerCluster;
    sectorOffset := runByteOffset mod sectorSize;
    ctx^.PendingLBA := FAT32ClusterToLBA(ctx^.OpenFile^.VolumeInfo, startCluster) + (runByteOffset div sectorSize);
    ctx^.PendingBufferOffset := ctx^.BytesDone;

    if (sectorOffset <> 0) or (remaining < sectorSize) or
       (((PtrUInt(ctx^.Buffer)+ctx^.BytesDone) and 1) <> 0) then begin
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

    if ctx^.Mode = ftmRead then begin readBatch(ctx); exit; end;

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
            puint32(PtrUInt(ctx^.Buffer) + ctx^.PendingBufferOffset), @asyncStep, ctx)
    else
        err := driver.storage.mgr.storage_write_async(ctx^.Volume^.device, ctx^.PendingLBA, chunkSectors,
            puint32(PtrUInt(ctx^.Buffer) + ctx^.PendingBufferOffset), @asyncStep, ctx);
    if err <> eNone then
        asyncComplete(ctx, err);
end;

{ Serialize pump state against IRQ completion and turn inline completions
  into iteration, so fake/RAM drivers cannot recursively exhaust the stack. }
procedure asyncContinue(ctx : PFATTransferCtx);
var
    irqFlags: PtrUInt;
    flags : uint32;
begin
    irqFlags := arch.platform.cpu.lock;
    if ctx^.Pumping then ctx^.Resume := true
    else begin
        ctx^.Pumping := true;
        repeat
            ctx^.Resume := false;
            asyncAdvance(ctx);
        until (not ctx^.Resume) or ctx^.Finished;
        ctx^.Pumping := false;
        if ctx^.Finished then asyncComplete(ctx,ctx^.LastError);
    end;
    arch.platform.cpu.unlock(irqFlags);
end;

type
    PReadWait = ^TReadWait;
    TReadWait = record Done, Bytes : uint32; Process : PProcessContext; end;
procedure readWaitDone(error : TError; data : pointer);
var wait : PReadWait;
begin
    wait := PReadWait(data);
    if wait^.Process <> nil then wait^.Process^.State := psReady;
    puint32(@wait^.Done)^ := 1;
end;

function FAT32ReadFileAtOffset(volume : PStorage_Volume; directory : pchar; fileName : pchar;
    offset : uint32; buffer : puint32; byteCount : uint32; ctx : pointer) : uint32;
var
    savedIRQ: PtrUInt;

    ofi       : PFATOpenFile;
    tempCtx   : pointer;
    fileSize  : uint32;
    readLimit : uint32;
    wait : TReadWait;
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
    if readLimit > 0 then begin
        wait.Done := 0; wait.Bytes := 0; wait.Process := CurrentProcess;
        FAT32ReadFileAtOffsetAsync(volume,directory,fileName,offset,buffer,readLimit,ofi,
            @wait.Bytes,@readWaitDone,@wait);
        savedIRQ := arch.platform.cpu.lock;
        if (puint32(@wait.Done)^ = 0) and (CurrentProcess <> nil) then CurrentProcess^.State := psAwaiting;
        arch.platform.cpu.unlock(savedIRQ);
        while puint32(@wait.Done)^ = 0 do arch.platform.cpu.idle;
        FAT32ReadFileAtOffset := wait.Bytes;
    end;

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
