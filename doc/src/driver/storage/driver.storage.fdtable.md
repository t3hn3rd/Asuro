# driver.storage.fdtable

Per-process file descriptor table management.

## Overview

Each process owns one `TFDTable`, allocated at process creation and freed when the process is reaped. The table holds up to `MAX_FDS` (64) file descriptor slots. File handles are 1-based indices into this table; handle 0 is always invalid.

The VFS layer calls `fd_alloc`, `fd_get`, and `fd_close` rather than manipulating the table directly. This unit has no knowledge of VFS paths or filesystem drivers — it only manages slot lifetime, string ownership, and pre-loaded data buffers stored in each descriptor.

## Dependencies

- `memory.heap`
- `driver.storage.types`
- `core.util`, `arch.x86.util`

## Constants

### MAX_FDS

`64` — Maximum number of file descriptors a single process may have open simultaneously.

## Types

### TFileDescriptor / PFileDescriptor

One slot in the per-process FD table.

| Field | Type | Description |
|---|---|---|
| `InUse` | `boolean` | True if this slot is allocated |
| `Volume` | `PStorage_Volume` | Volume the file resides on |
| `Directory` | `pchar` | Directory path within the volume (heap-owned) |
| `FileName` | `pchar` | Filename within that directory (heap-owned) |
| `OpenMode` | `uint8` | `TOpenMode` ordinal (avoids circular VFS type dependency) |
| `WriteMode` | `uint8` | `TWriteMode` ordinal |
| `DataBuffer` | `puint32` | Pre-loaded file data for small files, nil otherwise |
| `DataSize` | `uint32` | Size of pre-loaded data in bytes |
| `Loaded` | `boolean` | True if data has been pre-loaded into `DataBuffer` |
| `StreamOff` | `uint32` | Current byte offset for streaming / on-demand reads |

### TFDTable / PFDTable

Fixed-size array of `MAX_FDS` file descriptor slots. One instance per process.

## Functions and Procedures

### fd_table_new

```pascal
function fd_table_new : PFDTable;
```

Allocates and zero-initialises a new FD table on the heap. Called once per process at creation time. Returns nil on allocation failure.

### fd_table_free

```pascal
procedure fd_table_free(table : PFDTable);
```

Closes all open descriptors in the table via `fd_close_all`, then frees the table itself. Safe to call with nil.

### fd_alloc

```pascal
function fd_alloc(table : PFDTable) : uint32;
```

Finds the first free slot in the table and returns its 1-based handle. Returns 0 if the table is full or nil. Does not mark the slot as in-use; the caller must set `InUse := true` after populating the descriptor fields.

### fd_get

```pascal
function fd_get(table : PFDTable; handle : uint32) : PFileDescriptor;
```

Returns a pointer to the descriptor for the given 1-based handle. Returns nil if the handle is out of range (0 or > `MAX_FDS`) or if the slot is not marked `InUse`.

### fd_close

```pascal
function fd_close(table : PFDTable; handle : uint32) : boolean;
```

Closes a single file descriptor: frees `DataBuffer`, `Directory`, and `FileName` strings, zeroes tracking fields, and marks the slot as not in-use. Returns true if the handle was valid and open, false otherwise.

### fd_close_all

```pascal
procedure fd_close_all(table : PFDTable);
```

Iterates all slots and closes every in-use descriptor. Used during process cleanup before the table itself is freed.

## Notes

- Handles are 1-based so that 0 can serve as a sentinel "invalid handle" value throughout the kernel.
- The `fd_free_entry` internal procedure performs the actual resource release; it is called by both `fd_close` and `fd_close_all`.
- `DataBuffer` is only populated for pre-loaded files (e.g., files opened in `omReadOnly` or `omReadWrite` mode). Stream-mode handles leave it nil and use `StreamOff` for incremental reads.
