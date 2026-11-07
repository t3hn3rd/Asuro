//  Copyright 2021 Kieron Morris
//  Copyright 2026 Aaron Hance
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
    LMemoryManager - Logical (Heap) Memory Management (Bitmap Refactor)

    Provides kalloc/kfree for core.version heap allocation.  Each heap page is a
    4 MiB virtual region obtained from the VMM.  Within each page a bitmap
    tracks which 8-byte allocation units are free or allocated.

    Layout of a 4 MiB heap page:
      Header: 24 bytes on i386, 32 bytes on x86_64
      Bitmap: 64512 bytes immediately following the header
      Padding: remainder of the first 64 KiB
      [0x010000..0x3FFFFF]  Data area         (4128768 bytes = 516096 x 8)

    Each allocation prepends a 16-byte size prefix (4 bytes for the unit
    count + 12 bytes padding) so that kfree can determine the allocation
    size and the returned pointer is naturally 16-byte aligned (required
    for SSE 128-bit operations).

    Large allocations (> single page capacity) are served by klalloc which
    maps contiguous virtual pages and stores a magic sentinel so kfree can
    identify them.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit memory.heap;

interface

uses memory.bitmap;

const
    ALLOC_UNIT        = 8;          { bytes per allocation unit }
    DATA_OFFSET       = $10000;     { 64 KiB - data area starts here }
    PAGE_SIZE_LMM     = $400000;    { 4 MiB per heap page }
    TOTAL_UNITS       = (PAGE_SIZE_LMM - DATA_OFFSET) div ALLOC_UNIT; { 516096 }
    BITMAP_DWORDS     = (TOTAL_UNITS + 31) div 32;                    { 16128 }
    SIZE_PREFIX       = 16;         { 16-byte prefix per alloc (4B size + 12B pad for 16-byte alignment) }
    LARGE_ALLOC_MAGIC = $FFFFFFFE;  { sentinel for klalloc'd memory }
    {$IFDEF DEBUG_LMM}
    GUARD_MAGIC       = $DEADBEEF;  { guard sentinel for overrun detection }
    {$ENDIF}

type
    PHeapPageHeader = ^THeapPageHeader;
    THeapPageHeader = packed record
        NextPage   : PHeapPageHeader;
        PrevPage   : PHeapPageHeader;
        FreeUnits  : uint32;
        NextFree   : uint32;
        TotalUnits : uint32;
        Reserved   : uint32;
    end;

var
    Root_Page   : PHeapPageHeader;
    Search_Page : PHeapPageHeader;

procedure init;
procedure UnitTest;
function kalloc(size : SizeUInt) : void;
function klalloc(size : SizeUInt) : void;
procedure klfree(address : PtrUInt);
function kpalloc(address : PtrUInt) : void;
procedure kfree(area : void);

{ Statistics }
function lmm_total_free : SizeUInt;
function lmm_page_count : uint32;

implementation

uses arch.platform.memory, arch.platform.cpu, arch.platform.diagnostics;
procedure GPF;
begin fatal('LMM', 'FAIL: heap invariant'); end;
procedure heap_log(message: pchar);
begin arch.platform.diagnostics.log('LMM', message); end;
procedure heap_oom(message: pchar);
begin fatal('OOM', message); end;

{ ==== Internal helpers ==== }

function get_bitmap(hp: PHeapPageHeader): PuInt32; inline;
begin
    get_bitmap := PuInt32(PtrUInt(hp) + uint32(sizeof(THeapPageHeader)));
end;

function get_data_base(hp: PHeapPageHeader): PtrUInt; inline;
begin
    get_data_base := PtrUInt(hp) + DATA_OFFSET;
end;

procedure zero_mem(dest: Pointer; bytes: SizeUInt);
begin arch.platform.cpu.zero(dest, bytes); end;
procedure restore_if(saved: PtrUInt); inline;
begin arch.platform.cpu.unlock(saved); end;

{ ==== Page management ==== }

function new_lmm_page: PtrUInt;
begin new_lmm_page := arch.platform.memory.allocateHeapPage; end;

function new_heap_page(current: PHeapPageHeader): PHeapPageHeader;
var
    addr: PtrUInt;
    bmp: PuInt32;
    i: uint32;
begin
    push_trace('memory.heap.new_heap_page');
    addr := new_lmm_page;
    if addr = 0 then begin
        new_heap_page := nil;
        pop_trace;
        exit;
    end;
    new_heap_page := PHeapPageHeader(addr);
    { Link into list }
    if current <> nil then
        current^.NextPage := new_heap_page;
    new_heap_page^.NextPage   := nil;
    new_heap_page^.PrevPage   := current;
    new_heap_page^.FreeUnits  := TOTAL_UNITS;
    new_heap_page^.NextFree   := 0;
    new_heap_page^.TotalUnits := TOTAL_UNITS;
    new_heap_page^.Reserved   := 0;

    { Clear bitmap: all zero = all free }
    bmp := get_bitmap(new_heap_page);
    for i := 0 to BITMAP_DWORDS - 1 do
        bmp[i] := 0;

    pop_trace;
end;

{ Release a completely-free heap page back to VMM/PMM. }
procedure try_release_page(hp: PHeapPageHeader);
begin
    if hp = Root_Page then exit;
    if hp^.FreeUnits <> hp^.TotalUnits then exit;

    push_trace('memory.heap.try_release_page');

    { Unlink from doubly-linked list }
    if hp^.PrevPage <> nil then
        hp^.PrevPage^.NextPage := hp^.NextPage;
    if hp^.NextPage <> nil then
        hp^.NextPage^.PrevPage := hp^.PrevPage;

    { Fix Search_Page if it points here }
    if Search_Page = hp then begin
        if hp^.PrevPage <> nil then
            Search_Page := hp^.PrevPage
        else
            Search_Page := Root_Page;
    end;

    { Free the virtual page (returns physical block to PMM) }
    arch.platform.memory.release(PtrUInt(hp), 1);

    pop_trace;
end;

{ ==== Public API ==== }

procedure init;
begin
    push_trace('memory.heap.init');
    heap_log('INIT BEGIN.');
    Root_Page := new_heap_page(nil);
    Search_Page := Root_Page;
    if Root_Page = nil then begin
        heap_log('FATAL: Could not allocate root heap page!');
        GPF;
    end;
    heap_log('INIT END.');
    pop_trace;
end;

function kpalloc(address: PtrUInt): void;
begin kpalloc := void(arch.platform.memory.identityReserve(address)); end;

procedure klfree(address: PtrUInt);
var
    num_pages : uint32;
begin
    push_trace('memory.heap.klfree');
    num_pages := PuInt32(address)^;
    if (num_pages = 0) or (num_pages > MAX_HEAP_REGIONS) then begin
        heap_log('ERROR: klfree invalid page count.');
        GPF;
        pop_trace;
        exit;
    end;
    arch.platform.memory.release(address, num_pages);
    pop_trace;
end;

function klalloc(size: SizeUInt): void;
var
    total_size : SizeUInt;
    pages      : uint32;
    base_addr  : PtrUInt;
begin
    push_trace('memory.heap.klalloc');
    klalloc := void(nil);

    { Need extra 16 bytes for header: [page_count:4][magic:4][pad:8] }
    if (size = 0) or (size > High(SizeUInt) - PAGE_SIZE_LMM - SIZE_PREFIX) then begin
        pop_trace; exit;
    end;
    total_size := size + 16;
    if ((total_size + PAGE_SIZE_LMM - 1) div PAGE_SIZE_LMM) > MAX_HEAP_REGIONS then begin
        pop_trace; exit;
    end;
    pages := (total_size + PAGE_SIZE_LMM - 1) div PAGE_SIZE_LMM;
    if pages = 0 then pages := 1;

    base_addr := arch.platform.memory.allocateLarge(pages);
    if base_addr <> 0 then begin
        zero_mem(Pointer(base_addr), SIZE_PREFIX);
        PuInt32(base_addr)^ := pages;
        PuInt32(base_addr + 4)^ := LARGE_ALLOC_MAGIC;
        klalloc := void(base_addr + SIZE_PREFIX);
        pop_trace; exit;
    end;

    heap_log('ERROR: klalloc no contiguous pages.');
    pop_trace;
end;

function kalloc(size: SizeUInt): void; [public, alias: 'kernel_kalloc'];
var
    units_needed : uint32;
    hp           : PHeapPageHeader;
    bmp          : PuInt32;
    idx          : sInt32;
    alloc_base   : PtrUInt;
    saved_flags  : PtrUInt;
begin
    { Disable interrupts - save EFLAGS to local then cli.
      Uses pushfd;cli;pop (stack-balanced) instead of bare pushfd/popfd
      across the function, which is unsafe because FPC does not track
      stack pointer changes inside asm blocks. }
    saved_flags := arch.platform.cpu.lock;

    kalloc := nil;

    if (size = 0) or (size > High(SizeUInt) - PAGE_SIZE_LMM - SIZE_PREFIX) then begin
        restore_if(saved_flags);
        exit;
    end;

    { Keep every allocation start 16-byte aligned, including odd sizes. }
    if size > TOTAL_UNITS * ALLOC_UNIT - SIZE_PREFIX - 16 then begin
        kalloc := klalloc(size);
        if kalloc = nil then begin
            restore_if(saved_flags);
            heap_oom('kalloc: large allocation failed');
            exit;
        end;
        zero_mem(Pointer(kalloc), size);
        restore_if(saved_flags);
        exit;
    end;

    units_needed := ((size + SIZE_PREFIX + {$IFDEF DEBUG_LMM}8 + {$ENDIF}15) div 16) * 2;

    hp := Search_Page;
    while true do begin
        { Only try pages with enough free units }
        if hp^.FreeUnits >= units_needed then begin
            bmp := get_bitmap(hp);
            { Search from roving hint }
            idx := find_free_run(bmp, hp^.NextFree, units_needed, hp^.TotalUnits);
            { Wrap around if needed }
            if (idx < 0) and (hp^.NextFree > 0) then
                idx := find_free_run(bmp, 0, units_needed, hp^.TotalUnits);

            if idx >= 0 then begin
                { Mark units as allocated }
                bitmap_set_range(bmp, uint32(idx), units_needed);
                hp^.FreeUnits := hp^.FreeUnits - units_needed;
                { Advance hint past this allocation }
                if uint32(idx) + units_needed < hp^.TotalUnits then
                    hp^.NextFree := uint32(idx) + units_needed
                else
                    hp^.NextFree := 0;

                { Write size prefix + zero padding for alignment.
                  Padding must not accidentally match LARGE_ALLOC_MAGIC. }
                alloc_base := get_data_base(hp) + uint32(idx) * ALLOC_UNIT;
                PuInt32(alloc_base)^ := units_needed;
                PuInt32(alloc_base + 4)^ := 0;
                kalloc := void(alloc_base + SIZE_PREFIX);

                { Zero the user-visible area }
                zero_mem(Pointer(kalloc), size);

                {$IFDEF DEBUG_LMM}
                { Write guard sentinel at end of allocated region }
                PuInt32(alloc_base + units_needed * ALLOC_UNIT - 4)^ := GUARD_MAGIC;
                {$ENDIF}

                Search_Page := hp;
                restore_if(saved_flags);
                exit;
            end;
        end;

        { Move to next page or allocate a new one }
        if hp^.NextPage = nil then begin
            hp := new_heap_page(hp);
            if hp = nil then begin
                restore_if(saved_flags);
                heap_oom('kalloc: out of memory');
                exit;
            end;
        end else begin
            hp := hp^.NextPage;
        end;
        Search_Page := hp;
    end;

    restore_if(saved_flags);
end;

procedure kfree(area: void); [public, alias: 'kernel_kfree'];
var
    hp          : PHeapPageHeader;
    bmp         : PuInt32;
    prefix_val  : uint32;
    alloc_base  : PtrUInt;
    unit_idx    : uint32;
    base        : PtrUInt;
    saved_flags : PtrUInt;
begin
    if area = nil then exit;

    { Disable interrupts - stack-balanced save to local variable }
    saved_flags := arch.platform.cpu.lock;

    { Check for large allocation: magic sentinel at area - 12
      (klalloc header is [page_count:4][MAGIC:4][pad:8][user_data]) }
    if PuInt32(PtrUInt(area) - 12)^ = LARGE_ALLOC_MAGIC then begin
        base := PtrUInt(area) - 16;
        klfree(base);
        restore_if(saved_flags);
        exit;
    end;

    { Read the size prefix (SIZE_PREFIX bytes before the returned pointer) }
    prefix_val := PuInt32(PtrUInt(area) - SIZE_PREFIX)^;

    { Normal heap allocation }
    hp := PHeapPageHeader((PtrUInt(area) shr 22) shl 22);
    bmp := get_bitmap(hp);

    { Compute allocation base and unit index }
    alloc_base := PtrUInt(area) - SIZE_PREFIX;
    unit_idx := (alloc_base - get_data_base(hp)) div ALLOC_UNIT;

    { Bounds check }
    if (prefix_val = 0) or (unit_idx >= hp^.TotalUnits) or
       (prefix_val > hp^.TotalUnits - unit_idx) then begin
        heap_log('ERROR: kfree invalid range.');
        GPF;
        restore_if(saved_flags);
        exit;
    end;

    {$IFDEF DEBUG_LMM}
    { Guard byte overrun detection }
    if PuInt32(alloc_base + prefix_val * ALLOC_UNIT - 4)^ <> GUARD_MAGIC then begin
        heap_log('ERROR: kfree guard corrupted - buffer overrun!');
        GPF;
        restore_if(saved_flags);
        exit;
    end;
    {$ENDIF}

    { Double-free detection }
    if not bitmap_all_set(bmp, unit_idx, prefix_val) then begin
        heap_log('ERROR: kfree double free!');
        GPF;
        restore_if(saved_flags);
        exit;
    end;

    { Clear the bitmap bits }
    bitmap_clear_range(bmp, unit_idx, prefix_val);
    hp^.FreeUnits := hp^.FreeUnits + prefix_val;

    { Update roving hint for better locality }
    if unit_idx < hp^.NextFree then
        hp^.NextFree := unit_idx;

    { If page is completely free, return it to VMM/PMM }
    try_release_page(hp);

    restore_if(saved_flags);
end;

{ ==== Statistics ==== }

function lmm_total_free: SizeUInt;
var
    hp: PHeapPageHeader;
begin
    lmm_total_free := 0;
    hp := Root_Page;
    while hp <> nil do begin
        lmm_total_free := lmm_total_free + hp^.FreeUnits * ALLOC_UNIT;
        hp := hp^.NextPage;
    end;
end;

function lmm_page_count: uint32;
var
    hp: PHeapPageHeader;
begin
    lmm_page_count := 0;
    hp := Root_Page;
    while hp <> nil do begin
        inc(lmm_page_count);
        hp := hp^.NextPage;
    end;
end;

procedure UnitTest;
var
    a, b, large: void;
    beforeFree: SizeUInt;
    beforeFrames: uint64;
    passed, failed: uint32;
    procedure Assert(condition: boolean; name: pchar);
    begin
        if condition then begin inc(passed); heap_log(name); end
        else begin inc(failed); heap_log('FAIL: heap test'); heap_log(name); end;
    end;
begin
    passed := 0; failed := 0;
    beforeFree := lmm_total_free;
    beforeFrames := arch.platform.memory.freeBacking;
    a := kalloc(1); b := kalloc(17);
    Assert((a <> nil) and (b <> nil) and ((PtrUInt(a) and 15) = 0) and
           ((PtrUInt(b) and 15) = 0), 'PASS: heap odd sizes remain 16-byte aligned');
    Assert((PUInt8(a)^ = 0) and (PUInt8(PtrUInt(b) + 16)^ = 0), 'PASS: heap allocation zeroed');
    PUInt8(a)^ := 123; PUInt8(PtrUInt(b) + 16)^ := 45;
    kfree(a); kfree(b); kfree(nil);
    a := kalloc(1);
    Assert(PUInt8(a)^ = 0, 'PASS: heap reused storage zeroed');
    kfree(a);
    large := kalloc(PAGE_SIZE_LMM + 17);
    Assert((large <> nil) and ((PtrUInt(large) and 15) = 0), 'PASS: heap large allocation aligned');
    PUInt8(large)^ := 87;
    PUInt8(PtrUInt(large) + PAGE_SIZE_LMM + 16)^ := 91;
    Assert((PUInt8(large)^ = 87) and (PUInt8(PtrUInt(large) + PAGE_SIZE_LMM + 16)^ = 91),
           'PASS: heap large allocation first/last bytes writable');
    kfree(large);
    Assert((kalloc(0) = nil) and (kalloc(High(SizeUInt)) = nil), 'PASS: heap rejects zero/overflow sizes');
    Assert((lmm_total_free = beforeFree) and (lmm_page_count = 1), 'PASS: heap free accounting restored');
    Assert(arch.platform.memory.freeBacking = beforeFrames, 'PASS: heap backing frames restored');
    arch.platform.diagnostics.testSummary('LMM', 'HEAP_TESTS_PASSED', 'HEAP_TESTS_FAILED', passed, failed);
    if failed <> 0 then GPF;
end;



end.