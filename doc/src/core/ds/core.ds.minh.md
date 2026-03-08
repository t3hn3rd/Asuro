# core.ds.minh

Min-heap: extracts the element with the lowest priority value first.

## Overview

`core.ds.minh` is a thin typed wrapper over `core.ds.bheap` that creates a min-heap. In a min-heap, `minh_ExtractMin` always yields the element whose `Priority` value is the smallest among all inserted elements. This is suitable for applications such as Dijkstra's algorithm or any scenario where the least-costly item should be processed first.

All heap mechanics (index-array indirection, free-slot recycling, automatic growth) are handled by the underlying `core.ds.bheap` engine.

## Dependencies

- `core.ds.types` — `TBinaryHeap`, `PBinaryHeap`
- `core.ds.bheap` — heap engine
- `io.syslog` — test output (implementation only)
- `core.strings` — test output formatting (implementation only)
- `memory.heap` — `kfree` (implementation only)

## Functions and Procedures

### minh_New
```pascal
function minh_New(ElementSize : uint32; InitialCapacity : uint32) : PBinaryHeap;
```
Creates a new min-heap. `ElementSize` is the size in bytes of each data element. `InitialCapacity` is the starting number of slots (grows automatically).

### minh_Insert
```pascal
procedure minh_Insert(Heap : PBinaryHeap; Priority : uint32; Data : void);
```
Inserts an element with the given priority. Lower priority values are extracted first.

### minh_ExtractMin
```pascal
function minh_ExtractMin(Heap : PBinaryHeap; Data : void) : boolean;
```
Removes and copies the element with the lowest priority into `Data`. Returns `false` if the heap is empty.

### minh_PeekMin
```pascal
function minh_PeekMin(Heap : PBinaryHeap) : void;
```
Returns a direct pointer to the lowest-priority element's data without removing it. Returns `nil` if the heap is empty.

### minh_Size
```pascal
function minh_Size(Heap : PBinaryHeap) : uint32;
```
Returns the number of elements in the heap.

### minh_IsEmpty
```pascal
function minh_IsEmpty(Heap : PBinaryHeap) : boolean;
```
Returns `true` if the heap contains no elements.

### minh_Free
```pascal
procedure minh_Free(Heap : PBinaryHeap);
```
Frees the heap and all its internal buffers.

### UnitTest
```pascal
procedure UnitTest;
```
Runs the min-heap test suite (basic operations plus a stress test of 50 elements inserted in reverse order and extracted in ascending order) and logs a pass/fail summary to syslog under the `'MINH'` channel.
