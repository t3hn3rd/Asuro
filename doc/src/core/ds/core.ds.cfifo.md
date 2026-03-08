# core.ds.cfifo

Array-backed contiguous FIFO queue with lazy compaction and automatic growth.

## Overview

`core.ds.cfifo` implements a First-In First-Out queue that stores elements in a flat contiguous buffer rather than a linked list. This avoids per-element heap allocation overhead and improves cache locality. The buffer doubles in size when it becomes full. A lazy compaction strategy is used: instead of shifting elements on every dequeue, the `Head` index is simply advanced. When `Head` passes half the capacity, all remaining elements are shifted back to index 0 in a single compaction pass.

## Dependencies

- `core.ds.types` — `TCFIFOQueue`, `PCFIFOQueue`
- `memory.heap` — `kalloc`, `kfree`
- `core.util` — `memcpy`, `memset`
- `arch.x86.util` — architecture utilities
- `io.syslog` — test output (implementation only)
- `core.strings` — test output formatting (implementation only)

## Functions and Procedures

### CFIFO_New
```pascal
function CFIFO_New(ElementSize : uint32; InitialCapacity : uint32) : PCFIFOQueue;
```
Creates a new contiguous FIFO queue. `ElementSize` is the size in bytes of each element. `InitialCapacity` is the starting number of element slots; the buffer grows automatically as needed.

### CFIFO_Enqueue
```pascal
procedure CFIFO_Enqueue(Queue : PCFIFOQueue; Data : void);
```
Copies `ElementSize` bytes from `Data` into the back of the queue. Grows the buffer if all slots are consumed. Triggers a compaction pass if there is no room at the tail despite available slots (due to head advancement).

### CFIFO_Dequeue
```pascal
function CFIFO_Dequeue(Queue : PCFIFOQueue; Data : void) : boolean;
```
Copies the front element into `Data` and advances `Head`. Triggers a lazy compaction when `Head` passes half the capacity. Resets `Head` to 0 when the queue becomes empty. Returns `false` if the queue is empty.

### CFIFO_Peek
```pascal
function CFIFO_Peek(Queue : PCFIFOQueue) : void;
```
Returns a direct pointer to the front element without removing it. Returns `nil` if the queue is empty. The pointer is invalidated by any subsequent enqueue or dequeue that triggers compaction or growth.

### CFIFO_Size
```pascal
function CFIFO_Size(Queue : PCFIFOQueue) : uint32;
```
Returns the number of elements currently in the queue.

### CFIFO_IsEmpty
```pascal
function CFIFO_IsEmpty(Queue : PCFIFOQueue) : boolean;
```
Returns `true` if the queue contains no elements.

### CFIFO_Capacity
```pascal
function CFIFO_Capacity(Queue : PCFIFOQueue) : uint32;
```
Returns the current allocated capacity in number of element slots.

### CFIFO_Free
```pascal
procedure CFIFO_Free(Queue : PCFIFOQueue);
```
Frees the element buffer and the queue structure.

### UnitTest
```pascal
procedure UnitTest;
```
Runs the CFIFO test suite and logs a pass/fail summary to syslog under the `'CFIFO'` channel.

## Notes

Compaction uses `memcpy` to shift elements, which is safe here because the destination is always at a lower address than the source when `Head > 0`.

The buffer capacity never shrinks automatically. Use `CFIFO_Free` and `CFIFO_New` to reclaim memory after draining a large queue.
