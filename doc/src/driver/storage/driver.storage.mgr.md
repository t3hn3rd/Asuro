# driver.storage.mgr

Physical storage device registry and I/O dispatch manager.

## Overview

The storage manager is the central hub of the Asuro storage subsystem. It maintains a global list of registered storage devices and owns the Phase 2 request-based I/O path. Hardware controller drivers call `register_device` when they discover a device; the manager assigns an ID, initialises the per-device CFIFO, determines whether the device is the boot device, and triggers volume discovery.

The I/O model operates as follows:

- `submit_io` enqueues a `TIORequest` into the device's CFIFO and calls `dispatch_next` to send the head request to hardware.
- `complete_io` is called from ISR or driver completion context to finalise a request, invoke its callback, free the heap copy, and dispatch the next queued request.
- `submit_io_wait` is a blocking wrapper that parks the calling process (`psAwaiting`) until `complete_io` wakes it.
- `storage_read` / `storage_write` are convenience wrappers that build a stack-local `TIORequest` and call `submit_io_wait`.
- `storage_read_async` / `storage_write_async` build and submit a request with a caller-supplied callback, returning immediately.

Legacy `storage_read_legacy` / `storage_write_legacy` procedure wrappers are retained for callers not yet migrated to the function-returning API.

## Dependencies

- `core.ds.cfifo`
- `core.ds.types`
- `driver.storage.iorequest`
- `core.ds.lists`
- `memory.heap`
- `driver.storage.vol.mbr`
- `proc.mgr`
- `proc.types`
- `driver.storage.types`
- `io.syslog`
- `debug.tracer`
- `core.util`, `arch.x86.util`
- `driver.storage.vol.mgr` (implementation uses)

## Boot Registration

Registered with `boot.mgr` as `driver.storage.mgr`, depending on `driver.storage.vfs`.

## Variables

| Name | Type | Description |
|---|---|---|
| `storageDevices` | `PDList` | Global list of all registered `TStorage_Device` records |
| `nextDeviceId` | `uint32` | Monotonically increasing device ID counter |
| `bootDriveByte` | `uint8` | BIOS drive byte set from multiboot info (`$80` = first HDD) |
| `hdCount` | `uint32` | Number of non-ATAPI devices registered so far |
| `atapiCount` | `uint32` | Number of ATAPI devices registered so far |

## Functions and Procedures

### init

```pascal
procedure init();
```

Initialises the storage device list and resets all counters. Must be called before any other storage manager function.

### set_boot_drive_byte

```pascal
procedure set_boot_drive_byte(driveByte : uint8);
```

Records the BIOS drive byte obtained from the multiboot info structure. Must be called once during early boot before any controller driver registers devices.

### get_boot_drive_byte

```pascal
function get_boot_drive_byte() : uint8;
```

Returns the stored BIOS drive byte (`$FF` if not yet set).

### register_device

```pascal
procedure register_device(device : PStorage_Device);
```

Registers a storage device discovered by a controller driver. Assigns a device ID, initialises the request queue and Phase 2 fields, determines whether the device is the boot device by comparing against `bootDriveByte`, and calls `driver.storage.vol.mgr.discover_volumes` to find and register partitions.

ATAPI devices are identified as the boot device if the BIOS drive byte does not correspond to any known HDD index (covers standard ISO boot). HDDs are matched by position (`$80` + HDD index).

### get_device_list

```pascal
function get_device_list() : PDList;
```

Returns the global device list.

### get_device_count

```pascal
function get_device_count() : uint32;
```

Returns the number of registered devices.

### get_device

```pascal
function get_device(index : uint32) : PStorage_Device;
```

Returns the device at `index`, or nil if out of range.

### controller_type_2_string

```pascal
function controller_type_2_string(controllerType : TControllerType) : pchar;
```

Converts a `TControllerType` value to a human-readable string (e.g., `'AHCI'`, `'ATAPI'`).

### read_mbr

```pascal
function read_mbr(device : PStorage_Device) : PMaster_Boot_Record;
```

