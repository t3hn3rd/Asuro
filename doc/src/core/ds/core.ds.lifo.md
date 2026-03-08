# core.ds.lifo

Linked-list backed Last-In First-Out stack.

## Overview

`core.ds.lifo` implements a LIFO stack using a singly-linked list of heap-allocated nodes. Each pushed element is copied into a new node prepended to the head of the list. Each pop copies the data out and frees the top node. The linked-list design allows unbounded growth with no pre-allocation, at the cost of one heap allocation per element.

## Dependencies

- `memory.heap` — `kalloc`, `kfree`
- `core.util` — `memcpy`
- `arch.x86.util` — architecture utilities
- `core.ds.types` — `TLIFOStack`, `PLIFOStack`, `TQueueNode`, `PQueueNode`
- `io.syslog` — test output (implementation only)
- `core.strings` — test output formatting (implementation only)

## Functions and Procedures

### lifo_New
```pascal
function lifo_New(ElementSize : uint32) : PLIFOStack;
```
Creates and returns a new empty LIFO stack. `ElementSize` is the size in bytes of each element.

### lifo_Push
```pascal
procedure lifo_Push(Stack : PLIFOStack; Data : void);
```
Allocates a new node, copies `ElementSize` bytes from `Data` into it, and prepends the node to the top of the stack.

### lifo_Pop
```pascal
function lifo_Pop(Stack : PLIFOStack; Data : void) : boolean;
```
Copies the top element's data into `Data`, removes the top node, and frees it. Returns `false` if the stack is empty.

### lifo_Peek
```pascal
function lifo_Peek(Stack : PLIFOStack) : void;
```
Returns a direct pointer to the top element's data without removing the node. Returns `nil` if the stack is empty. The pointer is invalidated if the top node is popped.

### lifo_Size
```pascal
function lifo_Size(Stack : PLIFOStack) : uint32;
```
Returns the number of elements currently on the stack.

### lifo_IsEmpty
```pascal
function lifo_IsEmpty(Stack : PLIFOStack) : boolean;
```
Returns `true` if the stack contains no elements.

### lifo_Free
```pascal
procedure lifo_Free(Stack : PLIFOStack);
```
Pops and frees all nodes and their data buffers, then frees the stack structure.

### UnitTest
```pascal
procedure UnitTest;
```
Runs the LIFO stack test suite and logs a pass/fail summary to syslog under the `'LIFO'` channel.

## Notes

Each push causes two heap allocations (node structure and element data buffer). The stack does not expose an array-backed variant; if cache efficiency matters, consider using `core.ds.cfifo` reversed or a custom stack on a pre-allocated buffer.
