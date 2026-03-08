# core.ds.maxh

Max-heap: extracts the element with the highest priority value first.

## Overview

`core.ds.maxh` is a thin typed wrapper over `core.ds.bheap` that creates a max-heap. In a max-heap, `maxh_ExtractMax` always yields the element whose `Priority` value is the largest among all inserted elements. This is suitable for applications such as scheduling where the most urgent (highest-valued) item should be processed first.

All heap mechanics (index-array indirection, free-slot recycling, automatic growth) are handled by the underlying `core.ds.bheap` engine.

## Dependencies

- `core.ds.types` — `TBinaryHeap`, `PBinaryHeap`
- `core.ds.bheap` — heap engine
- `io.syslog` — test output (implementation only)
- `core.strings` — test output formatting (implementation only)
- `memory.heap` — `kfree` (implementation only)

## Functions and Procedures

### maxh_New
```pascal
function maxh_New(ElementSize : uint32; InitialCapacity : uint32) : PBinaryHeap;
```
Creates a new max-heap. `ElementSize` is the size in bytes of each data element. `InitialCapacity` is the starting number of slots (grows automatically).

### maxh_Insert
```pascal
procedure maxh_Insert(Heap : PBinaryHeap; Priority : uint32; Data : void);
```
Inserts an element with the given priority. Higher priority values are extracted first.

### maxh_ExtractMax
```pascal
function maxh_ExtractMax(Heap : PBinaryHeap; Data : void) : boolean;
```
Removes and copies the element with the highest priority into `Data`. Returns `false` if the heap is empty.

### maxh_PeekMax
```pascal
function maxh_PeekMax(Heap : PBinaryHeap) : void;
```
Returns a direct pointer to the highest-priority element's data without removing it. Returns `nil` if the heap is empty.

### maxh_Size
```pascal
function maxh_Size(Heap : PBinaryHeap) : uint32;
```
Returns the number of elements in the heap.

### maxh_IsEmpty
```pascal
function maxh_IsEmpty(Heap : PBinaryHeap) : boolean;
```
Returns `true` if the heap contains no elements.

### maxh_Free
```pascal
procedure maxh_Free(Heap : PBinaryHeap);
```
Frees the heap and all its internal buffers.

### UnitTest
```pascal
procedure UnitTest;
```
Runs the max-heap test suite (inserts 5 elements out of order, verifies extraction in descending order) and logs a pass/fail summary to syslog under the `'MAXH'` channel.
