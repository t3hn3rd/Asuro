# VFS Public Interface

The Virtual File System (`driver.storage.vfs`) provides a unified API for file I/O, directory management, path resolution, symlinks, device nodes, and directory-change notifications. All paths are UNIX-style (`/`-separated). The VFS namespace is a tree of virtual directories, mount points, symlinks, and device nodes.

---

## Types

### Enumerations

| Type | Values | Description |
|------|--------|-------------|
| `TOpenMode` | `omRead`, `omWrite`, `omCreate`, `omReadWrite`, `omStream` | How a file handle is opened. See `OpenFile` for details. |
| `TIsPathValid` | `pvInvalid`, `pvFile`, `pvDirectory` | Result of path validation. |
| `TObjectType` | `otVDIRECTORY`, `otDRIVE`, `otDEVICE`, `otVFILE`, `otMOUNT`, `otDIRECTORY`, `otFILE`, `otSYMLINK` | Node types in the VFS tree. |
| `TVFSWatchEvent` | `weCreated`, `weDeleted`, `weRenamed`, `weModified` | Events that fire on watched directories. |

### Handle Type

```pascal
TFileHandle = uint32;
```

Returned by `OpenFile` / `OpenFileAsync`. Value `0` means invalid/not open. Handles are 1-based indices into the per-process file descriptor table (max 64 open files per process).

### Records

#### TVFSObject

```pascal
TVFSObject = record
    Parent     : PVFSObject;
    ObjectName : pchar;
    ObjectType : TObjectType;
    Reference  : void;
    FileSize   : uint32;
end;
```

Internal VFS tree node. Exposed in directory listing snapshots returned by `GetDirectoryListingFrom`.

#### TVFSDeviceOps

```pascal
TVFSDeviceOps = record
    Read  : TVFSDevReadFunc;
    Write : TVFSDevWriteFunc;
    Size  : TVFSDevSizeFunc;
end;
```

