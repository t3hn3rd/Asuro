# core.ds.cfifols

Dynamic list of contiguous FIFO queue pointers.

## Overview

`core.ds.cfifols` implements a growable ordered list of `PCFIFOQueue` pointers. It is used to group and manage a variable number of related contiguous FIFO queues under a single handle. The list stores only pointer references; the referenced queues are owned and managed by the caller unless `CFIFOLS_FreeAll` is used.

## Dependencies

- `memory.heap` — `kalloc`, `kfree`
- `core.ds.types` — `TCFIFOList`, `PCFIFOList`
- `core.ds.cfifo` — `CFIFO_Free` (used by `CFIFOLS_FreeAll`)
- `core.util` — `memcpy`, `memset`
- `arch.x86.util` — architecture utilities
- `io.syslog` — test output (implementation only)
- `core.strings` — test output formatting (implementation only)

## Functions and Procedures

### CFIFOLS_New
```pascal
function CFIFOLS_New(InitialCapacity : uint32) : PCFIFOList;
```
Creates a new contiguous FIFO list with `InitialCapacity` pointer slots. The slot buffer grows automatically when the capacity is exceeded.

### CFIFOLS_Add
```pascal
procedure CFIFOLS_Add(List : PCFIFOList; Queue : PCFIFOQueue);
```
Appends the queue pointer `Queue` to the end of the list. Grows the slot buffer by doubling if capacity is exhausted.

### CFIFOLS_Get
```pascal
function CFIFOLS_Get(List : PCFIFOList; Index : uint32) : PCFIFOQueue;
```
Returns the queue pointer at zero-based `Index`. Returns `nil` if `Index` is out of range.

### CFIFOLS_Remove
```pascal
function CFIFOLS_Remove(List : PCFIFOList; Index : uint32) : boolean;
```
Removes the pointer at `Index` by shifting subsequent entries left. The referenced queue is not freed; ownership is retained by the caller. Returns `false` if `Index` is out of range.

### CFIFOLS_Count
```pascal
function CFIFOLS_Count(List : PCFIFOList) : uint32;
```
Returns the number of queue pointers currently in the list.

### CFIFOLS_IsEmpty
```pascal
function CFIFOLS_IsEmpty(List : PCFIFOList) : boolean;
```
Returns `true` if the list holds no pointers.

### CFIFOLS_Free
```pascal
procedure CFIFOLS_Free(List : PCFIFOList);
```
Frees the pointer slot buffer and the list structure. Does not free the referenced queues.

### CFIFOLS_FreeAll
```pascal
procedure CFIFOLS_FreeAll(List : PCFIFOList);
```
Calls `CFIFO_Free` on every queue in the list, then frees the slot buffer and the list structure.

### UnitTest
```pascal
procedure UnitTest;
```
Runs the CFIFOLS test suite and logs a pass/fail summary to syslog under the `'CFIFOLS'` channel.

## Notes

`CFIFOLS_Remove` shifts remaining entries using `memcpy`, which is safe because the destination is always at a lower address than the source.

The list does not track queue ownership; callers must decide whether to use `CFIFOLS_Free` (preserving queues) or `CFIFOLS_FreeAll` (destroying queues).
