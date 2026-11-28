// Copyright 2026 Aaron Hance
// SPDX-License-Identifier: Apache-2.0
unit arch.x86_64.test.storage;

interface
procedure run;

implementation
uses arch.x86_64.memory.physical, arch.x86_64.memory.virtual, arch.platform.cpu,
    arch.x86_64.util, core.strings, core.clock, proc.types, proc.mgr,
    driver.storage.types, driver.storage.vfs, driver.storage.mgr,
    driver.storage.vol.mgr, driver.storage.ctl.usb, memory.heap, test.harness, debug.early;

const
    lengths: array[0..3] of uint32 = (4095, 4096, 4097, 131073);
    guard = 17;
    maxLength = 131073;
    seed = $5317;
type
    PJob = ^TJob;
    TJob = record
        path: pchar;
        buf: puint8;
        arena: PtrUInt;
        id, done, offset, length, phase, actual, closeError: uint32;
        intact: boolean;
        deadline: uint64;
        ok: boolean;
    end;
var
    jobs: array[0..1] of TJob;
    startWork: uint32;
    serialControl: boolean;

function pattern(id, pos: uint32): byte;
begin
    pattern := byte((pos * 37 + (pos shr 8) * 19 + (pos shr 16) * 23 + id * 71 + seed) and 255);
end;

function guardsIntact(j: PJob): boolean;
var i: uint32;
begin
    guardsIntact := false;
    for i := 0 to guard - 1 do
        if (puint8(j^.arena)[i] <> $A5) or (j^.buf[j^.length+i] <> $5A) then exit;
    guardsIntact := true;
end;

procedure arm(j: PJob; phase: uint32);
begin
    j^.phase := phase;
    j^.deadline := core.clock.nowUS + 30000000;
end;

function place(j: PJob; highPages: boolean): boolean;
var page, saved: PtrUInt;
    original, frame, physical: uint64;
begin
    place := false;
    j^.arena := allocate_region(1);
    if j^.arena = 0 then exit;
    j^.buf := puint8(j^.arena + guard);
    page := j^.arena;
    while page < PtrUInt(j^.buf) + maxLength + guard do begin
        physical := translate(page);
        if (physical >= uint64($100000000)) <> highPages then begin
            if highPages then frame := alloc_high else frame := alloc_page(true);
            if frame = 0 then exit;
            saved := lockIRQ;
            if not unmap_page(page, original) then bootstrap_halt;
            if not map_page(page, frame, true) then begin
                if not map_page(page, original, true) then bootstrap_halt;
                free_page(frame);
                unlockIRQ(saved);
                exit;
            end;
            free_page(original);
            unlockIRQ(saved);
        end;
        physical := translate(page);
        if (physical = 0) or ((physical >= uint64($100000000)) <> highPages) then exit;
        inc(page, FRAME_SIZE);
    end;
    field('DIFF_BUFFER_VA', PtrUInt(j^.buf));
    field('DIFF_FIRST_PA', translate(PtrUInt(j^.buf)));
    field('DIFF_VERIFIED_PAGES', (page - j^.arena) div FRAME_SIZE);
    place := j^.arena > $FFFFFFFF;
end;

function roundTrip(j: PJob; first: boolean): boolean;
var i, n: uint32;
    fh: TFileHandle;
    err: TError;
    mode: TOpenMode;
begin
    roundTrip := false;
    for i := 0 to guard - 1 do begin
        puint8(j^.arena)[i] := $A5;
        j^.buf[j^.length+i] := $5A;
    end;
    for i := 0 to j^.length - 1 do j^.buf[i] := pattern(j^.id, j^.offset+i);
    if first then mode := omCreate else mode := omReadWrite;
    arm(j, 1);
    fh := OpenFile(j^.path, mode, @err);
    if err <> eNone then exit;
    arm(j, 2);
    n := WriteFile(fh, j^.offset, j^.buf, j^.length);
    arm(j, 3);
    err := CloseFile(fh);
    j^.actual := n;
    j^.closeError := ord(err);
    j^.intact := guardsIntact(j);
    if (err <> eNone) or (n <> j^.length) or not j^.intact then exit;
    for i := 0 to j^.length - 1 do j^.buf[i] := not pattern(j^.id, j^.offset+i);
    arm(j, 4);
    fh := OpenFile(j^.path, omRead, @err);
    if err <> eNone then exit;
    arm(j, 5);
    n := ReadFile(fh, j^.offset, j^.buf, j^.length);
    arm(j, 6);
    err := CloseFile(fh);
    j^.actual := n;
    j^.closeError := ord(err);
    j^.intact := guardsIntact(j);
    if (err <> eNone) or (n <> j^.length) or not j^.intact then exit;
    for i := 0 to j^.length - 1 do
        if j^.buf[i] <> pattern(j^.id, j^.offset+i) then begin
            field('DIFF_MISMATCH_OFFSET', j^.offset+i);
            exit;
        end;
    roundTrip := true;
end;

procedure worker(ctx: PProcessContext);
var j: PJob;
    k: uint32;
