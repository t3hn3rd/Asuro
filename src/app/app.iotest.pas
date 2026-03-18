{
    App->IOTest - Write and read-back a file to exercise offset-based I/O.

    Usage:  IOTEST [size] [path]
    Default size: 25 MB
    Default path: /disk/vol0/IOTEST.BIN

    Writes the requested size in chunks with a rotating byte pattern, then
    reads the file back and verifies every byte. Reports pure I/O throughput
    separately from buffer fill and verification overhead.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit app.iotest;

interface

uses
    io.stdio, debug.tracer;

procedure init();

implementation

uses
    driver.storage.vfs, driver.storage.types,
    memory.heap, core.util, arch.x86.util,
    core.strings, arch.x86.bda,
    proc.mgr, proc.types;

const
    DEFAULT_FILE_SIZE = 25 * 1024 * 1024;  { 25 MB }
    CHUNK_SIZE = 4096*128;           { MB per is 4k*128 = 512 KB, so 50 chunks total }
    TICK_HZ    = 1024;               { timer ISR frequency }
    IO_WAIT_TIMEOUT_TICKS = 10 * TICK_HZ;
    DELETE_TIMEOUT_TICKS = 5 * TICK_HZ;
    DEFAULT_PATH : pchar = '/disk/vol2/IOTEST.BIN';

type
    TIOTSyncWaitCtx = record
        Done      : uint32;
        Error     : TError;
        BytesDone : uint32;
        Process   : proc.types.PProcessContext;
    end;
    PIOTSyncWaitCtx = ^TIOTSyncWaitCtx;

function isNumericStr(s : pchar) : boolean;
var
    i : uint32;
begin
    isNumericStr := false;
    if (s = nil) or (s[0] = char(0)) then exit;
    i := 0;
    while s[i] <> char(0) do begin
        if (s[i] < '0') or (s[i] > '9') then exit;
        i := i + 1;
    end;
    isNumericStr := true;
end;

function parseSizeBytes(s : pchar) : uint32;
var
    len      : uint32;
    idx      : uint32;
    digitsEnd: uint32;
    value    : uint32;
    unit1    : char;
    unit2    : char;
begin
    parseSizeBytes := 0;
    if s = nil then exit;
    len := stringSize(s);
    if len = 0 then exit;

    idx := 0;
    value := 0;
    while (idx < len) and (s[idx] >= '0') and (s[idx] <= '9') do begin
        value := (value * 10) + uint32(uint8(s[idx]) - uint8('0'));
        idx := idx + 1;
    end;
    if (idx = 0) or (value = 0) then exit;

    digitsEnd := idx;
    unit1 := #0;
    unit2 := #0;
    if idx < len then begin
        unit1 := s[idx];
        idx := idx + 1;
    end;
    if idx < len then begin
        unit2 := s[idx];
        idx := idx + 1;
    end;
    if idx <> len then exit;

    if unit1 = #0 then begin
        parseSizeBytes := value;
        exit;
    end;

    if (unit2 <> #0) and (unit2 <> 'B') and (unit2 <> 'b') then
        exit;

    if (digitsEnd + 2 = len) and ((unit1 = 'K') or (unit1 = 'k')) then
        parseSizeBytes := value * 1024
    else if (digitsEnd + 2 = len) and ((unit1 = 'M') or (unit1 = 'm')) then
        parseSizeBytes := value * 1048576
    else if (digitsEnd + 2 = len) and ((unit1 = 'G') or (unit1 = 'g')) then
        parseSizeBytes := value * 1073741824
    else if (digitsEnd + 1 = len) and ((unit1 = 'B') or (unit1 = 'b')) then
        parseSizeBytes := value
    else begin
        if unit2 <> #0 then
            exit;
        if ((unit1 = 'K') or (unit1 = 'k')) then
            parseSizeBytes := value * 1024
        else if ((unit1 = 'M') or (unit1 = 'm')) then
            parseSizeBytes := value * 1048576
        else if ((unit1 = 'G') or (unit1 = 'g')) then
            parseSizeBytes := value * 1073741824;
    end;
end;

procedure writeSize(buf : POutBuf; bytes : uint32);
begin
    if bytes >= 1073741824 then begin
        io.stdio.bufWriteInt(buf, bytes div 1073741824);
        io.stdio.bufWriteStr(buf, '.');
        io.stdio.bufWriteInt(buf, ((bytes mod 1073741824) * 10) div 1073741824);
        io.stdio.bufWriteStr(buf, ' GB');
    end else if bytes >= 1048576 then begin
        io.stdio.bufWriteInt(buf, bytes div 1048576);
        io.stdio.bufWriteStr(buf, '.');
        io.stdio.bufWriteInt(buf, ((bytes mod 1048576) * 10) div 1048576);
        io.stdio.bufWriteStr(buf, ' MB');
    end else if bytes >= 1024 then begin
        io.stdio.bufWriteInt(buf, bytes div 1024);
        io.stdio.bufWriteStr(buf, '.');
        io.stdio.bufWriteInt(buf, ((bytes mod 1024) * 10) div 1024);
        io.stdio.bufWriteStr(buf, ' KB');
    end else begin
        io.stdio.bufWriteInt(buf, bytes);
        io.stdio.bufWriteStr(buf, ' B');
    end;
end;

{ Fill buf[0..byteCount-1] with a deterministic pattern seeded by chunkIdx }
procedure fillPattern(buf : puint8; chunkIdx : uint32; byteCount : uint32);
var
    i : uint32;
begin
    if byteCount > 0 then
        for i := 0 to byteCount - 1 do
            buf[i] := uint8((chunkIdx + i) and $FF);
end;

{ Write throughput with auto-scaled units: KB/s or MB/s }
procedure writeThroughput(buf : POutBuf; kbps : uint32);
begin
    if kbps >= 1024 then begin
        io.stdio.bufWriteInt(buf, kbps div 1024);
        io.stdio.bufWriteStr(buf, '.');
        io.stdio.bufWriteInt(buf, ((kbps mod 1024) * 10) div 1024);
        io.stdio.bufWriteStr(buf, ' MB/s');
    end else begin
        io.stdio.bufWriteInt(buf, kbps);
        io.stdio.bufWriteStr(buf, ' KB/s');
    end;
end;

procedure iot_sync_complete(error : TError; userdata : pointer);
var
    ctx : PIOTSyncWaitCtx;
begin
    ctx := PIOTSyncWaitCtx(userdata);
    if ctx = nil then exit;
    if ctx^.Process <> nil then
        ctx^.Process^.State := psReady;
    ctx^.Error := error;
    puint32(@ctx^.Done)^ := 1;
end;

procedure writeErrorName(buf : POutBuf; err : TError);
begin
    case err of
        eNone: io.stdio.bufWriteStr(buf, 'eNone');
        eUnknown: io.stdio.bufWriteStr(buf, 'eUnknown');
        eNotSupported: io.stdio.bufWriteStr(buf, 'eNotSupported');
        eOutOfMemory: io.stdio.bufWriteStr(buf, 'eOutOfMemory');
        eInvalidArgument: io.stdio.bufWriteStr(buf, 'eInvalidArgument');
        eFileInUse: io.stdio.bufWriteStr(buf, 'eFileInUse');
        eFileDoesNotExist: io.stdio.bufWriteStr(buf, 'eFileDoesNotExist');
        eInvalidFileName: io.stdio.bufWriteStr(buf, 'eInvalidFileName');
        eInvalidFileExtension: io.stdio.bufWriteStr(buf, 'eInvalidFileExtension');
        eFilenameTooLong: io.stdio.bufWriteStr(buf, 'eFilenameTooLong');
        eDirectoryDoesNotExist: io.stdio.bufWriteStr(buf, 'eDirectoryDoesNotExist');
        eDirectoryAlreadyExists: io.stdio.bufWriteStr(buf, 'eDirectoryAlreadyExists');
        eDirectoryNotEmpty: io.stdio.bufWriteStr(buf, 'eDirectoryNotEmpty');
        eDirectoryFull: io.stdio.bufWriteStr(buf, 'eDirectoryFull');
        eNotADirectory: io.stdio.bufWriteStr(buf, 'eNotADirectory');
        eWriteOnly: io.stdio.bufWriteStr(buf, 'eWriteOnly');
        eReadOnly: io.stdio.bufWriteStr(buf, 'eReadOnly');
        ePermissionDenied: io.stdio.bufWriteStr(buf, 'ePermissionDenied');
        eInvalidPath: io.stdio.bufWriteStr(buf, 'eInvalidPath');
        eTooManyOpenFiles: io.stdio.bufWriteStr(buf, 'eTooManyOpenFiles');
        eInvalidHandle: io.stdio.bufWriteStr(buf, 'eInvalidHandle');
        eFileNotLoaded: io.stdio.bufWriteStr(buf, 'eFileNotLoaded');
        eAlreadyExists: io.stdio.bufWriteStr(buf, 'eAlreadyExists');
        eDiskFull: io.stdio.bufWriteStr(buf, 'eDiskFull');
        eIOError: io.stdio.bufWriteStr(buf, 'eIOError');
        eIOTimeout: io.stdio.bufWriteStr(buf, 'eIOTimeout');
        eIOCancelled: io.stdio.bufWriteStr(buf, 'eIOCancelled');
        eDeviceNotReady: io.stdio.bufWriteStr(buf, 'eDeviceNotReady');
        eDeviceRemoved: io.stdio.bufWriteStr(buf, 'eDeviceRemoved');
        eDeviceNotFound: io.stdio.bufWriteStr(buf, 'eDeviceNotFound');
        eQueueFull: io.stdio.bufWriteStr(buf, 'eQueueFull');
        eNoFreeSlot: io.stdio.bufWriteStr(buf, 'eNoFreeSlot');
        eCorruptFilesystem: io.stdio.bufWriteStr(buf, 'eCorruptFilesystem');
        eBadSector: io.stdio.bufWriteStr(buf, 'eBadSector');
        eAlreadyMounted: io.stdio.bufWriteStr(buf, 'eAlreadyMounted');
        eNotMounted: io.stdio.bufWriteStr(buf, 'eNotMounted');
        eUnsupportedFilesystem: io.stdio.bufWriteStr(buf, 'eUnsupportedFilesystem');
        eInvalidPartitionTable: io.stdio.bufWriteStr(buf, 'eInvalidPartitionTable');
        eVolumeNotFound: io.stdio.bufWriteStr(buf, 'eVolumeNotFound');
    end;
end;

function currentTicks : uint32;
begin
    currentTicks := puint32(@arch.x86.bda.Counters.c32)^;
end;

function waitForIOTask(var wait : TIOTSyncWaitCtx; timeoutTicks : uint32; var err : TError) : boolean;
var
    startT : uint32;
begin
    waitForIOTask := false;
    startT := currentTicks;

    asm pushf; cli end;
    if puint32(@wait.Done)^ = 0 then begin
        if proc.mgr.CurrentProcess <> nil then
            proc.mgr.CurrentProcess^.State := psAwaiting;
    end;
    asm popf end;

    while puint32(@wait.Done)^ = 0 do begin
        if (timeoutTicks > 0) and ((currentTicks - startT) >= timeoutTicks) then begin
            err := eIOTimeout;
            if proc.mgr.CurrentProcess <> nil then
                proc.mgr.CurrentProcess^.State := psReady;
            exit;
        end;
        asm hlt end;
    end;

    err := wait.Error;
    waitForIOTask := wait.Error = eNone;
end;

function writeFileWithError(fileHandle : TFileHandle; position : uint32; buffer : puint8;
    length : uint32; var err : TError) : uint32;
var
    wait : TIOTSyncWaitCtx;
begin
    writeFileWithError := 0;
    memset(uint32(@wait), 0, sizeof(TIOTSyncWaitCtx));
    wait.Error := eUnknown;
    wait.Process := proc.mgr.CurrentProcess;

    driver.storage.vfs.WriteFileAsync(fileHandle, position, buffer, length,
        @wait.BytesDone, @iot_sync_complete, @wait);
    if waitForIOTask(wait, IO_WAIT_TIMEOUT_TICKS, err) then
        writeFileWithError := wait.BytesDone;
end;

function readFileWithError(fileHandle : TFileHandle; position : uint32; buffer : puint8;
    length : uint32; var err : TError) : uint32;
var
    wait : TIOTSyncWaitCtx;
begin
    readFileWithError := 0;
    memset(uint32(@wait), 0, sizeof(TIOTSyncWaitCtx));
    wait.Error := eUnknown;
    wait.Process := proc.mgr.CurrentProcess;

    driver.storage.vfs.ReadFileAsync(fileHandle, position, buffer, length,
        @wait.BytesDone, @iot_sync_complete, @wait);
    if waitForIOTask(wait, IO_WAIT_TIMEOUT_TICKS, err) then
        readFileWithError := wait.BytesDone;
end;

function deleteFileWithTimeout(path : pchar; var err : TError; timeoutTicks : uint32) : boolean;
var
    wait   : TIOTSyncWaitCtx;
    startT : uint32;
begin
    deleteFileWithTimeout := false;
    memset(uint32(@wait), 0, sizeof(TIOTSyncWaitCtx));
    wait.Error := eUnknown;
    wait.Process := proc.mgr.CurrentProcess;
    startT := currentTicks;

    driver.storage.vfs.DeleteFileAsync(path, @err, @iot_sync_complete, @wait);

    while puint32(@wait.Done)^ = 0 do begin
        if (currentTicks - startT) >= timeoutTicks then begin
            err := eIOTimeout;
            if proc.mgr.CurrentProcess <> nil then
                proc.mgr.CurrentProcess^.State := psReady;
            exit;
        end;
        asm hlt end;
    end;

    err := wait.Error;
    deleteFileWithTimeout := wait.Error = eNone;
end;

procedure run(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    path       : pchar;
    sizeParam  : pchar;
    pathParam  : pchar;
    fh         : TFileHandle;
    fErr       : TError;
    buf        : puint8;
    verBuf     : puint8;
    offset     : uint32;
    chunkIdx   : uint32;
    chunkBytes : uint32;
    written    : uint32;
    readBack   : uint32;
    fileSize   : uint32;
    ok         : boolean;
    i          : uint32;
    t0, t1     : uint32;
    elapsed    : uint32;
    kbps       : uint32;
    tLast      : uint32;  { tick of last per-second report }
    bytesInSec : uint32;  { bytes transferred since last report }
    ioTicks    : uint32;
    prepTicks  : uint32;
    verifyTicks: uint32;
    ioTicksInSec : uint32;
    opStart    : uint32;
    opEnd      : uint32;
    parsedSize : uint32;
    ioErr      : TError;
begin
    fileSize := DEFAULT_FILE_SIZE;
    path := DEFAULT_PATH;
    sizeParam := getParam(0, Params);
    pathParam := getParam(1, Params);

    if sizeParam <> nil then begin
        parsedSize := parseSizeBytes(sizeParam);
        if parsedSize > 0 then begin
            fileSize := parsedSize;
            if pathParam <> nil then
                path := pathParam;
        end else begin
            { Backward-compatible path-only form: IOTEST [path] }
            path := sizeParam;
        end;
    end;

    { Allocate two heap buffers }
    buf := puint8(kalloc(CHUNK_SIZE));
    verBuf := puint8(kalloc(CHUNK_SIZE));
    if (buf = nil) or (verBuf = nil) then begin
        io.stdio.bufWriteStrLn(stderr_buf, 'ERROR: Out of memory.');
        if buf <> nil then kfree(puint32(buf));
        if verBuf <> nil then kfree(puint32(verBuf));
        exit;
    end;

    { ==================== WRITE PHASE ==================== }
    io.stdio.bufWriteStr(stdout_buf, 'Writing ');
    writeSize(stdout_buf, fileSize);
    io.stdio.bufWriteStr(stdout_buf, ' to ');
    io.stdio.bufWriteStrLn(stdout_buf, path);

    fh := OpenFile(path, omCreate, @fErr);
    if (fh = 0) or (fErr <> eNone) then begin
        io.stdio.bufWriteStr(stderr_buf, 'ERROR: Could not create file: ');
        writeErrorName(stderr_buf, fErr);
        io.stdio.bufWriteNewLine(stderr_buf);
        kfree(puint32(buf));
        kfree(puint32(verBuf));
        exit;
    end;

    t0 := arch.x86.bda.Counters.c32;
    tLast := t0;
    bytesInSec := 0;
    ioTicks := 0;
    prepTicks := 0;
    ioTicksInSec := 0;
    offset := 0;
    ok := true;
    chunkIdx := 0;
    while offset < fileSize do begin
        chunkBytes := fileSize - offset;
        if chunkBytes > CHUNK_SIZE then
            chunkBytes := CHUNK_SIZE;
        opStart := arch.x86.bda.Counters.c32;
        fillPattern(buf, chunkIdx, chunkBytes);
        opEnd := arch.x86.bda.Counters.c32;
        prepTicks := prepTicks + (opEnd - opStart);
        opStart := arch.x86.bda.Counters.c32;
        written := writeFileWithError(fh, offset, buf, chunkBytes, ioErr);
        opEnd := arch.x86.bda.Counters.c32;
        ioTicks := ioTicks + (opEnd - opStart);
        ioTicksInSec := ioTicksInSec + (opEnd - opStart);
        if written <> chunkBytes then begin
                io.stdio.bufWriteStr(stderr_buf, 'ERROR: Short write at offset ');
                io.stdio.bufWriteInt(stderr_buf, offset);
                io.stdio.bufWriteStr(stderr_buf, ' (got ');
                io.stdio.bufWriteInt(stderr_buf, written);
                io.stdio.bufWriteStr(stderr_buf, ', err ');
                writeErrorName(stderr_buf, ioErr);
                io.stdio.bufWriteStrLn(stderr_buf, ')');
                ok := false;
                break;
        end;
        offset := offset + chunkBytes;
        bytesInSec := bytesInSec + chunkBytes;
        if ioTicksInSec >= TICK_HZ then begin
            kbps := (bytesInSec div 1024) * TICK_HZ div ioTicksInSec;
            io.stdio.bufWriteStr(stdout_buf, '  W ');
            io.stdio.bufWriteInt(stdout_buf, offset div 1024);
            io.stdio.bufWriteStr(stdout_buf, ' KB  ');
            writeThroughput(stdout_buf, kbps);
            io.stdio.bufWriteNewLine(stdout_buf);
            tLast := arch.x86.bda.Counters.c32;
            bytesInSec := 0;
            ioTicksInSec := 0;
        end;
        chunkIdx := chunkIdx + 1;
    end;
    opStart := arch.x86.bda.Counters.c32;
    io.stdio.bufWriteStrLn(stdout_buf, 'Closing write handle...');
    CloseFile(fh);
    opEnd := arch.x86.bda.Counters.c32;
    ioTicks := ioTicks + (opEnd - opStart);
    t1 := opEnd;
    io.stdio.bufWriteStrLn(stdout_buf, 'Write handle closed.');

    if ok then begin
        elapsed := ioTicks;
        io.stdio.bufWriteStr(stdout_buf, 'Write I/O complete: ');
        if elapsed > 0 then begin
            kbps := ((fileSize div 1024) * TICK_HZ) div elapsed;
            writeThroughput(stdout_buf, kbps);
            io.stdio.bufWriteStr(stdout_buf, ' (');
            io.stdio.bufWriteInt(stdout_buf, (elapsed * 1000) div TICK_HZ);
            io.stdio.bufWriteStrLn(stdout_buf, ' ms)');
        end else
            io.stdio.bufWriteStrLn(stdout_buf, '< 1 tick');
        io.stdio.bufWriteStr(stdout_buf, 'Write buffer fill: ');
        if prepTicks > 0 then begin
            io.stdio.bufWriteInt(stdout_buf, (prepTicks * 1000) div TICK_HZ);
            io.stdio.bufWriteStrLn(stdout_buf, ' ms');
        end else
            io.stdio.bufWriteStrLn(stdout_buf, '< 1 tick');
    end;

    if not ok then begin
        kfree(puint32(buf));
        kfree(puint32(verBuf));
        exit;
    end;

    { ==================== READ + VERIFY PHASE ==================== }
    io.stdio.bufWriteStrLn(stdout_buf, 'Reading back and verifying...');

    fh := OpenFile(path, omRead, @fErr);
    if (fh = 0) or (fErr <> eNone) then begin
        io.stdio.bufWriteStr(stderr_buf, 'ERROR: Could not open file for reading: ');
        writeErrorName(stderr_buf, fErr);
        io.stdio.bufWriteNewLine(stderr_buf);
        kfree(puint32(buf));
        kfree(puint32(verBuf));
        exit;
    end;

    t0 := arch.x86.bda.Counters.c32;
    tLast := t0;
    bytesInSec := 0;
    ioTicks := 0;
    verifyTicks := 0;
    ioTicksInSec := 0;
    offset := 0;
    ok := true;
    chunkIdx := 0;
    while offset < fileSize do begin
        chunkBytes := fileSize - offset;
        if chunkBytes > CHUNK_SIZE then
            chunkBytes := CHUNK_SIZE;
        core.util.memset(uint32(verBuf), 0, chunkBytes);
        opStart := arch.x86.bda.Counters.c32;
        readBack := readFileWithError(fh, offset, verBuf, chunkBytes, ioErr);
        opEnd := arch.x86.bda.Counters.c32;
        ioTicks := ioTicks + (opEnd - opStart);
        ioTicksInSec := ioTicksInSec + (opEnd - opStart);
        if readBack <> chunkBytes then begin
                io.stdio.bufWriteStr(stderr_buf, 'ERROR: Short read at offset ');
                io.stdio.bufWriteInt(stderr_buf, offset);
                io.stdio.bufWriteStr(stderr_buf, ' (got ');
                io.stdio.bufWriteInt(stderr_buf, readBack);
                io.stdio.bufWriteStr(stderr_buf, ', err ');
                writeErrorName(stderr_buf, ioErr);
                io.stdio.bufWriteStrLn(stderr_buf, ')');
                ok := false;
                break;
        end;

        { Verify pattern }
        opStart := arch.x86.bda.Counters.c32;
        fillPattern(buf, chunkIdx, chunkBytes);
        if chunkBytes > 0 then begin
            for i := 0 to chunkBytes - 1 do begin
                if verBuf[i] <> buf[i] then begin
                    io.stdio.bufWriteStr(stderr_buf, 'ERROR: Mismatch at offset ');
                    io.stdio.bufWriteInt(stderr_buf, offset + i);
                    io.stdio.bufWriteStr(stderr_buf, ' expected ');
                    io.stdio.bufWriteHexPair(stderr_buf, buf[i]);
                    io.stdio.bufWriteStr(stderr_buf, ' got ');
                    io.stdio.bufWriteHexPair(stderr_buf, verBuf[i]);
                    io.stdio.bufWriteNewLine(stderr_buf);
                    ok := false;
                    break;
                end;
            end;
        end;
        opEnd := arch.x86.bda.Counters.c32;
        verifyTicks := verifyTicks + (opEnd - opStart);
        if not ok then break;

        offset := offset + chunkBytes;
        bytesInSec := bytesInSec + chunkBytes;
        if ioTicksInSec >= TICK_HZ then begin
            kbps := (bytesInSec div 1024) * TICK_HZ div ioTicksInSec;
            io.stdio.bufWriteStr(stdout_buf, '  R ');
            io.stdio.bufWriteInt(stdout_buf, offset div 1024);
            io.stdio.bufWriteStr(stdout_buf, ' KB  ');
            writeThroughput(stdout_buf, kbps);
            io.stdio.bufWriteNewLine(stdout_buf);
            tLast := arch.x86.bda.Counters.c32;
            bytesInSec := 0;
            ioTicksInSec := 0;
        end;
        chunkIdx := chunkIdx + 1;
    end;
    opStart := arch.x86.bda.Counters.c32;
    io.stdio.bufWriteStrLn(stdout_buf, 'Closing read handle...');
    CloseFile(fh);
    opEnd := arch.x86.bda.Counters.c32;
    ioTicks := ioTicks + (opEnd - opStart);
    t1 := opEnd;
    io.stdio.bufWriteStrLn(stdout_buf, 'Read handle closed.');

    if ok then begin
        elapsed := ioTicks;
        io.stdio.bufWriteStr(stdout_buf, 'Read I/O complete: ');
        if elapsed > 0 then begin
            kbps := ((fileSize div 1024) * TICK_HZ) div elapsed;
            writeThroughput(stdout_buf, kbps);
            io.stdio.bufWriteStr(stdout_buf, ' (');
            io.stdio.bufWriteInt(stdout_buf, (elapsed * 1000) div TICK_HZ);
            io.stdio.bufWriteStrLn(stdout_buf, ' ms)');
        end else
            io.stdio.bufWriteStrLn(stdout_buf, '< 1 tick');
        io.stdio.bufWriteStr(stdout_buf, 'Verification pass: ');
        if verifyTicks > 0 then begin
            io.stdio.bufWriteInt(stdout_buf, (verifyTicks * 1000) div TICK_HZ);
            io.stdio.bufWriteStrLn(stdout_buf, ' ms');
        end else
            io.stdio.bufWriteStrLn(stdout_buf, '< 1 tick');
        io.stdio.bufWriteStr(stdout_buf, 'PASS: All ');
        writeSize(stdout_buf, fileSize);
        io.stdio.bufWriteStrLn(stdout_buf, ' verified OK.');
    end else begin
        io.stdio.bufWriteStrLn(stderr_buf, 'FAIL: Verification failed.');
    end;

    { ==================== CLEANUP ==================== }
    io.stdio.bufWriteStrLn(stdout_buf, 'Deleting test file...');
    if deleteFileWithTimeout(path, fErr, DELETE_TIMEOUT_TICKS) then
        io.stdio.bufWriteStrLn(stdout_buf, 'Test file deleted.')
    else begin
        io.stdio.bufWriteStr(stdout_buf, 'Cleanup skipped: ');
        writeErrorName(stdout_buf, fErr);
        io.stdio.bufWriteNewLine(stdout_buf);
    end;

    kfree(puint32(buf));
    kfree(puint32(verBuf));
end;

procedure init();
begin
    debug.tracer.push_trace('iotest.init');
    io.stdio.registerCommand('IOTEST', @run, 'Write and read-verify a file. Usage: IOTEST [size] [path]');
end;

end.
