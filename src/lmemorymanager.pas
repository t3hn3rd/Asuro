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
    LMemoryManager - Logical (Heap) Memory Management (Bitmap Refactor)

    Provides kalloc/kfree for kernel heap allocation.  Each heap page is a
    4 MiB virtual region obtained from the VMM.  Within each page a bitmap
    tracks which 8-byte allocation units are free or allocated.

    Layout of a 4 MiB heap page:
      [0x000000..0x000017]  THeapPageHeader   (24 bytes)
      [0x000018..0x00FC17]  Bitmap            (64512 bytes = 516096 bits)
      [0x00FC18..0x00FFFF]  Padding           (1000 bytes)
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
unit lmemorymanager;

interface

uses
    util,
    vmemorymanager,
    pmemorymanager,
    syslog,
    tracer;

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
function kalloc(size : uint32) : void;
function klalloc(size : uint32) : void;
procedure klfree(address : uint32);
function kpalloc(address : uint32) : void;
procedure kfree(area : void);

{ Statistics }
function lmm_total_free : uint32;
function lmm_page_count : uint32;

implementation

{ ==== Internal helpers ==== }

function get_bitmap(hp: PHeapPageHeader): PuInt32; inline;
begin
    get_bitmap := PuInt32(uint32(hp) + uint32(sizeof(THeapPageHeader)));
end;

function get_data_base(hp: PHeapPageHeader): uint32; inline;
begin
    get_data_base := uint32(hp) + DATA_OFFSET;
end;

{ Zero a memory region using rep stosd + rep stosb. }
procedure zero_mem(dest: Pointer; bytes: uint32);
var
    d: Pointer;
    b: uint32;
begin
    d := dest;
    b := bytes;
    if b = 0 then exit;
    asm
        push edi
        mov  edi, d
        mov  ecx, b
        shr  ecx, 2
        xor  eax, eax
        cld
        rep  stosd
        mov  ecx, b
        and  ecx, 3
        rep  stosb
        pop  edi
    end;
end;

{ Find a contiguous run of 'count' zero (free) bits in the bitmap
  starting at bit index 'start'.  Returns the starting index or -1. }
function find_free_run(bmp: PuInt32; start, count, total: uint32): sInt32;
var
    idx, run_len, dw_idx: uint32;
    dw: uint32;
begin
    find_free_run := -1;
    idx := start;
    while idx + count <= total do begin
        dw_idx := idx shr 5;
        dw := bmp[dw_idx];

        { Fast skip: entire dword fully allocated }
        if dw = $FFFFFFFF then begin
            idx := (dw_idx + 1) shl 5;
            continue;
        end;

        { Check if bit at idx is free (0) }
        if (dw and (uint32(1) shl (idx and 31))) <> 0 then begin
            inc(idx);
            continue;
        end;

        { Free bit at idx - verify contiguous run of 'count' }
        run_len := 0;
        while run_len < count do begin
            if idx + run_len >= total then break;
            if (bmp[(idx + run_len) shr 5] and
                (uint32(1) shl ((idx + run_len) and 31))) <> 0 then
                break;
            inc(run_len);
        end;

        if run_len >= count then begin
            find_free_run := sInt32(idx);
            exit;
        end;

        { Skip past the used bit that broke the run }
        idx := idx + run_len + 1;
    end;
end;

procedure bitmap_set_range(bmp: PuInt32; start, count: uint32);
var
    i: uint32;
begin
    for i := start to start + count - 1 do
        bmp[i shr 5] := bmp[i shr 5] or (uint32(1) shl (i and 31));
end;

procedure bitmap_clear_range(bmp: PuInt32; start, count: uint32);
var
    i: uint32;
begin
    for i := start to start + count - 1 do
        bmp[i shr 5] := bmp[i shr 5] and not (uint32(1) shl (i and 31));
end;

{ Check that all bits in a range are set (for double-free detection). }
function bitmap_all_set(bmp: PuInt32; start, count: uint32): boolean;
var
    i: uint32;
