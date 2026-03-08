{ Compatibility shim: wasuro references the old unit name 'lmemorymanager'.
  Since wasuro/ cannot be modified, this unit re-exports the public API of
  memory.heap so that 'uses lmemorymanager' continues to compile. }
unit lmemorymanager;

interface

uses
    memory.heap;

const
    ALLOC_UNIT        = memory.heap.ALLOC_UNIT;
    DATA_OFFSET       = memory.heap.DATA_OFFSET;
    PAGE_SIZE_LMM     = memory.heap.PAGE_SIZE_LMM;
    TOTAL_UNITS       = memory.heap.TOTAL_UNITS;
    BITMAP_DWORDS     = memory.heap.BITMAP_DWORDS;
    SIZE_PREFIX       = memory.heap.SIZE_PREFIX;
    LARGE_ALLOC_MAGIC = memory.heap.LARGE_ALLOC_MAGIC;

type
    PHeapPageHeader = memory.heap.PHeapPageHeader;
    THeapPageHeader = memory.heap.THeapPageHeader;

procedure init;
function kalloc(size : uint32) : void;
function klalloc(size : uint32) : void;
procedure klfree(address : uint32);
function kpalloc(address : uint32) : void;
procedure kfree(area : void);
function lmm_total_free : uint32;
function lmm_page_count : uint32;

implementation

procedure init;
begin
    memory.heap.init;
end;

function kalloc(size : uint32) : void; inline;
begin
    kalloc := memory.heap.kalloc(size);
end;

function klalloc(size : uint32) : void; inline;
begin
    klalloc := memory.heap.klalloc(size);
end;

procedure klfree(address : uint32); inline;
begin
    memory.heap.klfree(address);
end;

function kpalloc(address : uint32) : void; inline;
begin
    kpalloc := memory.heap.kpalloc(address);
end;

procedure kfree(area : void); inline;
begin
    memory.heap.kfree(area);
end;

function lmm_total_free : uint32; inline;
begin
    lmm_total_free := memory.heap.lmm_total_free;
end;

function lmm_page_count : uint32; inline;
begin
    lmm_page_count := memory.heap.lmm_page_count;
end;

end.
