# lmemorymanager

Compatibility shim that re-exports the `memory.heap` API under the legacy unit name.

## Overview

The Wasuro WASM VM project references the old unit name `lmemorymanager` for heap memory operations. Because the Wasuro source tree cannot be modified, this shim unit re-exports every public symbol from `memory.heap` so that `uses lmemorymanager` continues to compile without changes. All functions are thin inline wrappers that delegate directly to their `memory.heap` counterparts.

## Dependencies

- `memory.heap` -- the canonical heap allocator implementation in the Asuro kernel.

## Constants

### ALLOC_UNIT
Re-exported from `memory.heap.ALLOC_UNIT`. The base allocation unit size used by the heap allocator.

### DATA_OFFSET
Re-exported from `memory.heap.DATA_OFFSET`. Byte offset from a heap block header to the start of user data.

### PAGE_SIZE_LMM
Re-exported from `memory.heap.PAGE_SIZE_LMM`. Page size used by the lightweight memory manager.

### TOTAL_UNITS
Re-exported from `memory.heap.TOTAL_UNITS`. Total number of allocation units per heap page.

### BITMAP_DWORDS
Re-exported from `memory.heap.BITMAP_DWORDS`. Number of 32-bit words in the per-page allocation bitmap.

### SIZE_PREFIX
Re-exported from `memory.heap.SIZE_PREFIX`. Size of the prefix stored before each allocation to record its length.

### LARGE_ALLOC_MAGIC
Re-exported from `memory.heap.LARGE_ALLOC_MAGIC`. Magic value used to identify large (multi-page) allocations.

## Types

### PHeapPageHeader / THeapPageHeader
Re-exported from `memory.heap`. Pointer and record types describing the header structure at the beginning of each heap page.

## Functions and Procedures

### init
```pascal
procedure init;
```
Initializes the heap memory manager by delegating to `memory.heap.init`.

### kalloc
```pascal
function kalloc(size: uint32): void;
```
Allocates `size` bytes from the kernel heap and returns a pointer to the allocated memory.

### klalloc
```pascal
function klalloc(size: uint32): void;
```
Performs a large kernel allocation of `size` bytes and returns a pointer to the allocated memory.

### klfree
```pascal
procedure klfree(address: uint32);
```
Frees a large allocation previously obtained via `klalloc`.

### kpalloc
```pascal
function kpalloc(address: uint32): void;
```
Allocates a heap page at the specified address and returns a pointer to it.

### kfree
```pascal
procedure kfree(area: void);
```
Frees a standard allocation previously obtained via `kalloc`.

### lmm_total_free
```pascal
function lmm_total_free: uint32;
```
Returns the total number of free bytes available across all heap pages.

### lmm_page_count
```pascal
function lmm_page_count: uint32;
```
Returns the current number of heap pages managed by the allocator.

## Notes

- Every function and procedure in the implementation section is marked `inline`, so the compiler eliminates the wrapper overhead entirely.
- This unit exists solely for backward compatibility with the Wasuro WASM VM build. New kernel code should use `memory.heap` directly.
