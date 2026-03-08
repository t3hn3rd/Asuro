# core.ds.bheap

Shared binary heap engine for min-heap, max-heap, and priority queue implementations.

## Overview

`core.ds.bheap` provides the core binary heap machinery used by `core.ds.minh`, `core.ds.maxh`, and `core.ds.prio`. It stores element data inline in a flat buffer with index-array indirection: a separate `Indices` array maps heap positions to data slot indices, so swaps during sift-up and sift-down exchange only 32-bit indices rather than copying full element data. Freed data slots are recycled via a free-slot stack, avoiding fragmentation. The buffer grows automatically by doubling when capacity is exhausted.

The heap can operate in either min-heap mode (root holds the lowest priority value) or max-heap mode (root holds the highest priority value), controlled by the `IsMinHeap` field set at creation time.

This unit is not intended to be used directly. Use the typed wrappers `core.ds.minh`, `core.ds.maxh`, or `core.ds.prio` instead.

## Dependencies

- `core.ds.types` — `TBinaryHeap`, `PBinaryHeap`
- `memory.heap` — `kalloc`, `kfree`
- `core.util` — `memcpy`, `memset`
- `arch.x86.util` — architecture utilities

## Functions and Procedures

### BHeap_New
```pascal
function BHeap_New(ElementSize : uint32; InitialCapacity : uint32;
                   MinHeap : boolean) : PBinaryHeap;
```
Allocates and initialises a new binary heap. `ElementSize` is the size in bytes of each data element (not including the priority field). `InitialCapacity` is the starting number of slots. `MinHeap` selects ordering: `true` for min-heap, `false` for max-heap.

### BHeap_Insert
```pascal
procedure BHeap_Insert(Heap : PBinaryHeap; Priority : uint32; Data : void);
```
Inserts a new element with the given `Priority`. The element data pointed to by `Data` is copied into the heap's internal buffer. Grows the heap automatically if capacity is exhausted.

### BHeap_ExtractRoot
```pascal
function BHeap_ExtractRoot(Heap : PBinaryHeap; OutData : void) : boolean;
```
Removes and copies the root element's data into `OutData`. The root's data slot is returned to the free-slot stack. Returns `true` if an element was extracted; `false` if the heap was empty.

### BHeap_PeekRoot
```pascal
function BHeap_PeekRoot(Heap : PBinaryHeap) : void;
```
Returns a direct pointer to the root element's data without removing it. Returns `nil` if the heap is empty. The pointer is invalidated by any subsequent insertion or extraction.

### BHeap_Free
```pascal
procedure BHeap_Free(Heap : PBinaryHeap);
```
Frees all three internal buffers (`Data`, `Indices`, `FreeSlots`) and the heap structure itself.

## Notes

The data slot layout is: `[uint32 priority][ElementSize bytes of element data]`. The `NodeStride` field equals `sizeof(uint32) + ElementSize`.

Swaps during sift-up and sift-down exchange entries in the `Indices` array only, so the cost of a swap is always O(1) regardless of element size.

When the heap is full, `BHeap_Grow` doubles all three buffers and copies existing data. This is an O(n) operation.
