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
    PMemoryManager - Physical Memory Management (Bitmap Refactor)

    Manages 1024 × 4 MiB physical blocks (= 4 GiB addressable).
    Each block is tracked by a single bit in two 1024-bit bitmaps:

      PhysPresent  – bit set = block exists in physical RAM
      PhysAlloc    – bit set = block is allocated

    A free block has its PhysPresent bit set and PhysAlloc bit clear.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit pmemorymanager;

interface

uses
    util,
    syslog,
    multiboot,
    tracer;

{ Public interface — signatures unchanged from the original unit }
procedure init;
function alloc_block(block : uint16; caller : uint32) : boolean;
procedure force_alloc_block(block : uint16; caller : uint32);
function new_block(caller : uint32) : uint16;
procedure free_block(block : uint16; caller : uint32);

{ New: query helpers for observability }
function pmm_free_blocks : uint32;
function pmm_total_blocks : uint32;

implementation

const
    BLOCK_COUNT = 1024;         { total 4 MiB blocks (covers 4 GiB) }
    DWORD_COUNT = BLOCK_COUNT div 32;   { 32 dwords = 1024 bits }
    RESERVED_LO = 0;           { first reserved block (inclusive) }
    RESERVED_HI = 3;           { last reserved block (inclusive) — kernel/BIOS }

var
    { Bit set = block physically present (from multiboot memory map) }
    PhysPresent : array[0..DWORD_COUNT-1] of uint32;
    { Bit set = block allocated }
    PhysAlloc   : array[0..DWORD_COUNT-1] of uint32;
    { Tracks which blocks have been scanned during memory map walk
      (handles overlapping/conflicting regions — first non-available wins) }
    PhysScanned : array[0..DWORD_COUNT-1] of uint32;
    { Owner tracking — only updated, never used for allocation decisions.
      Kept for diagnostic / free_block caller validation. }
    PhysOwner   : array[0..BLOCK_COUNT-1] of uint32;
    { Roving hint for new_block — start scanning from here }
    NextFreeHint : uint16;
    { Cached count of present blocks (set during init) }
    nPresent     : uint32;

{ ---- Inline bitmap helpers ---- }

function bit_test(var bmp: array of uint32; idx: uint16): boolean; inline;
begin
    bit_test := (bmp[idx shr 5] and (uint32(1) shl (idx and 31))) <> 0;
end;

procedure bit_set(var bmp: array of uint32; idx: uint16); inline;
begin
    bmp[idx shr 5] := bmp[idx shr 5] or (uint32(1) shl (idx and 31));
end;

procedure bit_clear(var bmp: array of uint32; idx: uint16); inline;
begin
    bmp[idx shr 5] := bmp[idx shr 5] and not (uint32(1) shl (idx and 31));
end;

{ popcount32 — count set bits in a 32-bit word (Hamming weight) }
function popcount32(x: uint32): uint32;
begin
    x := x - ((x shr 1) and $55555555);
    x := (x and $33333333) + ((x shr 2) and $33333333);
    x := (x + (x shr 4)) and $0F0F0F0F;
    x := x + (x shr 8);
    x := x + (x shr 16);
    popcount32 := x and $3F;
end;

{ ---- Memory map walking ---- }

procedure set_memory_area_present(base: uint64; len: uint64; present: boolean);
var
    first, last, i: uint32;
begin
    push_trace('pmemorymanager.set_memory_area_present');
    first := base shr 22;
    last  := (base + len) shr 22;
    { Clamp to valid range }
    if first > (BLOCK_COUNT - 1) then begin pop_trace; exit; end;
    if last  > (BLOCK_COUNT - 1) then last := BLOCK_COUNT - 1;
    for i := first to last do begin
        if not present then begin
            { Non-available region always wins — mark scanned + not present }
            bit_set(PhysScanned, i);
            bit_clear(PhysPresent, i);
        end else begin
            { Available region only applies if not already scanned }
            if not bit_test(PhysScanned, i) then begin
                bit_set(PhysScanned, i);
                bit_set(PhysPresent, i);
            end;
        end;
    end;
    pop_trace;
end;

procedure walk_memory_map;
var
    mmap    : Pmemory_map_t;
    address : uint32;
    len     : uint32;
    i       : uint16;
begin
    push_trace('pmemorymanager.walk_memory_map');
    address := multibootinfo^.mmap_addr + KERNEL_VIRTUAL_BASE;
    len     := multibootinfo^.mmap_length;
    mmap    := Pmemory_map_t(address);

    { Clear all bitmaps }
    for i := 0 to DWORD_COUNT - 1 do begin
        PhysPresent[i] := 0;
        PhysAlloc[i]   := 0;
        PhysScanned[i] := 0;
    end;
    for i := 0 to BLOCK_COUNT - 1 do
        PhysOwner[i] := 0;

    { Walk multiboot memory map entries }
    while uint32(mmap) < (address + len) do begin
        if mmap^.mtype = $01 then
            set_memory_area_present(mmap^.base_addr, mmap^.length, true)
        else
            set_memory_area_present(mmap^.base_addr, mmap^.length, false);
        mmap := Pmemory_map_t(uint32(mmap) + mmap^.size + sizeof(mmap^.size));
    end;

    { Count present blocks }
    nPresent := 0;
    for i := 0 to DWORD_COUNT - 1 do
        nPresent := nPresent + popcount32(PhysPresent[i]);

    pop_trace;
end;

{ ---- Public API ---- }

