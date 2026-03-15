{
    App->IOTest - Write and read-back a 10 MB file to exercise offset-based I/O.

    Usage:  IOTEST [path]
    Default path: /disk/vol0/IOTEST.BIN

    Writes 10 MB in 4 KB chunks with a rotating byte pattern, then reads
    the file back and verifies every byte.  Reports throughput (KB/s)
    for both the write and the read phase.

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
    core.strings, arch.x86.bda;

const
    FILE_SIZE  = 10 * 1024 * 1024;  { 10 MB }
    CHUNK_SIZE = 4096*64;           { MB per is 4k*64 = 256 KB, so 40 chunks total }
    TICK_HZ    = 1024;               { timer ISR frequency }
    DEFAULT_PATH : pchar = '/disk/vol0/IOTEST.BIN';

{ Fill buf[0..CHUNK_SIZE-1] with a deterministic pattern seeded by chunkIdx }
procedure fillPattern(buf : puint8; chunkIdx : uint32);
var
    i : uint32;
begin
    if CHUNK_SIZE > 0 then
        for i := 0 to CHUNK_SIZE - 1 do
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

procedure run(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    path       : pchar;
    fh         : TFileHandle;
    fErr       : TError;
    buf        : puint8;
    verBuf     : puint8;
    offset     : uint32;
    chunkIdx   : uint32;
    written    : uint32;
    readBack   : uint32;
    totalChunks: uint32;
    ok         : boolean;
    i          : uint32;
    t0, t1     : uint32;
    elapsed    : uint32;
    kbps       : uint32;
    tmp        : pchar;
    tLast      : uint32;  { tick of last per-second report }
    bytesInSec : uint32;  { bytes transferred since last report }
begin
    { Determine target path }
    path := getParam(0, Params);
    if path = nil then
        path := DEFAULT_PATH;

    totalChunks := FILE_SIZE div CHUNK_SIZE;

    { Allocate two 4 KB heap buffers }
    buf := puint8(kalloc(CHUNK_SIZE));
    verBuf := puint8(kalloc(CHUNK_SIZE));

    { ==================== WRITE PHASE ==================== }
    io.stdio.bufWriteStr(stdout_buf, 'Writing 10 MB to ');
    io.stdio.bufWriteStrLn(stdout_buf, path);

    fh := OpenFile(path, omCreate, @fErr);
    if (fh = 0) or (fErr <> eNone) then begin
        io.stdio.bufWriteStrLn(stderr_buf, 'ERROR: Could not create file.');
        kfree(puint32(buf));
        kfree(puint32(verBuf));
        exit;
    end;

    t0 := arch.x86.bda.Counters.c32;
    tLast := t0;
    bytesInSec := 0;
    offset := 0;
    ok := true;
    if totalChunks > 0 then begin
        for chunkIdx := 0 to totalChunks - 1 do begin
            fillPattern(buf, chunkIdx);
            written := WriteFile(fh, offset, buf, CHUNK_SIZE);
            if written <> CHUNK_SIZE then begin
                io.stdio.bufWriteStr(stderr_buf, 'ERROR: Short write at offset ');
                io.stdio.bufWriteIntLn(stderr_buf, offset);
                ok := false;
                break;
            end;
            offset := offset + CHUNK_SIZE;
            bytesInSec := bytesInSec + CHUNK_SIZE;
            t1 := arch.x86.bda.Counters.c32;
            if (t1 - tLast) >= TICK_HZ then begin
                kbps := (bytesInSec div 1024) * TICK_HZ div (t1 - tLast);
                io.stdio.bufWriteStr(stdout_buf, '  W ');
                io.stdio.bufWriteInt(stdout_buf, offset div 1024);
                io.stdio.bufWriteStr(stdout_buf, ' KB  ');
                writeThroughput(stdout_buf, kbps);
                io.stdio.bufWriteNewLine(stdout_buf);
                tLast := t1;
                bytesInSec := 0;
            end;
        end;
    end;
    t1 := arch.x86.bda.Counters.c32;
    CloseFile(fh);

    if ok then begin
        elapsed := t1 - t0;
        io.stdio.bufWriteStr(stdout_buf, 'Write complete: ');
        if elapsed > 0 then begin
            kbps := ((FILE_SIZE div 1024) * TICK_HZ) div elapsed;
            writeThroughput(stdout_buf, kbps);
            io.stdio.bufWriteStr(stdout_buf, ' (');
            io.stdio.bufWriteInt(stdout_buf, (elapsed * 1000) div TICK_HZ);
            io.stdio.bufWriteStrLn(stdout_buf, ' ms)');
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
        io.stdio.bufWriteStrLn(stderr_buf, 'ERROR: Could not open file for reading.');
        kfree(puint32(buf));
        kfree(puint32(verBuf));
        exit;
    end;

    t0 := arch.x86.bda.Counters.c32;
    tLast := t0;
    bytesInSec := 0;
    offset := 0;
    ok := true;
    if totalChunks > 0 then begin
        for chunkIdx := 0 to totalChunks - 1 do begin
            core.util.memset(uint32(verBuf), 0, CHUNK_SIZE);
            readBack := ReadFile(fh, offset, verBuf, CHUNK_SIZE);
            if readBack <> CHUNK_SIZE then begin
                io.stdio.bufWriteStr(stderr_buf, 'ERROR: Short read at offset ');
                io.stdio.bufWriteInt(stderr_buf, offset);
                io.stdio.bufWriteStr(stderr_buf, ' (got ');
                io.stdio.bufWriteInt(stderr_buf, readBack);
                io.stdio.bufWriteStrLn(stderr_buf, ')');
                ok := false;
                break;
            end;

            { Verify pattern }
            fillPattern(buf, chunkIdx);
            for i := 0 to CHUNK_SIZE - 1 do begin
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
            if not ok then break;

            offset := offset + CHUNK_SIZE;
            bytesInSec := bytesInSec + CHUNK_SIZE;
            t1 := arch.x86.bda.Counters.c32;
            if (t1 - tLast) >= TICK_HZ then begin
                kbps := (bytesInSec div 1024) * TICK_HZ div (t1 - tLast);
                io.stdio.bufWriteStr(stdout_buf, '  R ');
                io.stdio.bufWriteInt(stdout_buf, offset div 1024);
                io.stdio.bufWriteStr(stdout_buf, ' KB  ');
                writeThroughput(stdout_buf, kbps);
                io.stdio.bufWriteNewLine(stdout_buf);
                tLast := t1;
                bytesInSec := 0;
            end;
        end;
    end;
    t1 := arch.x86.bda.Counters.c32;
    CloseFile(fh);

    if ok then begin
        elapsed := t1 - t0;
        io.stdio.bufWriteStr(stdout_buf, 'Read+verify complete: ');
        if elapsed > 0 then begin
            kbps := ((FILE_SIZE div 1024) * TICK_HZ) div elapsed;
            writeThroughput(stdout_buf, kbps);
            io.stdio.bufWriteStr(stdout_buf, ' (');
            io.stdio.bufWriteInt(stdout_buf, (elapsed * 1000) div TICK_HZ);
            io.stdio.bufWriteStrLn(stdout_buf, ' ms)');
        end else
            io.stdio.bufWriteStrLn(stdout_buf, '< 1 tick');
        io.stdio.bufWriteStrLn(stdout_buf, 'PASS: All 10 MB verified OK.');
    end else begin
        io.stdio.bufWriteStrLn(stderr_buf, 'FAIL: Verification failed.');
    end;

    { ==================== CLEANUP ==================== }
    DeleteFile(path, @fErr);

    kfree(puint32(buf));
    kfree(puint32(verBuf));
end;

procedure init();
begin
    debug.tracer.push_trace('iotest.init');
    io.stdio.registerCommand('IOTEST', @run, 'Write and read-verify a 10 MB file.');
end;

end.