Function-pointer table for character/block device I/O. Any field may be `nil` if the device does not support that operation. See [Device Nodes](#device-nodes) for callback signatures.

---

## Initialisation

### `procedure init()`

Initialises the VFS subsystem. Creates the root node and default virtual directories (`/dev`, `/disk`, `/mnt`, `/cfg`, `/boot`), registers built-in device nodes (`/dev/null`, `/dev/zero`), initialises the watch table and directory cache, and registers shell commands (`LS`, `CD`, `PUSHD`, `POPD`, `MKDIR`, `RM`, `RMDIR`, `MOUNT`, `UMOUNT`).

Called once during kernel boot. Must not be called again.

---

## File I/O — Synchronous

### `OpenFile`

```pascal
function OpenFile(
    Filename  : pchar;
    OpenMode  : TOpenMode;
    Error     : PError
) : TFileHandle;
```

Opens a file or device node. Returns a non-zero handle on success, `0` on failure. `Error^` is set to the specific `TError` code.

- **Device nodes** (e.g. `/dev/null`) are detected before volume resolution. The FD is set up with device callbacks; no filesystem driver is involved.
- **`omRead`**: Open existing file for reading. The entire file is pre-loaded into the FD's data buffer. Subsequent `ReadFile` calls read from this buffer by position.
- **`omWrite`**: Open existing file for writing (overwrite).
- **`omCreate`**: Create a new file for writing. Fails with `eFileDoesNotExist` if the file already exists.
- **`omReadWrite`**: Open existing file for both reading and writing. Pre-loads data like `omRead`, but also allows `WriteFile`.
- **`omStream`**: Streaming sequential I/O. No pre-load. Reads and writes use the filesystem's offset-based callbacks on demand, with an internal stream offset that auto-advances. Use `SeekFile` to reposition.

### `ReadFile`

```pascal
function ReadFile(
    FileHandle : TFileHandle;
    Position   : uint32;
    Buffer     : puint8;
    Length     : uint32
) : uint32;
```

Reads up to `Length` bytes into `Buffer`. Returns the number of bytes actually read.

- **Device FDs**: Dispatches to `DeviceOps^.Read`. In stream mode, the internal stream offset is used and auto-advanced.
- **Stream mode** (`omStream`): `Position` is ignored; reads from the current stream offset.
- **Buffered mode** (`omRead` / `omReadWrite`): Reads from the pre-loaded buffer at `Position`.

### `WriteFile`

```pascal
function WriteFile(
    FileHandle : TFileHandle;
    Position   : uint32;
    Buffer     : puint8;
    Length     : uint32
) : uint32;
```

Writes `Length` bytes from `Buffer`. Returns bytes written (`Length` on success, `0` on failure).

- Handle must have been opened with `omWrite`, `omCreate`, `omReadWrite`, or `omStream`.
- **Device FDs**: Dispatches to `DeviceOps^.Write`. In stream mode, the internal stream offset is used and auto-advanced.
- **Stream mode** (`omStream`): `Position` is ignored; writes at the current stream offset via the filesystem's `writeOffsetCallback`. Returns `0` if the FS does not implement `writeOffsetCallback`.
- **Volume FDs** (non-stream): Delegates to the filesystem's write callback. The buffer is padded to 4096 bytes internally (drivers may read full sectors).

### `CloseFile`

```pascal
function CloseFile(FileHandle : TFileHandle) : TError;
```

Closes the file handle. Frees all associated buffers and strings. Returns `eNone` on success, `eInvalidHandle` if the handle is not open.

### `FileSize`

```pascal
function FileSize(Filename : pchar; error : PError) : uint32;
```

Opens the file read-only, reads its size, closes it, and returns the size in bytes. Convenience wrapper — for already-open files, prefer `FileSizeFromHandle`.

### `FileSizeFromHandle`

```pascal
function FileSizeFromHandle(Handle : TFileHandle) : uint32;
```

Returns the data size of an open file handle. For device FDs, calls `DeviceOps^.Size` if available. Returns `0` for invalid handles.

### `SeekFile`

```pascal
function SeekFile(Handle : TFileHandle; Offset : uint32) : TError;
```

Sets the stream offset for a handle opened with `omStream`. Returns `eNotStreamMode` if the handle was not opened in stream mode.

### `DeleteFile`

```pascal
function DeleteFile(Path : pchar; Error : PError) : TError;
```

Deletes a file at the given path. Returns `eNone` on success.

### `CreateDirectory`

```pascal
function CreateDirectory(Path : pchar; Error : PError) : TError;
```

Creates a directory on the underlying filesystem.

### `DeleteDirectory`

```pascal
function DeleteDirectory(Path : pchar; Error : PError) : TError;
```

Deletes an empty directory. Returns `eDirectoryNotEmpty` if the directory has entries.

### `RenameFile`

```pascal
function RenameFile(OldPath : pchar; NewName : pchar; Error : PError) : TError;
```

Renames a file. `NewName` is just the new filename, not a full path.

---

## File I/O — Asynchronous

All async variants return immediately. The callback fires when the operation completes. Callers **must keep all buffers alive** until the callback fires.

### `OpenFileAsync`

```pascal
procedure OpenFileAsync(
    Filename     : pchar;
    OpenMode     : TOpenMode;
    var OutHandle : TFileHandle;
    Error        : PError;
    Callback     : TIOCallback;
    CallbackData : pointer
);
```

Async version of `OpenFile`. `OutHandle` and `Error^` are set before the callback fires.

### `ReadFileAsync`

```pascal
procedure ReadFileAsync(
    FileHandle   : TFileHandle;
    Position     : uint32;
    Buffer       : puint8;
    Length       : uint32;
    BytesRead    : puint32;
    Callback     : TIOCallback;
    CallbackData : pointer
);
```

Async read. `BytesRead^` is set before the callback fires. Device FDs are handled synchronously with an immediate callback.

### `WriteFileAsync`

```pascal
procedure WriteFileAsync(
    FileHandle   : TFileHandle;
    Position     : uint32;
    Buffer       : puint8;
    Length       : uint32;
    Callback     : TIOCallback;
    CallbackData : pointer
);
```

Async write. Prefers the filesystem's async write hook; falls back to sync + immediate callback.

- Handle must have been opened with `omWrite`, `omCreate`, `omReadWrite`, or `omStream`.
- **Device FDs**: Dispatches to `DeviceOps^.Write` synchronously, then fires callback. In stream mode, stream offset is auto-advanced.
- **Stream mode** (`omStream`) for volume FDs: Uses `writeOffsetCallback`; fires `eNotSupported` if the FS does not implement it.
- **Non-stream volume FDs**: Standard async/sync write dispatch with 4096-byte padding.

### `DeleteFileAsync`

```pascal
procedure DeleteFileAsync(
    Path         : pchar;
    Error        : PError;
    Callback     : TIOCallback;
    CallbackData : pointer
);
```

### `DeleteDirectoryAsync`

```pascal
procedure DeleteDirectoryAsync(
    Path         : pchar;
    Error        : PError;
    Callback     : TIOCallback;
    CallbackData : pointer
);
```

### `GetDirectoryListingAsync`

```pascal
procedure GetDirectoryListingAsync(
    Path         : pchar;
    ResultMap    : PPHashMap;
    Callback     : TIOCallback;
    CallbackData : pointer
);
```

Async directory listing. `ResultMap^` is set to a caller-owned `PHashMap` snapshot before the callback fires. Caller must `FreeDirectoryListing()` the result.

---

## Path Resolution

### `PathValid`

```pascal
function PathValid(Path : pchar) : TIsPathValid;
```

Tests whether a path resolves to a file, directory, or is invalid. Follows symlinks (up to 8 hops). Device nodes return `pvFile`.

### `MakeAbsolutePath`

```pascal
function MakeAbsolutePath(Path : pchar) : pchar;
```

Converts a path to absolute form using the current working directory. Returns a heap-allocated string — caller must `kfree()`.

### `MakeAbsolutePathFrom`

```pascal
function MakeAbsolutePathFrom(Path : pchar; BaseDir : pchar) : pchar;
```

Same as `MakeAbsolutePath` but uses `BaseDir` instead of the process CWD. Returns a heap-allocated string — caller must `kfree()`.

### `ResolvePathFrom`

```pascal
function ResolvePathFrom(Path : pchar; BaseDir : pchar) : TIsPathValid;
```

Resolves a relative path against `BaseDir` and returns its validity.

### `ChangeDirectory`

```pascal
function ChangeDirectory(Path : pchar) : TIsPathValid;
```

Sets the per-process current working directory. Returns the validity of the new path.

### `ChangeDirectoryFrom`

```pascal
function ChangeDirectoryFrom(
    Path    : pchar;
    BaseDir : pchar;
    var NewDir : pchar
) : TIsPathValid;
```

Changes directory relative to `BaseDir`. `NewDir` receives the new absolute path (heap-allocated, caller must `kfree()`).

### `GetWorkingDirectory`

```pascal
function GetWorkingDirectory : pchar;
```

Returns a heap-allocated copy of the per-process CWD. Caller must `kfree()`.

---

## Directory Listings

### `GetDirectoryListingFrom`

```pascal
function GetDirectoryListingFrom(Path : pchar; BaseDir : pchar) : PHashMap;
```

Returns a **deep-copied snapshot** `PHashMap` of the directory contents. Keys are entry names (`pchar`), values are `PVFSObject`. Returns `nil` if the path is invalid.

Multiple calls return independent snapshots — modifying or freeing one does not affect others.

**Important**: Caller **must** call `FreeDirectoryListing()` when done.

### `FreeDirectoryListing`

```pascal
procedure FreeDirectoryListing(map : PHashMap);
```

Frees a directory listing snapshot and all its deep-copied entries. Safe to pass `nil`.

---

## Virtual Directories

### `newVirtualDirectory`

```pascal
function newVirtualDirectory(Path : pchar) : TError;
```

Creates a virtual directory in the VFS namespace tree. Parent directories must already exist. Returns `eAlreadyExists` if the name is taken.

Virtual directories exist only in the VFS tree — they are not backed by any filesystem and are lost on reboot.

---

## Mount Points

### `mountVolume`

```pascal
function mountVolume(mountPath : pchar; volume : PStorage_Volume) : TRegError;
```

Mounts a storage volume at the given VFS path. The path must be an existing virtual directory. Returns `pvRegistered` on success.

### `auto_mount_volumes`

```pascal
procedure auto_mount_volumes();
```

Automatically mounts all detected volumes under `/disk/` with auto-generated names (`/disk/vol0`, `/disk/vol1`, ...).

After mounting all volumes, reads `MOUNT.ASR` from the root of the boot volume (ISO). Each line in the file is a command:

```
mnt {device}/boot /boot
mnt {device}/sys  /sys
```

- `mnt <source> <target>` — creates a symlink from `<target>` to `<source>`.
- `{device}` is replaced with the boot volume's mount path (e.g. `/disk/vol2`).

This replaces the old `asr.mnt` persistent-mount mechanism.

---

## Symlinks

### `CreateSymlink`

```pascal
function CreateSymlink(LinkPath : pchar; TargetPath : pchar) : TError;
```

Creates a symbolic link at `LinkPath` pointing to `TargetPath`. The parent directory of `LinkPath` must exist and be a virtual directory. The target path is stored as-is and resolved at access time. Symlink resolution is capped at 8 hops.

Returns:
- `eNone` — success
- `eInvalidArgument` — nil argument
- `eInvalidPath` — parent directory does not exist
- `eAlreadyExists` — name already taken
- `eNotADirectory` — parent is not a directory

---

## Device Nodes

Device nodes allow non-storage I/O to be accessed through the standard VFS file API. A device is registered at a VFS path with a table of read/write/size callbacks.

### Callback Signatures

```pascal
TVFSDevReadFunc  = function(devData : pointer; offset : uint32; buffer : puint8; length : uint32) : uint32;
TVFSDevWriteFunc = function(devData : pointer; offset : uint32; buffer : puint8; length : uint32) : uint32;
TVFSDevSizeFunc  = function(devData : pointer) : uint32;
```

- `devData` — opaque pointer passed at registration time
- `offset` — byte offset (for positional reads) or current stream offset
- `buffer` — caller's data buffer
- `length` — number of bytes requested
- **Return value** — number of bytes actually read/written

Any callback may be `nil` if the device does not support that operation.

### `RegisterDevice`

```pascal
function RegisterDevice(
    Path    : pchar;
    Ops     : PVFSDeviceOps;
    DevData : pointer
) : TError;
```

Registers a device node at `Path`. The `TVFSDeviceOps` record is **deep-copied** so the caller's record can be stack-allocated. `DevData` is stored as-is (not copied).

The parent directory must exist and be a virtual directory.

Returns:
- `eNone` — success
- `eInvalidArgument` — nil path or ops
- `eDirectoryDoesNotExist` — parent not found
- `eNotADirectory` — parent is not a virtual directory
- `eAlreadyExists` — name already taken

### Built-in Devices

| Path | Read | Write | Size |
|------|------|-------|------|
| `/dev/null` | Returns 0 bytes (EOF) | Accepts and discards all data | 0 |
| `/dev/zero` | Fills buffer with zero bytes | Accepts and discards all data | 0 |

### Example: Registering a Custom Device

```pascal
function MyDev_Read(devData : pointer; offset : uint32; buffer : puint8; length : uint32) : uint32;
begin
    { Fill buffer with 'A' characters }
    memset(uint32(buffer), ord('A'), length);
    MyDev_Read := length;
end;

var
    ops : TVFSDeviceOps;
begin
    ops.Read  := @MyDev_Read;
    ops.Write := nil;
    ops.Size  := nil;
    RegisterDevice('/dev/mydevice', @ops, nil);
end;
```

The device can then be used with the standard file API:

```pascal
var
    h   : TFileHandle;
    err : TError;
    buf : array[0..15] of uint8;
begin
    h := OpenFile('/dev/mydevice', omRead, @err);
    ReadFile(h, 0, @buf[0], 16);  { buf now contains 16 'A' bytes }
    CloseFile(h);
end;
```

---

## Watch / Notify

Directory watches fire a callback whenever the watched directory is mutated (child created, deleted, renamed, or modified).

### `WatchDirectory`

```pascal
function WatchDirectory(
    Path     : pchar;
    Callback : TVFSWatchCallback;
    UserData : pointer
) : uint32;
```

Registers a watch on a directory path. Returns a non-zero watch ID on success, `0` on failure (nil args, path doesn't exist, or table full). Maximum 32 concurrent watches.

### `UnwatchDirectory`

```pascal
procedure UnwatchDirectory(WatchID : uint32);
```

Removes a watch by ID. Safe to call with `0` or invalid IDs.

### Callback Signature

```pascal
TVFSWatchCallback = procedure(
    event    : TVFSWatchEvent;
    path     : pchar;
    userdata : pointer
);
```

- `event` — what kind of mutation occurred
- `path` — the absolute path of the affected entry
- `userdata` — the opaque pointer passed at registration time

---

## Error Codes

All functions that return `TError` use the shared error codes defined in `driver.storage.types`. The most commonly returned codes from VFS operations are:

| Code | Meaning |
|------|---------|
| `eNone` | Success |
| `eInvalidArgument` | Nil pointer or invalid parameter |
| `eInvalidPath` | Malformed or unresolvable path |
| `eInvalidHandle` | Handle is not open |
| `eInvalidFileName` | Resolved filename is empty or invalid |
| `eFileDoesNotExist` | Path resolves but no file found |
| `eDirectoryDoesNotExist` | Parent directory not found |
| `eNotADirectory` | Path component is not a directory |
| `eAlreadyExists` | Target name already exists |
| `eTooManyOpenFiles` | Per-process FD table full (max 64) |
| `eNotStreamMode` | SeekFile on non-stream handle |
| `eFileNotLoaded` | Read on handle whose data hasn't loaded |
| `eReadOnly` | Write on read-only handle |

See [driver.storage.types.pas](../src/driver/storage/driver.storage.types.pas) for the full `TError` enumeration.

---

## Ownership & Lifetime Rules

1. **File handles** — Must be closed with `CloseFile` when no longer needed. All handles are per-process and automatically closed on process exit.
2. **Directory listings** — `GetDirectoryListingFrom` / `GetDirectoryListingAsync` return caller-owned snapshots. Always call `FreeDirectoryListing()`.
3. **Heap strings** — `MakeAbsolutePath`, `MakeAbsolutePathFrom`, `GetWorkingDirectory`, and `ChangeDirectoryFrom` (via `NewDir`) return heap-allocated strings. Caller must `kfree()`.
4. **Async buffers** — All buffers passed to async functions must remain valid until the completion callback fires.
5. **Device ops** — The `TVFSDeviceOps` record is deep-copied by `RegisterDevice`. The caller's record can be stack-local. However, `DevData` is stored by pointer — its lifetime must exceed the device registration.
