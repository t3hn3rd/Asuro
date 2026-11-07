// Copyright 2026 Aaron Hance
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

{ BSP kernel mappings. Page-table frames stay below 4 GiB so the bootstrap
  identity map can access them; data frames may live above 4 GiB. }
unit arch.x86_64.memory.virtual;
interface
const
    ARENA_SIZE = $400000;
    ARENA_COUNT = 4096;
    HEAP_BASE = PtrUInt($FFFF800000000000);
function allocate_region(arenas: uint32): PtrUInt;
function release_region(address: PtrUInt; arenas: uint32): boolean;
function map_page(address: PtrUInt; physical: uint64; owned: boolean): boolean;
function unmap_page(address: PtrUInt; var physical: uint64): boolean;
function translate(address: PtrUInt): uint64;
procedure init;
procedure UnitTest;
implementation
uses arch.x86_64.memory.physical, arch.x86_64.util, memory.bitmap, debug.early;
const
    ADDRESS_MASK = uint64($000FFFFFFFFFF000);
    PTE_OWNED = uint64(1) shl 9;
var
    root: PUInt64;
    arenaBitmap: PUInt32;
    tablePages: uint64;
    leafFlags: uint64;
    failAfter: sint32; { deterministic OOM injection, disabled outside UnitTest }

function acquire(lowOnly: boolean): uint64;
begin
    acquire := 0;
    if failAfter = 0 then exit;
    if failAfter > 0 then dec(failAfter);
    acquire := arch.x86_64.memory.physical.alloc_page(lowOnly);