begin
    bitmap_all_set := true;
    for i := start to start + count - 1 do begin
        if (bmp[i shr 5] and (uint32(1) shl (i and 31))) = 0 then begin
            bitmap_all_set := false;
            exit;
        end;
    end;
end;

{ Restore interrupt flag if it was enabled before cli.
  Uses sti instead of popfd to avoid restoring dangerous EFLAGS bits
  (IOPL, NT, VM, AC) that could cause GPF or Bad-TSS on next IRET. }
procedure restore_if(saved: uint32); inline;
begin
    if (saved and $200) <> 0 then
        asm sti end;
end;

{ ==== Page management ==== }

function new_lmm_page: uint32;
var
    i: uint32;
begin
    push_trace('lmemorymanager.new_lmm_page');
    new_lmm_page := 0;
    i := KERNEL_PAGE_NUMBER + 4;
    while i < 1024 do begin
        if vmemorymanager.new_page(i) then begin
            new_lmm_page := i shl 22;
            pop_trace;
            exit;
        end;
        inc(i);
    end;
    syslog.logln('LMM', 'ERROR: new_lmm_page failed.');
    pop_trace;
end;

function new_heap_page(current: PHeapPageHeader): PHeapPageHeader;
var
    addr: uint32;
    bmp: PuInt32;
    i: uint32;
begin
    push_trace('lmemorymanager.new_heap_page');
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

    push_trace('lmemorymanager.try_release_page');

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
    vmemorymanager.free_page_at_address(uint32(hp));

    pop_trace;
end;

{ ==== Public API ==== }

procedure init;
begin
    push_trace('lmemorymanager.init');
    syslog.logln('LMM', 'INIT BEGIN.');
    Root_Page := new_heap_page(nil);
    Search_Page := Root_Page;
    if Root_Page = nil then begin
        syslog.logln('LMM', 'FATAL: Could not allocate root heap page!');
        GPF;
    end;
    syslog.logln('LMM', 'INIT END.');
    pop_trace;
end;

function kpalloc(address: uint32): void;
var
    block: uint16;
begin
    push_trace('lmemorymanager.kpalloc');
    block := address shr 22;
    if block >= 1024 then begin
        syslog.logln('LMM', 'ERROR: kpalloc block out of range.');
        GPF;
        kpalloc := nil;
        pop_trace;
        exit;
    end;
    syslog.log('LMM', 'kpalloc: identity-map block ');
    syslog.writeintln(block);
    force_alloc_block(block, 0);
    map_page(block, block);
    kpalloc := void(block shl 22);
    pop_trace;
end;

procedure klfree(address: uint32);
var
    page_num : uint16;
    num_pages : uint32;
    i : uint32;
begin
    push_trace('lmemorymanager.klfree');
    num_pages := PuInt32(address)^;
    if (num_pages = 0) or (num_pages > 256) then begin
        syslog.logln('LMM', 'ERROR: klfree invalid page count.');
        GPF;
        pop_trace;
        exit;
    end;
    page_num := address shr 22;
    for i := 0 to num_pages - 1 do
        vmemorymanager.free_page(page_num + uint16(i));
    pop_trace;
end;

function klalloc(size: uint32): void;
var
    total_size : uint32;
    pages      : uint32;
    curr_page  : uint16;
    i          : uint16;
    miss       : boolean;
    base_addr  : uint32;
begin
    push_trace('lmemorymanager.klalloc');
    klalloc := void(nil);

    { Need extra 16 bytes for header: [page_count:4][magic:4][pad:8] }
    total_size := size + 16;
    pages := (total_size + PAGE_SIZE_LMM - 1) div PAGE_SIZE_LMM;
    if pages = 0 then pages := 1;

    { Scan low virtual pages (below kernel space) for contiguous free range }
    curr_page := 5;
    while uint32(curr_page) + pages - 1 < KERNEL_PAGE_NUMBER do begin
        miss := false;
        for i := 0 to pages - 1 do begin
            if not page_mappable(curr_page + i) then begin
                miss := true;
                curr_page := curr_page + i;
                break;
            end;
        end;
        if not miss then begin
            for i := 0 to pages - 1 do
                vmemorymanager.new_page(curr_page + i);
            base_addr := uint32(curr_page) shl 22;
            zero_mem(Pointer(base_addr), 16);
            { Header: [page_count:4][magic:4][pad:8] → user at +16 (16-aligned) }
            PuInt32(base_addr)^ := pages;
            PuInt32(base_addr + 4)^ := LARGE_ALLOC_MAGIC;
            klalloc := void(base_addr + 16);
            pop_trace;
            exit;
        end;
        inc(curr_page);
    end;

    syslog.logln('LMM', 'ERROR: klalloc no contiguous pages.');
    pop_trace;
