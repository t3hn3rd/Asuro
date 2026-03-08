# core.ds.prio

Min-heap ordered priority queue (lowest priority value dequeued first).

## Overview

`core.ds.prio` is a thin typed wrapper over `core.ds.bheap` that presents a priority queue interface. Elements are dequeued in ascending priority order: the element with the lowest `Priority` value is always at the front. This convention (low number = high urgency) is used by the Asuro process scheduler and other subsystems that assign numeric priorities to tasks.

All heap mechanics are handled by the underlying `core.ds.bheap` engine.

## Dependencies

- `core.ds.bheap` — heap engine
- `core.ds.types` — `TBinaryHeap`, `PBinaryHeap`
- `io.syslog` — test output (implementation only)
- `core.strings` — test output formatting (implementation only)
- `memory.heap` — `kfree` (implementation only)

## Functions and Procedures

### prio_New
```pascal
function prio_New(ElementSize : uint32; InitialCapacity : uint32) : PBinaryHeap;
```
Creates a new priority queue. `ElementSize` is the size in bytes of each data element. `InitialCapacity` is the starting number of slots (grows automatically).

### prio_Enqueue
```pascal
procedure prio_Enqueue(Heap : PBinaryHeap; Priority : uint32; Data : void);
```
Enqueues an element with the given `Priority`. Elements with lower priority values will be dequeued before those with higher values.

### prio_Dequeue
```pascal
function prio_Dequeue(Heap : PBinaryHeap; Data : void) : boolean;
```
Removes and copies the highest-priority (lowest-valued) element into `Data`. Returns `false` if the queue is empty.

### prio_Peek
```pascal
function prio_Peek(Heap : PBinaryHeap) : void;
```
Returns a direct pointer to the highest-priority element's data without removing it. Returns `nil` if the queue is empty.

### prio_Size
```pascal
function prio_Size(Heap : PBinaryHeap) : uint32;
```
Returns the number of elements in the priority queue.

### prio_IsEmpty
```pascal
function prio_IsEmpty(Heap : PBinaryHeap) : boolean;
```
Returns `true` if the queue contains no elements.

### prio_Free
```pascal
procedure prio_Free(Heap : PBinaryHeap);
```
Frees the priority queue and all its internal buffers.

### UnitTest
```pascal
procedure UnitTest;
```
Runs the priority queue test suite (enqueues elements with priorities 1–5 in shuffled order, verifies dequeue in priority order) and logs a pass/fail summary to syslog under the `'PRIO'` channel.

## Notes

The priority convention is inverted from common intuition: a `Priority` value of `1` is dequeued before `5`. This matches the convention used by process schedulers where priority 0 or 1 represents the most urgent task.