end;
procedure fail(message: pchar);
begin puts('FAIL: VMM '); puts(message); puts(#13#10); bootstrap_halt; end;
function managed(address: PtrUInt): boolean;
begin
    managed := (address >= HEAP_BASE) and (address - HEAP_BASE < uint64(ARENA_COUNT) * ARENA_SIZE);
end;
function enableNX: boolean; assembler; nostackframe;
asm
    push rbx
    mov eax, $80000001
    cpuid
    xor eax, eax
    test edx, 1 shl 20
    jz @done
    mov ecx, $C0000080
    rdmsr
    or eax, 1 shl 11
    wrmsr
    mov eax, 1
@done:
    pop rbx
end;
function map_page(address: PtrUInt; physical: uint64; owned: boolean): boolean;
var table, slot: PUInt64; shift, created: sint32; frame, saved: uint64;
    parents: array[0..2] of PUInt64;
    frames: array[0..2] of uint64;
begin
    map_page := false;
    if not managed(address) or ((address and $FFF) <> 0) or
       ((physical and not ADDRESS_MASK) <> 0) then exit;
    saved := lockIRQ;
    table := root; created := 0; shift := 39;
    while shift > 12 do begin
        slot := @table[(address shr shift) and $1FF];
        if (slot^ and 1) = 0 then begin
            frame := acquire(true);
            if frame = 0 then break;
            zero(pointer(PtrUInt(frame)), 4096);
            parents[created] := slot;
            frames[created] := frame;
            inc(created); inc(tablePages);
            slot^ := frame or 3;
        end;
        if (slot^ and $80) <> 0 then break;
        table := PUInt64(PtrUInt(slot^ and ADDRESS_MASK));
        dec(shift, 9);
    end;
    if shift = 12 then begin
        slot := @table[(address shr 12) and $1FF];
        if (slot^ and 1) = 0 then begin
            slot^ := physical or leafFlags;
            if owned then slot^ := slot^ or PTE_OWNED;
            invalidate(address);
            map_page := true;
        end;
    end;
    if not map_page then while created > 0 do begin
        dec(created);
        parents[created]^ := 0;
        if not arch.x86_64.memory.physical.free_page(frames[created]) then fail('table rollback');
        dec(tablePages);
    end;
    unlockIRQ(saved);
end;
function leaf(address: PtrUInt): PUInt64;
var table: PUInt64; shift: sint32; entry: uint64;
begin
    leaf := nil;
    if not managed(address) then exit;
    table := root; shift := 39;
    while shift > 12 do begin
        entry := table[(address shr shift) and $1FF];
        if ((entry and 1) = 0) or ((entry and $80) <> 0) then exit;
        table := PUInt64(PtrUInt(entry and ADDRESS_MASK));
        dec(shift, 9);
    end;
    leaf := @table[(address shr 12) and $1FF];
end;
function translate(address: PtrUInt): uint64;
var table: PUInt64; shift: sint32; entry, span: uint64;
begin
    translate := 0;
    if (address > $00007FFFFFFFFFFF) and (address < HEAP_BASE) then exit;
    table := root; shift := 39;
    while shift >= 12 do begin
        entry := table[(address shr shift) and $1FF];
        if (entry and 1) = 0 then exit;
        if (shift = 12) or (((entry and $80) <> 0) and (shift < 39)) then begin
            span := uint64(1) shl shift;
            translate := (entry and ADDRESS_MASK and not (span - 1)) + (address and (span - 1));
            exit;
        end;
        table := PUInt64(PtrUInt(entry and ADDRESS_MASK));
        dec(shift, 9);
    end;
end;
procedure prune(address: PtrUInt);
var parents: array[0..2] of PUInt64; tables: array[0..2] of PUInt64;
    table, slot: PUInt64; shift, level: sint32; i: uint32; empty: boolean;
begin
    table := root; shift := 39; level := 0;
    while shift > 12 do begin
        slot := @table[(address shr shift) and $1FF];
        if ((slot^ and 1) = 0) or ((slot^ and $80) <> 0) then exit;
        parents[level] := slot;
        table := PUInt64(PtrUInt(slot^ and ADDRESS_MASK));
        tables[level] := table;
        inc(level); dec(shift, 9);
    end;
    while level > 0 do begin
        dec(level); empty := true;
        for i := 0 to 511 do if (tables[level][i] and 1) <> 0 then begin empty := false; break; end;
        if not empty then exit;
        parents[level]^ := 0;
        if not arch.x86_64.memory.physical.free_page(PtrUInt(tables[level])) then fail('table release');
        dec(tablePages);
    end;
end;
function unmap_page(address: PtrUInt; var physical: uint64): boolean;
var slot: PUInt64; saved: PtrUInt;
begin
    unmap_page := false; physical := 0;
    if not managed(address) or ((address and $FFF) <> 0) then exit;
    saved := lockIRQ; slot := leaf(address);
    if slot <> nil then if (slot^ and 1) <> 0 then begin
        physical := slot^ and ADDRESS_MASK;
        slot^ := 0;
        invalidate(address);
        prune(address);
        unmap_page := true;
    end;
    unlockIRQ(saved);
end;
procedure releaseMapped(address: PtrUInt; pages: uint32);
var i: uint32; slot: PUInt64; physical: uint64;
begin
    if pages = 0 then exit;
    for i := 0 to pages - 1 do begin
        slot := leaf(address + uint64(i) * 4096);
        if slot = nil then fail('missing owned mapping');
        physical := slot^ and ADDRESS_MASK;
        slot^ := 0;
        invalidate(address + uint64(i) * 4096);
        if not arch.x86_64.memory.physical.free_page(physical) then fail('data frame release');
    end;
    { Scan empty tables once per 2 MiB span, not once per 4 KiB page. }
    i := 0;
    while i < pages do begin
        prune(address + uint64(i) * 4096);
        inc(i, 512);
    end;
end;
function allocate_region(arenas: uint32): PtrUInt;
var idx: sint32; i, pages: uint32; base, saved: PtrUInt; physical: uint64;
begin
    allocate_region := 0;
    if (arenas = 0) or (arenas > ARENA_COUNT) or (arenaBitmap = nil) then exit;
    saved := lockIRQ;
    idx := find_free_run(arenaBitmap, 0, arenas, ARENA_COUNT);
    if idx < 0 then begin unlockIRQ(saved); exit; end;
    bitmap_set_range(arenaBitmap, idx, arenas);
    base := HEAP_BASE + uint64(idx) * ARENA_SIZE;
    pages := arenas * (ARENA_SIZE div 4096);
    i := 0;
    while i < pages do begin
        physical := acquire(false);
        if physical = 0 then break;
        if not map_page(base + uint64(i) * 4096, physical, true) then begin
            if not arch.x86_64.memory.physical.free_page(physical) then fail('allocation rollback');
            break;
        end;
        inc(i);
    end;
    if i <> pages then begin
        releaseMapped(base, i);
        bitmap_clear_range(arenaBitmap, idx, arenas);
    end else allocate_region := base;
    unlockIRQ(saved);
end;
function release_region(address: PtrUInt; arenas: uint32): boolean;
var idx, i, pages: uint32; saved: PtrUInt; slot: PUInt64;
begin
    release_region := false;
    if not managed(address) or ((address and (ARENA_SIZE - 1)) <> 0) or
       (arenas = 0) or (arenas > ARENA_COUNT) then exit;
    idx := (address - HEAP_BASE) div ARENA_SIZE;
    if arenas > ARENA_COUNT - idx then exit;
    saved := lockIRQ;
    if not bitmap_all_set(arenaBitmap, idx, arenas) then begin unlockIRQ(saved); exit; end;
    pages := arenas * (ARENA_SIZE div 4096);
    for i := 0 to pages - 1 do begin
        slot := leaf(address + uint64(i) * 4096);
        if slot = nil then begin unlockIRQ(saved); exit; end;
        if (slot^ and (PTE_OWNED or 1)) <> (PTE_OWNED or 1) then begin unlockIRQ(saved); exit; end;
    end;
    releaseMapped(address, pages);
    bitmap_clear_range(arenaBitmap, idx, arenas);
    release_region := true;
    unlockIRQ(saved);
end;
procedure init;
var storage: uint64;
begin
    root := PUInt64(PtrUInt(pageRoot and ADDRESS_MASK));
    leafFlags := 3;
    if enableNX then leafFlags := leafFlags or (uint64(1) shl 63);
    tablePages := 0; failAfter := -1;
    storage := arch.x86_64.memory.physical.alloc_page(true);
    if storage = 0 then fail('arena metadata allocation');
    arenaBitmap := PUInt32(PtrUInt(storage));
    zero(arenaBitmap, 4096);
end;
procedure UnitTest;
const TEST_ADDRESS = HEAP_BASE + $800000;
      TEST_PATTERN = uint64($FEDCBA9876543210);
var before, frame, removed, highFrame: uint64; region: PtrUInt; passed, failed: uint32;
    procedure Assert(condition: boolean; name: pchar);
    begin
        if condition then begin inc(passed); puts('PASS: '); end
        else begin inc(failed); puts('FAIL: '); end;
        puts(name); puts(#13#10);
        if not condition then bootstrap_halt;
    end;
begin
    passed := 0; failed := 0; before := free_count;
    frame := arch.x86_64.memory.physical.alloc_page(true);
    Assert(frame <> 0, 'VMM test frame allocation');
    Assert(map_page(TEST_ADDRESS, frame, false), 'VMM high virtual mapping');
    Assert(not map_page(TEST_ADDRESS, frame, false) and
        not map_page(TEST_ADDRESS + 1, frame, false), 'VMM rejects duplicate/unaligned mapping');
    Assert(translate(TEST_ADDRESS + 123) = frame + 123, 'VMM translation includes page offset');
    PUInt64(TEST_ADDRESS)^ := TEST_PATTERN;
    Assert(PUInt64(PtrUInt(frame))^ = TEST_PATTERN, 'VMM aliases the expected physical frame');
    Assert(unmap_page(TEST_ADDRESS, removed) and (removed = frame) and
        (translate(TEST_ADDRESS) = 0), 'VMM unmap invalidates translation');
    Assert(arch.x86_64.memory.physical.free_page(frame), 'VMM returns backing frame');
    Assert((free_count = before) and (tablePages = 0), 'VMM prunes empty tables without leaks');
    failAfter := 2;
    region := allocate_region(1);
    failAfter := -1;
    Assert((region = 0) and (free_count = before) and (tablePages = 0), 'VMM rolls back partial table allocation on OOM');
    failAfter := 12;
    region := allocate_region(1);
    failAfter := -1;
    Assert((region = 0) and (free_count = before) and (tablePages = 0), 'VMM rolls back partially populated arenas on OOM');
    highFrame := alloc_high;
    if highFrame <> 0 then begin
        Assert(map_page(TEST_ADDRESS, highFrame, false), 'VMM maps physical RAM above 4 GiB');
        PUInt64(TEST_ADDRESS)^ := $123456789ABCDEF0;
        Assert((PUInt64(TEST_ADDRESS)^ = $123456789ABCDEF0) and
            (translate(TEST_ADDRESS) = highFrame), 'VMM reads and writes physical RAM above 4 GiB');
        Assert(unmap_page(TEST_ADDRESS, removed) and
            arch.x86_64.memory.physical.free_page(highFrame), 'VMM releases high physical RAM');
    end else puts('SKIP: no available physical RAM above 4 GiB'#13#10);
    region := allocate_region(1);
    Assert(region <> 0, 'VMM contiguous arena backed by 4 KiB frames');
    PUInt64(region)^ := 1;
    PUInt64(region + ARENA_SIZE - 8)^ := 2;
    Assert((PUInt64(region)^ = 1) and (PUInt64(region + ARENA_SIZE - 8)^ = 2), 'VMM first/last arena pages writable');
    Assert(release_region(region, 1), 'VMM releases complete arena');
    Assert((free_count = before) and (tablePages = 0), 'VMM final frame accounting restored');
    field('VMM_TESTS_FAILED', failed);
end;
end.