end;

function kalloc(size: uint32): void; [public, alias: 'kernel_kalloc'];
var
    units_needed : uint32;
    hp           : PHeapPageHeader;
    bmp          : PuInt32;
    idx          : sInt32;
    alloc_base   : uint32;
    saved_flags  : uint32;
begin
    { Disable interrupts - save EFLAGS to local then cli.
      Uses pushfd;cli;pop (stack-balanced) instead of bare pushfd/popfd
      across the function, which is unsafe because FPC does not track
      stack pointer changes inside asm blocks. }
    asm
        pushfd
        cli
        pop saved_flags
    end;

    kalloc := nil;

    if size = 0 then begin
        restore_if(saved_flags);
        exit;
    end;

    { Units needed: user size + 8-byte prefix, rounded up to ALLOC_UNIT }
    units_needed := (size + SIZE_PREFIX + ALLOC_UNIT - 1) div ALLOC_UNIT;
    {$IFDEF DEBUG_LMM}
    inc(units_needed); { extra unit for guard sentinel }
    {$ENDIF}

    { Large allocations that exceed a single heap page }
    if units_needed > TOTAL_UNITS then begin
        kalloc := klalloc(size);
        if kalloc = nil then begin
            restore_if(saved_flags);
            BSOD('OOM', 'kalloc: large allocation failed');
            exit;
        end;
        zero_mem(Pointer(kalloc), size);
        restore_if(saved_flags);
        exit;
    end;

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
                BSOD('OOM', 'kalloc: out of memory');
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
    alloc_base  : uint32;
    unit_idx    : uint32;
    base        : uint32;
    saved_flags : uint32;
begin
    if area = nil then exit;

    { Disable interrupts - stack-balanced save to local variable }
    asm
        pushfd
        cli
        pop saved_flags
    end;

    { Check for large allocation: magic sentinel at area - 12
      (klalloc header is [page_count:4][MAGIC:4][pad:8][user_data]) }
    if PuInt32(uint32(area) - 12)^ = LARGE_ALLOC_MAGIC then begin
        base := uint32(area) - 16;
        klfree(base);
        restore_if(saved_flags);
        exit;
    end;

    { Read the size prefix (SIZE_PREFIX bytes before the returned pointer) }
    prefix_val := PuInt32(uint32(area) - SIZE_PREFIX)^;

    { Normal heap allocation }
    hp := PHeapPageHeader((uint32(area) shr 22) shl 22);
    bmp := get_bitmap(hp);

    { Compute allocation base and unit index }
    alloc_base := uint32(area) - SIZE_PREFIX;
    unit_idx := (alloc_base - get_data_base(hp)) div ALLOC_UNIT;

    { Bounds check }
    if (prefix_val = 0) or (unit_idx + prefix_val > hp^.TotalUnits) then begin
        syslog.logln('LMM', 'ERROR: kfree invalid range.');
        GPF;
        restore_if(saved_flags);
        exit;
    end;

    {$IFDEF DEBUG_LMM}
    { Guard byte overrun detection }
    if PuInt32(alloc_base + prefix_val * ALLOC_UNIT - 4)^ <> GUARD_MAGIC then begin
        syslog.logln('LMM', 'ERROR: kfree guard corrupted - buffer overrun!');
        GPF;
        restore_if(saved_flags);
        exit;
    end;
    {$ENDIF}

    { Double-free detection }
    if not bitmap_all_set(bmp, unit_idx, prefix_val) then begin
        syslog.logln('LMM', 'ERROR: kfree double free!');
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

function lmm_total_free: uint32;
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

end.