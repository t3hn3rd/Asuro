# core.ds.circ

Fixed-capacity ring-buffer queue.

## Overview

`core.ds.circ` implements a circular (ring-buffer) FIFO queue with a fixed maximum capacity set at creation time. Elements are stored in a flat pre-allocated buffer. Head and tail indices advance with modulo arithmetic to wrap around the buffer, eliminating the need for compaction or shifting. Enqueue is rejected when the buffer is full.

## Dependencies

- `memory.heap` — `kalloc`, `kfree`
- `core.ds.types` — `TCircularQueue`, `PCircularQueue`
- `core.util` — `memcpy`, `memset`
- `arch.x86.util` — architecture utilities
- `io.syslog` — test output (implementation only)
- `core.strings` — test output formatting (implementation only)

## Functions and Procedures

### circ_New
```pascal
function circ_New(Capacity : uint32; ElementSize : uint32) : PCircularQueue;
```
Creates a new circular queue with exactly `Capacity` element slots. `ElementSize` is the size in bytes of each element. The buffer is zero-initialised.

### circ_Enqueue
```pascal
function circ_Enqueue(Queue : PCircularQueue; Data : void) : boolean;
```
Copies `ElementSize` bytes from `Data` into the next free slot and advances the tail index. Returns `false` if the queue is full and the element is rejected.

### circ_Dequeue
```pascal
function circ_Dequeue(Queue : PCircularQueue; Data : void) : boolean;
```
Copies the front element into `Data` and advances the head index. Returns `false` if the queue is empty.

### circ_Peek
```pascal
function circ_Peek(Queue : PCircularQueue) : void;
```
Returns a direct pointer to the front element without removing it. Returns `nil` if the queue is empty.

### circ_Size
```pascal
function circ_Size(Queue : PCircularQueue) : uint32;
```
Returns the number of elements currently in the queue.

### circ_IsFull
```pascal
function circ_IsFull(Queue : PCircularQueue) : boolean;
```
Returns `true` if the queue has reached its maximum capacity.

### circ_IsEmpty
```pascal
function circ_IsEmpty(Queue : PCircularQueue) : boolean;
```
Returns `true` if the queue contains no elements.

### circ_Free
```pascal
procedure circ_Free(Queue : PCircularQueue);
```
Frees the element buffer and the queue structure.

### UnitTest
```pascal
procedure UnitTest;
```
Runs the circular queue test suite and logs a pass/fail summary to syslog under the `'CIRC'` channel.

## Notes

The capacity is fixed at creation. Unlike `core.ds.cfifo`, the circular queue never grows. Callers must choose a capacity sufficient for their maximum concurrent element count.

The pointer returned by `circ_Peek` is invalidated by any subsequent enqueue or dequeue that moves the head index.