Reads sector 0 from `device` into a heap-allocated buffer and updates the device's `cachedMBR`. The caller owns the returned pointer and must free it. Returns nil on I/O failure.

### write_mbr

```pascal
procedure write_mbr(device : PStorage_Device; mbr : PMaster_Boot_Record);
```

Writes an MBR record to sector 0 and updates the device cache. Does nothing if the device is not writable.

### get_cached_mbr

```pascal
function get_cached_mbr(device : PStorage_Device) : PMaster_Boot_Record;
```

Returns a pointer to the cached MBR without performing any I/O. The caller must not free the returned pointer. Returns nil if the cache is not populated or `device` is nil.

### write_mbr_async

```pascal
procedure write_mbr_async(device : PStorage_Device; mbr : PMaster_Boot_Record;
                          callback : TIOCallback; callbackData : pointer);
```

Updates the MBR cache and issues a non-blocking write. `callback` is fired from ISR context when the write completes. If the device is read-only, fires the callback immediately with `eReadOnly`.

### submit_io

```pascal
function submit_io(request : PIORequest) : TError;
```

Non-blocking: validates the request, enqueues it into the device's CFIFO, and calls `dispatch_next`. Returns `eNone` if successfully enqueued. The caller must have set `Callback`/`CallbackData` (async path) or `Caller`/`UserData` (blocking path) before calling. Disables interrupts around the enqueue and dispatch operations.

### submit_io_wait

```pascal
function submit_io_wait(request : PIORequest) : TError;
```

Blocking wrapper for task context only. Sets `sync_io_callback` as the completion callback, calls `submit_io`, parks the calling process in `psAwaiting`, and spins via pointer indirection until `complete_io` sets `Done = 1`. Returns the error code from the completed request.

### complete_io

```pascal
procedure complete_io(request : PIORequest; success : boolean; error : TError);
```

Called from ISR or driver completion context. Sets the request state and error, clears the device's `activeRequest`, invokes the completion callback, frees the heap copy of the request, and dispatches the next queued request.

### storage_read

```pascal
function storage_read(device : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32) : TError;
```

Blocking read. Builds a `TIORequest` and calls `submit_io_wait`. Must only be called from task context (interrupts enabled).

### storage_write

```pascal
function storage_write(device : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32) : TError;
```

Blocking write. Builds a `TIORequest` and calls `submit_io_wait`. Must only be called from task context.

### storage_read_async

```pascal
function storage_read_async(device : PStorage_Device; addr : uint32; sectors : uint32;
                            buffer : puint32; callback : TIOCallback; callbackData : pointer) : TError;
```

Non-blocking read. Enqueues a request and returns immediately. `callback` is fired from ISR context on completion. Safe to call from ISR or task context.

### storage_write_async

```pascal
function storage_write_async(device : PStorage_Device; addr : uint32; sectors : uint32;
                             buffer : puint32; callback : TIOCallback; callbackData : pointer) : TError;
```

Non-blocking write. Analogous to `storage_read_async`.

### storage_read_legacy / storage_write_legacy

```pascal
procedure storage_read_legacy(device : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32);
procedure storage_write_legacy(device : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32);
```

Drop-in procedure replacements for callers using the old void-returning API. Forward to `storage_read` / `storage_write` and discard the error code. Marked for removal once all callers are migrated.

## Notes

- `dispatch_next` is an internal procedure called with interrupts disabled. It dequeues the head of the CFIFO, allocates a heap copy via `ioreq_copy` (for ISR safety), and invokes the appropriate `dispatchRead` or `dispatchWrite` on the device. If neither dispatch pointer is set, the request is failed with `eDeviceNotFound`.
- The blocking path relies on pointer-dereferenced spin (`puint32(@wait.Done)^`) to prevent FPC from caching the `Done` flag in a register across the `hlt` instruction.
- Devices without `dispatchRead`/`dispatchWrite` set (i.e., drivers not yet migrated to Phase 2) will have `submit_io` return `eDeviceNotFound`. Legacy drivers must be migrated before they can use the new I/O path.
