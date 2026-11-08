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

{ 4 KiB physical frames. Metadata is carved once from verified low RAM before
  the heap exists. Non-available memory-map entries always override available
  entries. Only the BSP is active; IRQ exclusion is not an SMP lock. }
unit arch.x86_64.memory.physical;

interface
uses boot.multiboot;
const
    FRAME_SIZE = 4096;
    MAX_MANAGED = uint64(64) shl 30;
procedure init(info: Pmultiboot_info_t);
function alloc_page(lowOnly: boolean): uint64;
function alloc_high: uint64;
function free_page(address: uint64): boolean;
function reserve_range(address, bytes: uint64): boolean;
function free_count: uint64;
function total_count: uint64;
procedure UnitTest;

implementation
uses arch.x86_64.util, debug.early;
var
    eligible, used: PUInt32;
    frameCount, wordCount, hint: uint32;
    freeFrames, totalFrames: uint64;
    reservedEnd: uint64;
    kernelEnd: uint8; external name 'kernel_end';
    mapStart, mapEnd: PtrUInt;

procedure fail(message: pchar);
begin
    puts('FAIL: PMM ');
    puts(message);
    puts(#13#10);
    bootstrap_halt;
end;

function regionEnd(base, bytes: uint64): uint64;
begin
    if (base >= MAX_MANAGED) or (bytes > MAX_MANAGED - base) then
        regionEnd := MAX_MANAGED
    else regionEnd := base + bytes;
end;

function nextEntry(entry: Pmemory_map_t): Pmemory_map_t;
begin
    nextEntry := Pmemory_map_t(PtrUInt(entry) + entry^.size + 4);
end;

procedure preserve(address, bytes: uint64);
var
    finish: uint64;
begin
    if (address >= $100000000) or (bytes > $100000000 - address) then
        fail('boot data outside initial mapping');
    finish := address + bytes;
    if finish > reservedEnd then reservedEnd := finish;
end;

procedure setAvailable(base, bytes: uint64; available: boolean);
var
    first, last, i, mask: uint32;
    finish: uint64;
begin
    finish := regionEnd(base, bytes);
    if (base >= finish) or (base >= uint64(frameCount) * FRAME_SIZE) then exit;
    if available then begin
        first := (base + FRAME_SIZE - 1) div FRAME_SIZE;
        last := finish div FRAME_SIZE;
    end else begin
        first := base div FRAME_SIZE;
        last := (finish + FRAME_SIZE - 1) div FRAME_SIZE;
    end;
    if last > frameCount then last := frameCount;
    if first >= last then exit;
    for i := first to last - 1 do begin
        mask := uint32(1) shl (i and 31);
        if available then begin
            if (eligible[i shr 5] and mask) = 0 then begin
                eligible[i shr 5] := eligible[i shr 5] or mask;
                inc(freeFrames);
            end;
        end else if (eligible[i shr 5] and mask) <> 0 then begin
            eligible[i shr 5] := eligible[i shr 5] and not mask;
            dec(freeFrames);
        end;
    end;
end;

function metadataAddress(bytes: uint64): uint64;
var
    e, other: Pmemory_map_t;
    candidate, finish, nextCandidate: uint64;
begin
    metadataAddress := 0;
    e := Pmemory_map_t(mapStart);
    while PtrUInt(e) < mapEnd do begin
        if (e^.mtype = 1) and (e^.base_addr < $100000000) and (e^.length <> 0) then begin
            candidate := (e^.base_addr + FRAME_SIZE - 1) and not uint64(FRAME_SIZE - 1);
            if candidate < reservedEnd then candidate := reservedEnd;
            finish := regionEnd(e^.base_addr, e^.length);
            if finish > $100000000 then finish := $100000000;
            while (candidate < finish) and (bytes <= finish - candidate) do begin
                nextCandidate := candidate;
                other := Pmemory_map_t(mapStart);
                while PtrUInt(other) < mapEnd do begin
                    if (other^.mtype <> 1) and (other^.base_addr < candidate + bytes) and
                       (regionEnd(other^.base_addr, other^.length) > candidate) then begin
                        nextCandidate := (regionEnd(other^.base_addr, other^.length) + FRAME_SIZE - 1) and not uint64(FRAME_SIZE - 1);
                        break;
                    end;
                    other := nextEntry(other);
                end;
                if nextCandidate = candidate then begin
                    metadataAddress := candidate;
                    exit;
                end;
                candidate := nextCandidate; { strictly advances across a reserved interval }
            end;
        end;
        e := nextEntry(e);
    end;
end;

procedure init(info: Pmultiboot_info_t);
var
    e: Pmemory_map_t;
    limit, bytes, storage: uint64;
    i, entries: uint32;
    modules: Pmodule_t;
    sections: PtrUInt;
    sectionAddress, sectionBytes: uint64;
begin
    if (info = nil) or ((info^.flags and (1 shl 6)) = 0) then fail('memory map missing');
    if (info^.mmap_length = 0) or (info^.mmap_length > $100000) or
       (uint64(info^.mmap_addr) + info^.mmap_length > $100000000) then fail('invalid map length');
    mapStart := info^.mmap_addr;
    mapEnd := mapStart + info^.mmap_length;
    limit := 0;
    entries := 0;
    e := Pmemory_map_t(mapStart);
    while PtrUInt(e) < mapEnd do begin
        if (mapEnd - PtrUInt(e) < 24) or (e^.size < 20) or
           (uint64(e^.size) + 4 > mapEnd - PtrUInt(e)) then fail('malformed map entry');
        inc(entries);
        if entries > 4096 then fail('too many map entries');
        if (e^.mtype = 1) and (e^.length <> 0) and (e^.base_addr < MAX_MANAGED) then
            if regionEnd(e^.base_addr, e^.length) > limit then limit := regionEnd(e^.base_addr, e^.length);
        e := nextEntry(e);
    end;
    frameCount := limit div FRAME_SIZE;
    if frameCount = 0 then fail('no usable RAM');
    reservedEnd := $1000000; { legacy low-memory devices and firmware }
    preserve(0, PtrUInt(@kernelEnd));
    preserve(PtrUInt(info), 4096);
    preserve(mapStart, info^.mmap_length);
    if (info^.flags and (1 shl 2)) <> 0 then preserve(info^.cmdline, 4096);
    if (info^.flags and (1 shl 9)) <> 0 then preserve(info^.boot_loader_name, 4096);
    if (info^.flags and (1 shl 3)) <> 0 then begin
        if info^.mods_count > 4096 then fail('too many boot modules');
        preserve(info^.mods_addr, uint64(info^.mods_count) * sizeof(module_t));
        modules := Pmodule_t(PtrUInt(info^.mods_addr));
        if info^.mods_count > 0 then for i := 0 to info^.mods_count - 1 do begin
            if modules[i].mod_end < modules[i].mod_start then fail('invalid module range');
            preserve(modules[i].mod_start, modules[i].mod_end - modules[i].mod_start);
            if modules[i].name <> 0 then preserve(modules[i].name, 4096);
        end;
    end;
    if (info^.flags and (1 shl 4)) <> 0 then
        preserve(info^.elf_sec.addr, uint64(info^.elf_sec.num) + info^.elf_sec.size);
    if (info^.flags and (1 shl 5)) <> 0 then begin
        if (info^.elf_sec.num > 4096) or
           ((info^.elf_sec.size <> 40) and (info^.elf_sec.size <> 64)) then fail('invalid ELF sections');
        preserve(info^.elf_sec.addr, uint64(info^.elf_sec.num) * info^.elf_sec.size);
        sections := info^.elf_sec.addr;
        if info^.elf_sec.num > 0 then for i := 0 to info^.elf_sec.num - 1 do begin
            if info^.elf_sec.size = 64 then begin
                sectionAddress := PUInt64(sections + 16)^;
                sectionBytes := PUInt64(sections + 32)^;
            end else begin
                sectionAddress := PUInt32(sections + 12)^;
                sectionBytes := PUInt32(sections + 20)^;
            end;
            if (sectionAddress <> 0) and (sectionBytes <> 0) then preserve(sectionAddress, sectionBytes);
            inc(sections, info^.elf_sec.size);
        end;
    end;
    reservedEnd := (reservedEnd + FRAME_SIZE - 1) and not uint64(FRAME_SIZE - 1);
    wordCount := (frameCount + 31) div 32;
    bytes := (uint64(wordCount) * 8 + FRAME_SIZE - 1) and not uint64(FRAME_SIZE - 1);
    storage := metadataAddress(bytes);
    if storage = 0 then fail('no low RAM for frame metadata');
    eligible := PUInt32(PtrUInt(storage));
    used := PUInt32(PtrUInt(storage + uint64(wordCount) * 4));
    zero(eligible, bytes);
    freeFrames := 0;
    e := Pmemory_map_t(mapStart);
    while PtrUInt(e) < mapEnd do begin
        if e^.mtype = 1 then setAvailable(e^.base_addr, e^.length, true);
        e := nextEntry(e);
    end;
    e := Pmemory_map_t(mapStart);
    while PtrUInt(e) < mapEnd do begin
        if e^.mtype <> 1 then setAvailable(e^.base_addr, e^.length, false);
        e := nextEntry(e);
    end;
    totalFrames := freeFrames;
    setAvailable(0, reservedEnd, false);
    setAvailable(storage, bytes, false);
    hint := 0;
    field('PMM_FREE_FRAMES', freeFrames);
    field('PMM_MANAGED_LIMIT', uint64(frameCount) * FRAME_SIZE);
    field('PMM_METADATA', storage);
end;

function allocateBetween(first, last: uint32): uint64;
var
    saved: PtrUInt;
    pass, start, finish, idx, bits, mask, bit: uint32;
begin
    allocateBetween := 0;
    saved := lockIRQ;
    if last > frameCount then last := frameCount;
    if first < last then begin
        start := hint;
        if (start < first) or (start >= last) then start := first;
        finish := last;
        for pass := 0 to 1 do begin
            idx := start;
            while idx < finish do begin
                bits := eligible[idx shr 5] and not used[idx shr 5];
                bits := bits and ($FFFFFFFF shl (idx and 31));
                if bits <> 0 then begin
                    bit := 0;
                    while (bits and (uint32(1) shl bit)) = 0 do inc(bit);
                    idx := (idx and not uint32(31)) + bit;
                    if idx >= finish then break;
                    mask := uint32(1) shl bit;
                    used[idx shr 5] := used[idx shr 5] or mask;
                    dec(freeFrames);
                    hint := idx + 1;
                    allocateBetween := uint64(idx) * FRAME_SIZE;
                    unlockIRQ(saved);
                    exit;
                end;
                idx := (idx and not uint32(31)) + 32;
            end;
            finish := start;
            start := first;
        end;
    end;
    unlockIRQ(saved);
end;

function alloc_page(lowOnly: boolean): uint64;
begin
    if lowOnly then alloc_page := allocateBetween(0, $100000)
    else alloc_page := allocateBetween(0, frameCount);
end;

function alloc_high: uint64;
begin
    alloc_high := allocateBetween($100000, frameCount);
end;

function free_page(address: uint64): boolean;
var
    idx, mask: uint32;
    saved: PtrUInt;
begin
    free_page := false;
    if (address and (FRAME_SIZE - 1) <> 0) or (address div FRAME_SIZE >= frameCount) then exit;
    saved := lockIRQ;
    idx := address div FRAME_SIZE;
    mask := uint32(1) shl (idx and 31);
    if ((eligible[idx shr 5] and used[idx shr 5]) and mask) <> 0 then begin
        used[idx shr 5] := used[idx shr 5] and not mask;
        inc(freeFrames);
        if idx < hint then hint := idx;
        free_page := true;
    end;
    unlockIRQ(saved);
end;

function reserve_range(address, bytes: uint64): boolean;
var
    first, last, i: uint32;
    saved: PtrUInt;
begin
    reserve_range := false;
    if (bytes = 0) or (address >= MAX_MANAGED) or (bytes > MAX_MANAGED - address) then exit;
    first := address div FRAME_SIZE;
    last := (address + bytes + FRAME_SIZE - 1) div FRAME_SIZE;
    if last > frameCount then last := frameCount;
    saved := lockIRQ;
    if first < last then for i := first to last - 1 do
        if (used[i shr 5] and (uint32(1) shl (i and 31))) <> 0 then begin
            unlockIRQ(saved);
            exit;
        end;
    setAvailable(address, bytes, false);
    reserve_range := true;
    unlockIRQ(saved);
end;

function free_count: uint64;
begin
    free_count := freeFrames;
end;

function total_count: uint64;
begin
    total_count := totalFrames;
end;

procedure UnitTest;
var
    before, a, b: uint64;
    passed, failed: uint32;

    procedure Assert(condition: boolean; name: pchar);
    begin
        if condition then begin
            inc(passed);
            puts('PASS: ');
        end
        else begin
            inc(failed);
            puts('FAIL: ');
        end;
        puts(name);
        puts(#13#10);
    end;
begin
    passed := 0;
    failed := 0;
    before := free_count;
    a := alloc_page(true);
    b := alloc_page(true);
    Assert((a <> 0) and (b <> 0) and (a <> b) and (a >= reservedEnd) and
        (b >= reservedEnd), 'PMM unique usable frames exclude boot reservations');
    Assert(not free_page(0) and not free_page(a + 1), 'PMM rejects reserved/unaligned frees');
    Assert(free_page(a) and free_page(b), 'PMM releases owned frames');
    Assert(not free_page(a), 'PMM rejects double free');
    Assert(free_count = before, 'PMM free-frame accounting restored');
    field('PMM_TESTS_FAILED', failed);
    if failed <> 0 then bootstrap_halt;
end;
end.