begin
    j := PJob(ctx^.Local);
    while puint32(@startWork)^ = 0 do proc_yield;
    if serialControl and (j^.id = 1) then
        while puint32(@jobs[0].done)^ = 0 do proc_sleep_ms(1);
    j^.ok := true;
    for k := 0 to 3 do begin
        j^.length := lengths[k];
        j^.ok := roundTrip(j, k = 0);
        if not j^.ok then break;
        inc(j^.offset, j^.length);
        proc_yield;
    end;
    j^.done := 1;
end;

procedure describe(j: PJob);
begin
    field('DIFF_WORKER', j^.id);
    field('DIFF_OFFSET', j^.offset);
    field('DIFF_LENGTH', j^.length);
    field('DIFF_PHASE', j^.phase);
    field('DIFF_BYTES_RETURNED', j^.actual);
    field('DIFF_CLOSE_ERROR', j^.closeError);
    field('DIFF_GUARDS_INTACT', ord(j^.intact));
end;

function exercise(vol: PStorage_Volume; highPages: boolean): boolean;
var i: uint32;
    staged: uint32;
    sector: puint8;
    readError: TError;
    ok: boolean;
begin
    exercise := false;
    field('DIFF_SEED', seed);
    field('DIFF_SERIAL', ord(serialControl));
    field('DIFF_HIGH', ord(highPages));
    field('DIFF_CONTROLLER', ord(vol^.device^.controller));
    jobs[0].path := '/disk/ASURODIFF-TEST/WORKA.BIN';
    jobs[1].path := '/disk/ASURODIFF-TEST/WORKB.BIN';
    ok := core.clock.prepare;
    for i := 0 to 1 do begin
        jobs[i].id := i;
        if ok then ok := place(@jobs[i], highPages);
    end;
    if ok then begin
        { Sector 1 is a read-only oracle outside the FAT partition. A raw
          request reaches the controller even if FAT served data from cache. }
        sector := puint8(jobs[0].arena);
        watchStaging(sector);
        readError := storage_read(vol^.device, 1, 1, puint32(sector));
        field('DIFF_SECTOR_ERROR', ord(readError));
        ok := readError = eNone;
        staged := stagedBytes;
        watchStaging(nil);
        for i := 0 to 511 do
            if sector[i] <> pattern(0,i) then ok := false;
        if vol^.device^.controller = ControllerUSB then begin
            field('DIFF_OHCI_LOW_STAGE_BYTES', staged);
            ok := ok and (staged = 512);
        end;
    end;
    if ok then begin
        for i := 0 to 1 do begin
            arm(@jobs[i], 0);
            if proc.mgr.create('storage diff', @worker, void(@jobs[i]), 1) = nil then begin
                jobs[i].done := 1;
                ok := false;
            end;
        end;
        startWork := 1;
        repeat
            proc_sleep_ms(10);
            for i := 0 to 1 do
                if (puint32(@jobs[i].done)^ = 0) and (core.clock.nowUS > jobs[i].deadline) then begin
                    describe(@jobs[i]);
                    puts('DIFF_TIMEOUT'#13#10);
                    bootstrap_halt;
                end;
        until (puint32(@jobs[0].done)^ <> 0) and (puint32(@jobs[1].done)^ <> 0);
        for i := 0 to 1 do begin
            describe(@jobs[i]);
            ok := ok and jobs[i].ok;
        end;
    end;
    for i := 0 to 1 do
        if jobs[i].arena <> 0 then
            if not release_region(jobs[i].arena, 1) then ok := false;
    exercise := ok;
end;

procedure run;
var i, count: uint32;
    vol: PStorage_Volume;
    header: puint8;
    highPages, valid: boolean;
    ctx: TTestContext;
begin
    count := get_volume_count;
    if count = 0 then exit;
    for i := 0 to count - 1 do begin
        vol := get_volume(i);
        if (vol = nil) or (vol^.filesystem = nil) or (vol^.device = nil) then continue;
        if not stringEquals(@vol^.labelText[0], 'ASURODIFF') or
           not (stringEquals(vol^.filesystem^.sName, 'FAT32') or
                stringEquals(vol^.filesystem^.sName, 'EXT2')) then continue;
        if (vol^.sectorStart <> 2048) or (vol^.device^.sectorSize <> 512) then continue;
        header := puint8(tryAlloc(512));
        if header = nil then exit;
        valid := storage_read(vol^.device, 0, 1, puint32(header)) = eNone;
        valid := valid and (puint64(header)^ = uint64($314649444F525341)) and (header[8] <= 1) and (header[9] <= 1);
        highPages := header[8] = 1;
        serialControl := header[9] = 1;
        kfree(void(header));
        if not valid then continue;
        puts('DIFF_FS=');
        puts(vol^.filesystem^.sName);
        puts(#13#10);
        test.harness.Start(@ctx, 'storage.differential');
        valid := mountVolume('/disk/ASURODIFF-TEST', vol) = pvRegistered;
        if valid then valid := exercise(vol, highPages);
        test.harness.Assert(@ctx, valid, 'guarded concurrent file round trips and controller oracle');
        test.harness.Finish(@ctx);
        if valid then puts('DIFF_PASS'#13#10) else puts('DIFF_FAIL'#13#10);
        exit;
    end;
end;
end.
