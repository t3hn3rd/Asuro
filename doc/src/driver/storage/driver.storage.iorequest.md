# driver.storage.iorequest

I/O request allocation and lifecycle helpers.

## Overview

This unit provides heap allocation, copying, and freeing of `TIORequest` records used by the `submit_io` / `complete_io` path in `driver.storage.mgr`. It separates the memory management concern from the dispatch logic.

The key operation is `ioreq_copy`, which creates a heap-allocated copy of a CFIFO value-element. This copy is required for ISR safety: once a request is dequeued from the CFIFO and dispatched to hardware, the driver completion callback may fire on any stack at any time, so the request must reside on the heap rather than on a caller's stack.

## Dependencies

- `memory.heap`
- `driver.storage.types`

## Functions and Procedures

### ioreq_alloc

```pascal
function ioreq_alloc(reqType  : TIORequestType;
                     device   : PStorage_Device;
                     lba      : uint32;
                     sectors  : uint32;
                     buf      : pointer) : PIORequest;
```

Allocates a new `TIORequest` on the heap and initialises its core fields. `ByteCount`, `Error`, `Caller`, `UserData`, `Callback`, and `CallbackData` are zeroed. The state is set to `iosPending`. Returns nil on allocation failure.

### ioreq_free

```pascal
procedure ioreq_free(req : PIORequest);
```

Frees a heap-allocated `TIORequest`. Safe to call with nil.

### ioreq_copy

```pascal
function ioreq_copy(src : PIORequest) : PIORequest;
```

Performs a shallow copy of `src` into a new heap allocation. All fields are duplicated by value; the `Buffer` pointer is copied but the buffer itself is not duplicated. Returns nil on allocation failure.

## Notes

- `ioreq_alloc` is provided as a convenience for drivers that construct requests programmatically. The storage manager's public API (`storage_read`, `storage_write`) builds stack-local requests instead and copies them via `ioreq_copy` in `dispatch_next`.
- The copy performed by `ioreq_copy` is intentionally shallow: the data buffer pointed to by `Buffer` is shared between the original and the copy. Only the `TIORequest` record itself is duplicated.
