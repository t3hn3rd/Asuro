# core.ds.fifo

Linked-list backed First-In First-Out queue.

## Overview

`core.ds.fifo` implements a FIFO queue using a singly-linked list of heap-allocated nodes. Each enqueued element is copied into a new node; each dequeue copies the data out and frees the node. The linked-list design allows unbounded growth with no compaction or shifting, at the cost of one heap allocation per element. For use cases requiring better cache locality and lower allocation overhead, see `core.ds.cfifo`.

## Dependencies

- `memory.heap` — `kalloc`, `kfree`
- `core.util` — `memcpy`
- `arch.x86.util` — architecture utilities
- `core.ds.types` — `TFIFOQueue`, `PFIFOQueue`, `TQueueNode`, `PQueueNode`
- `io.syslog` — test output (implementation only)
- `core.strings` — test output formatting (implementation only)

## Functions and Procedures

### FIFO_New
```pascal
function FIFO_New(ElementSize : uint32) : PFIFOQueue;
```
Creates and returns a new empty FIFO queue. `ElementSize` is the size in bytes of each element.

### FIFO_Enqueue
```pascal
procedure FIFO_Enqueue(Queue : PFIFOQueue; Data : void);
```
Allocates a new node, copies `ElementSize` bytes from `Data` into it, and appends it to the tail of the queue.

### FIFO_Dequeue
```pascal
function FIFO_Dequeue(Queue : PFIFOQueue; Data : void) : boolean;
```
Copies the front element's data into `Data`, removes the head node, and frees it. Returns `false` if the queue is empty.

### FIFO_Peek
```pascal
function FIFO_Peek(Queue : PFIFOQueue) : void;
```
Returns a direct pointer to the front element's data without removing the node. Returns `nil` if the queue is empty. The pointer is invalidated if the head node is dequeued.

### FIFO_Size
```pascal
function FIFO_Size(Queue : PFIFOQueue) : uint32;
```
Returns the number of elements currently in the queue.

### FIFO_IsEmpty
```pascal
function FIFO_IsEmpty(Queue : PFIFOQueue) : boolean;
```
Returns `true` if the queue contains no elements.

### FIFO_Free
```pascal
procedure FIFO_Free(Queue : PFIFOQueue);
```
Frees all nodes and their data buffers, then frees the queue structure.

### UnitTest
```pascal
procedure UnitTest;
```
Runs the FIFO queue test suite and logs a pass/fail summary to syslog under the `'FIFO'` channel.

## Notes

Each enqueue causes two heap allocations (node structure and element data buffer). For high-frequency queuing, prefer `core.ds.cfifo` which batches allocations into a single growing buffer.
