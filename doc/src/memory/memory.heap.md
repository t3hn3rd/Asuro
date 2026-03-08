# memory.heap

Bitmap-based kernel heap allocator providing `kalloc`, `kfree`, and large-allocation support.

## Overview

`memory.heap` implements the Asuro logical memory manager (LMM). The heap is organized as a singly/doubly-linked list of 4 MiB virtual pages, each managed by a bitmap that tracks 8-byte allocation units.

Each heap page has the following layout:

| Region | Offset | Size |
|---|---|---|
| `THeapPageHeader` | `0x000000` | 24 bytes |
| Bitmap | `0x000018` | 64,512 bytes (516,096 bits) |
| Padding | `0x00FC18` | 1,000 bytes |
| Data area | `0x010000` | 4,128,768 bytes (516,096 units × 8 bytes) |

Every allocation is preceded by a 16-byte prefix: 4 bytes for the unit count, 12 bytes of padding. This ensures the returned pointer is 16-byte aligned (required for SSE 128-bit operations) and allows `kfree` to recover the allocation size without a separate metadata structure.

Allocations larger than a single heap page's capacity are handled by `klalloc`, which maps contiguous virtual pages and stores a magic sentinel (`$FFFFFFFE`) in the header so `kfree` can identify them and call `klfree` instead of the normal bitmap path.

`kalloc` and `kfree` disable interrupts for the duration of their critical sections using a stack-balanced `pushfd`/`cli`/`pop` sequence and restore the interrupt flag via `restore_if` on all exit paths.

## Dependencies

- `arch.x86.memory.physical`
- `arch.x86.memory.virtual`
- `io.syslog`
- `debug.tracer`
- `core.util`, `arch.x86.util`
- `core.panic`

## Constants

| Constant | Value | Description |
|---|---|---|
| `ALLOC_UNIT` | `8` | Bytes per allocation unit |
| `DATA_OFFSET` | `$10000` (64 KiB) | Offset from page base to data area |
| `PAGE_SIZE_LMM` | `$400000` (4 MiB) | Size of each heap virtual page |
| `TOTAL_UNITS` | `516096` | Allocation units per page (`(PAGE_SIZE_LMM - DATA_OFFSET) / ALLOC_UNIT`) |
| `BITMAP_DWORDS` | `16128` | 32-bit words required to hold the bitmap |
| `SIZE_PREFIX` | `16` | Bytes prepended to every normal allocation |
| `LARGE_ALLOC_MAGIC` | `$FFFFFFFE` | Sentinel written at offset +4 in `klalloc` headers |
| `GUARD_MAGIC` | `$DEADBEEF` | Guard sentinel for overrun detection (debug builds only) |

## Types

### THeapPageHeader / PHeapPageHeader

```pascal
THeapPageHeader = packed record
    NextPage   : PHeapPageHeader;
    PrevPage   : PHeapPageHeader;
    FreeUnits  : uint32;
    NextFree   : uint32;
    TotalUnits : uint32;
    Reserved   : uint32;
end;
```

Located at the base address of each heap virtual page. `NextFree` is a roving hint that tracks the first bitmap index likely to contain free units, reducing average scan time for sequential allocations.

## Functions and Procedures

### init

```pascal
procedure init;
```

Allocates the first heap page via `new_heap_page`, sets `Root_Page` and `Search_Page` to it. Panics if the root page cannot be allocated.

### kalloc

```pascal
function kalloc(size: uint32): void;
```

Allocates `size` bytes from the heap. Returns a 16-byte-aligned pointer. Returns `nil` for zero-size requests. Delegates to `klalloc` for requests too large for a single page. Searches pages starting from `Search_Page` using the `NextFree` roving hint, allocating a new page if no existing page can satisfy the request. Calls `core.panic.panic` if the system is completely out of memory. The allocated region is zeroed before being returned.

### kfree

```pascal
procedure kfree(area: void);
```

Frees a previously allocated block. Detects large allocations by checking the magic sentinel at `area - 12` and delegates to `klfree` if found. For normal allocations, reads the unit count prefix, validates the range and double-free guard, clears the bitmap range, updates `FreeUnits` and `NextFree`, and calls `try_release_page` to return completely-free pages to the VMM.

### klalloc

```pascal
function klalloc(size: uint32): void;
```

Allocates `size` bytes by mapping contiguous virtual pages from the low virtual address range (page numbers 5 through `KERNEL_PAGE_NUMBER - 1`). Writes a header containing the page count and `LARGE_ALLOC_MAGIC` sentinel. Returns a pointer 16 bytes past the header. Returns `nil` if no contiguous range is available.

### klfree

```pascal
procedure klfree(address: uint32);
```

Frees a large allocation by reading the page count from the header at `address` and releasing each mapped virtual page back to the VMM. Validates the page count before proceeding.

### kpalloc

```pascal
function kpalloc(address: uint32): void;
```

Identity-maps a physical 4 MiB block at the specified address using `force_alloc_block` and `map_page`. Used for memory-mapped hardware regions that must appear at a fixed virtual address.

### lmm_total_free

```pascal
function lmm_total_free: uint32;
```

Returns the total free bytes across all heap pages by summing `FreeUnits * ALLOC_UNIT` for every page in the linked list.

### lmm_page_count

```pascal
function lmm_page_count: uint32;
```

Returns the number of heap pages currently in the linked list.

## Notes

The `restore_if` helper checks bit 9 (IF) of the saved EFLAGS word and issues `STI` only if interrupts were enabled on entry. It uses `STI` rather than `POPFD` to avoid restoring potentially dangerous EFLAGS bits (IOPL, NT, VM, AC) that could trigger a General Protection Fault or Bad-TSS on the next `IRET`.

When `DEBUG_LMM` is defined, `kalloc` allocates one additional unit and writes `GUARD_MAGIC` at the end of the allocation. `kfree` verifies this sentinel before freeing; a mismatch triggers a GPF with a syslog error, catching buffer overruns at free time.

Double-free detection uses `bitmap_all_set`: if any bit in the allocation's range is already clear at free time, the allocator logs an error and GPFs rather than silently corrupting the bitmap.

Fully empty pages (other than the root page) are returned to the VMM by `try_release_page`, which unlinks the page from the doubly-linked list and calls `arch.x86.memory.virtual.free_page_at_address`.