procedure force_alloc_block(block: uint16; caller: uint32);
begin
    push_trace('pmemorymanager.force_alloc_block');
    if block < BLOCK_COUNT then begin
        bit_set(PhysAlloc, block);
        PhysOwner[block] := caller;
    end;
    pop_trace;
end;

procedure init;
begin
    push_trace('pmemorymanager.init');
    syslog.logln('PMM', 'INIT BEGIN.');
    walk_memory_map;
    { Reserve first 16 MiB for kernel / BIOS }
    force_alloc_block(0, 0);
    force_alloc_block(1, 0);
    force_alloc_block(2, 0);
    force_alloc_block(3, 0);
    { Start scanning from block 4 (first potentially free block) }
    NextFreeHint := RESERVED_HI + 1;
    syslog.log('PMM', ' ');
    syslog.writeint(nPresent);
    syslog.writestringln('/1024 Blocks Available for Allocation.');
    syslog.log('PMM', ' Free: ');
    syslog.writeint(pmm_free_blocks);
    syslog.writestringln(' blocks.');
    syslog.logln('PMM', 'INIT END.');
    pop_trace;
end;

function alloc_block(block: uint16; caller: uint32): boolean;
begin
    push_trace('pmemorymanager.alloc_block');
    alloc_block := false;
    if block >= BLOCK_COUNT then begin
        GPF;
        pop_trace;
        exit;
    end;
    if not bit_test(PhysPresent, block) then begin
        GPF;
        pop_trace;
        exit;
    end;
    if bit_test(PhysAlloc, block) then begin
        { Already allocated }
        pop_trace;
        exit;
    end;
    bit_set(PhysAlloc, block);
    PhysOwner[block] := caller;
    alloc_block := true;
    pop_trace;
end;

function new_block(caller: uint32): uint16;
var
    i      : uint16;
    dw     : uint16;
    bits   : uint32;
    bit    : uint16;
    idx    : uint16;
begin
    push_trace('pmemorymanager.new_block');
    new_block := 0;

    { Scan from NextFreeHint, wrapping around once }
    i := NextFreeHint;
    if i < (RESERVED_HI + 1) then i := RESERVED_HI + 1;

    while i < BLOCK_COUNT do begin
        { Skip to the dword containing bit i and scan at dword granularity }
        dw := i shr 5;
        { Free & present bits: present AND (NOT alloc) }
        bits := PhysPresent[dw] and (not PhysAlloc[dw]);
        { Mask out bits below our starting position within this dword }
        bits := bits and (not ((uint32(1) shl (i and 31)) - 1));
        if bits <> 0 then begin
            { Find lowest set bit — manual bit scan forward }
            bit := 0;
            while (bits and (uint32(1) shl bit)) = 0 do
                inc(bit);
            idx := (dw shl 5) or bit;
            if idx >= (RESERVED_HI + 1) then begin
                bit_set(PhysAlloc, idx);
                PhysOwner[idx] := caller;
                NextFreeHint := idx + 1;
                new_block := idx;
                pop_trace;
                exit;
            end;
        end;
        { Advance to next dword boundary }
        i := ((i shr 5) + 1) shl 5;
    end;

    { Wrap around: scan from first non-reserved block to original hint }
    i := RESERVED_HI + 1;
    while i < NextFreeHint do begin
        dw := i shr 5;
        bits := PhysPresent[dw] and (not PhysAlloc[dw]);
        bits := bits and (not ((uint32(1) shl (i and 31)) - 1));
        if bits <> 0 then begin
            bit := 0;
            while (bits and (uint32(1) shl bit)) = 0 do
                inc(bit);
            idx := (dw shl 5) or bit;
            if (idx >= (RESERVED_HI + 1)) and (idx < NextFreeHint) then begin
                bit_set(PhysAlloc, idx);
                PhysOwner[idx] := caller;
                NextFreeHint := idx + 1;
                new_block := idx;
                pop_trace;
                exit;
            end;
        end;
        i := ((i shr 5) + 1) shl 5;
    end;

    { OOM — no free block found. Return 0 as sentinel. }
    syslog.logln('PMM', 'ERROR: Out of physical memory!');
    pop_trace;
end;

procedure free_block(block: uint16; caller: uint32);
begin
    push_trace('pmemorymanager.free_block');
    if block >= BLOCK_COUNT then begin
        GPF;
        pop_trace;
        exit;
    end;
    if block <= RESERVED_HI then begin
        GPF;
        pop_trace;
        exit;
    end;
    if not bit_test(PhysPresent, block) then begin
        GPF;
        pop_trace;
        exit;
    end;
    if not bit_test(PhysAlloc, block) then begin
        { Double-free detected }
        syslog.logln('PMM', 'WARNING: Double-free on block!');
        GPF;
        pop_trace;
        exit;
    end;
    if PhysOwner[block] <> caller then begin
        GPF;
        pop_trace;
        exit;
    end;
    bit_clear(PhysAlloc, block);
    PhysOwner[block] := 0;
    { Update hint if this freed block is earlier }
    if block < NextFreeHint then
        NextFreeHint := block;
    pop_trace;
end;

{ ---- Statistics ---- }

function pmm_free_blocks: uint32;
var
    i: uint16;
begin
    pmm_free_blocks := 0;
    for i := 0 to DWORD_COUNT - 1 do
        pmm_free_blocks := pmm_free_blocks + popcount32(PhysPresent[i] and (not PhysAlloc[i]));
end;

function pmm_total_blocks: uint32;
begin
    pmm_total_blocks := nPresent;
end;

end.