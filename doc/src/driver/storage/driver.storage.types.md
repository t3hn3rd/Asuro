# driver.storage.types

Shared data types, enumerations, and record definitions used across the entire Asuro storage subsystem.

## Overview

This unit is the foundational type library for the storage stack. It defines all shared structures consumed by the storage manager, volume manager, filesystem drivers, VFS, and hardware controller drivers. No logic resides here — only declarations. Every other storage unit depends on this unit, making it the single source of truth for inter-layer contracts.

## Dependencies

- `core.ds.types`
- `core.ds.lists`

## Types

### TControllerType

Enumeration identifying the hardware interface type of a storage device.

| Value | Description |
|---|---|
| `ControllerATA` | Parallel ATA (PATA) hard disk |
| `ControllerATAPI` | ATAPI optical drive via IDE |
| `ControllerUSB` | USB mass storage |
| `ControllerAHCI` | AHCI SATA hard disk |
| `ControllerAHCI_ATAPI` | AHCI SATA optical drive |
| `ControllerNVMe` | NVMe solid-state drive |
| `ControllerNET` | Network block device |
| `ControllerRAM` | RAM-backed virtual device |
| `ControllerSCSI` | SCSI device |

### TFileSystemType

Enumeration of recognized filesystem formats. Currently informational; actual detection is performed by each filesystem driver's `identifyCallback`.

### TDirectory_Entry_Type

`(directoryEntry, fileEntry, mountEntry)` — classifies an entry returned by a directory listing operation.

### TError / PError

Comprehensive error code enumeration shared across all I/O, VFS, driver, and mount operations. `eNone` indicates success. Key categories:

- **Generic**: `eUnknown`, `eNotSupported`, `eOutOfMemory`, `eInvalidArgument`
- **File errors**: `eFileInUse`, `eFileDoesNotExist`, `eInvalidFileName`, `eFilenameTooLong`
- **Directory errors**: `eDirectoryDoesNotExist`, `eDirectoryAlreadyExists`, `eDirectoryNotEmpty`, `eDirectoryFull`, `eNotADirectory`
- **Access errors**: `eWriteOnly`, `eReadOnly`, `ePermissionDenied`
- **Path errors**: `eInvalidPath`
- **VFS / FD errors**: `eTooManyOpenFiles`, `eInvalidHandle`, `eNotStreamMode`
- **Disk / I/O errors**: `eDiskFull`, `eIOError`, `eIOTimeout`, `eIOCancelled`, `eDeviceNotReady`, `eDeviceRemoved`, `eDeviceNotFound`, `eQueueFull`, `eNoFreeSlot`
- **Filesystem integrity**: `eCorruptFilesystem`, `eBadSector`
- **Mount / volume**: `eAlreadyMounted`, `eNotMounted`, `eUnsupportedFilesystem`, `eInvalidPartitionTable`, `eVolumeNotFound`

### TDriverDispatch

```pascal
TDriverDispatch = procedure(device : PStorage_Device; request : PIORequest);
```

Unified hardware dispatch function pointer. A driver sets `dispatchRead` and `dispatchWrite` on `TStorage_Device` before registering. The storage manager calls the appropriate procedure when dequeuing a request from the per-device CFIFO.

### TIOCallback

```pascal
TIOCallback = procedure(error : TError; userdata : pointer);
```

Async I/O completion callback, fired from ISR context when a request finishes. Must be short and non-blocking. `userdata` is the opaque pointer supplied by the submitter.

### Filesystem hook types

Procedure and function pointer types assigned to `TFilesystem` fields. Each type corresponds to a VFS operation:

| Type | Operation |
|---|---|
| `PPWriteHook` | Synchronous file write |
| `PPReadHook` | Synchronous full-file read |
| `PPCreateHook` | Synchronous volume format/create |
| `PPCreateAsyncHook` | Async volume format/create |
| `PPDetectHook` | Probe raw device for this filesystem |
| `PPCreateDirHook` | Create directory |
| `PPReadDirHook` | Read directory listing |
| `PPDeleteFileHook` | Delete file |
| `PPDeleteDirHook` | Delete directory |
| `PPIdentifyHook` | Return true if volume is this filesystem |
| `PPReadOffsetHook` | Partial read at byte offset (streaming) |
| `PPWriteAsyncHook` ... `PPDeleteDirAsyncHook` | Async variants of the above |

### TIORequestType / TIORequestState

- `TIORequestType`: `(ioRead, ioWrite)`
- `TIORequestState`: `(iosPending, iosDispatched, iosComplete, iosCancelled, iosError)`

### TIORequest

Core I/O request record. One instance per disk operation in flight.

| Field | Type | Description |
|---|---|---|
| `RequestType` | `TIORequestType` | Read or write |
| `State` | `TIORequestState` | Lifecycle state |
| `Device` | `PStorage_Device` | Target device |
| `LBA` | `uint32` | Starting logical block address |
| `SectorCount` | `uint32` | Number of sectors to transfer |
| `Buffer` | `pointer` | Data buffer |
| `ByteCount` | `uint32` | Actual bytes transferred (driver fills on completion) |
| `Error` | `TError` | Result code |
| `Caller` | `pointer` | Process context for blocking sleep/wake |
| `UserData` | `pointer` | Back-pointer to caller's stack-local request |
| `Callback` | `TIOCallback` | Async completion callback (nil for blocking path) |
| `CallbackData` | `pointer` | Opaque data forwarded to `Callback` |

### TStorage_Device

Represents a registered physical storage device.

| Field | Description |
|---|---|
| `id` | Unique index assigned at registration |
| `controller` | Hardware interface type |
| `controllerId0` | Driver slot (e.g., master=0, slave=1) |
| `writable` | False for read-only media |
| `removed` | True after hot-unplug |
| `volumes` | Per-device volume list |
| `dispatchRead` / `dispatchWrite` | Phase 2 driver dispatch pointers |
| `requestQueue` | Per-device CFIFO of pending requests |
| `activeRequest` | Currently dispatched request, or nil |
| `maxSectorCount` | Total sectors on device |
| `sectorSize` | Bytes per sector |
| `start` | Device start sector offset |
| `cachedMBR` | Heap-cached copy of the MBR sector |
| `isBootDevice` | True if GRUB booted from this device |

### TFilesystem

Filesystem driver descriptor. All function pointer fields are optional; nil means the operation is unsupported by this driver.

### TStorage_Volume

Represents one partition on a device.

| Field | Description |
|---|---|
| `id` | Volume index |
| `device` | Owning storage device |
| `sectorStart` | First sector of this partition |
| `sectorSize` | Bytes per sector |
| `sectorCount` | Total sectors in partition |
| `freeSectors` | Available free sectors |
| `filesystem` | Filesystem driver descriptor |
| `isBootDrive` | True if device is the boot device |

### TDirectory_Entry

Generic directory entry.

| Field | Description |
|---|---|
| `fileName` | Entry name string |
| `entryType` | Classification (`directoryEntry`, `fileEntry`, `mountEntry`) |

### TDrive_Error

Error descriptor with a numeric code, a description string, and a recoverability flag.
