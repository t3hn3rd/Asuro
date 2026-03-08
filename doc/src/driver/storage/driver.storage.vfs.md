# driver.storage.vfs

Virtual File System — unified path-based interface over all mounted volumes and virtual directories.

## Overview

The VFS layer presents a single hierarchical namespace to the rest of the kernel and to user processes. It manages an in-memory tree of `TVFSObject` nodes rooted at `/`. Four top-level virtual directories are created at initialisation: `/disk`, `/dev`, `/mnt`, and `/cfg`. Storage volumes are mounted under `/disk/<name>` via `mountVolume`.

File handles (`TFileHandle`) are 1-based indices into a per-process file descriptor table (`TFDTable`). The VFS is the only layer that touches the FD table directly; all higher-level code uses the handle opaquely.

The VFS supports both synchronous and asynchronous operations. Sync functions call the filesystem driver's synchronous hooks; async functions call async hooks if available, otherwise fall back to the sync hooks. Path resolution handles `.` and `..` traversal, relative paths anchored to the current process working directory, and mount-point transparency.

## Dependencies

- `driver.storage.fdtable`
- `core.ds.hashmap`
- `core.ds.lists`
- `memory.heap`
- `driver.storage.types`
- `core.strings`
- `io.syslog`
- `debug.tracer`
- `driver.storage.fs.mgr` (implementation)
- `proc.mgr`, `proc.types` (implementation)
- `io.stdio` (implementation)
- `core.util`, `arch.x86.util` (implementation)
- `driver.storage.vol.mgr` (implementation)

## Types

### TOpenMode

`(omReadOnly, omWriteOnly, omReadWrite, omStream)` — controls which operations are permitted on an open file handle, and whether data is pre-loaded (`omStream` enables on-demand offset reads).

### TWriteMode

`(wmRewrite, wmAppend, wmNew)` — controls write positioning semantics.

### TIsPathValid

`(pvInvalid, pvFile, pvDirectory)` — result of path resolution.

### TRegError

`(pvUnknown, pvNotRegistered, pvRegistered, pvUnregistered)` — result of mount/unmount operations.

### TFileHandle

`uint32` — 1-based file descriptor handle. 0 indicates an invalid/unallocated handle.

### TObjectType

`(otVDIRECTORY, otDRIVE, otDEVICE, otVFILE, otMOUNT, otDIRECTORY, otFILE)` — classifies a node in the VFS object tree.

### TVFSObject / PVFSObject

Internal VFS tree node.

| Field | Description |
|---|---|
| `Parent` | Pointer to parent node (nil for root) |
| `ObjectName` | Name of this node |
| `ObjectType` | Node type |
| `Reference` | Type-specific payload: `PHashMap` for virtual directories, `PStorage_Volume` for mounts |

### TVFSMount / PVFSMount

Lightweight mount record used in the flat mount table (legacy; the tree model is primary).

## Variables

| Name | Description |
|---|---|
| `Root` | Pointer to the VFS root `TVFSObject` |
| `PushPopDirectory` | Linked list used by pushd/popd-style directory stack |

## Functions and Procedures

### init

```pascal
procedure init();
```

Initialises the VFS root object and creates the top-level virtual directories `/disk`, `/dev`, `/mnt`, and `/cfg`.

### OpenFile

```pascal
function OpenFile(Filename : pchar; OpenMode : TOpenMode; WriteMode : TWriteMode; Error : PError) : TFileHandle;
```

Resolves `Filename` to an absolute path, locates the mount point, allocates a file descriptor in the current process's FD table, and pre-loads the file data for `omReadOnly`/`omReadWrite` modes. Returns a non-zero handle on success. `Error` is set to a `TError` code on failure.

For `omStream` mode, data is not pre-loaded; subsequent `ReadFile` calls use the offset-based read hook.

### WriteFile

```pascal
function WriteFile(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
```

Writes `Length` bytes from `Buffer` to the file identified by `FileHandle`. `Position` is currently unused (write behaviour is determined by the `WriteMode` set at open time). Returns the number of bytes written.

### ReadFile

```pascal
function ReadFile(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
```

Reads up to `Length` bytes into `Buffer`. For pre-loaded files, copies from the in-memory buffer starting at `Position`. For stream handles, calls the filesystem's `readOffsetCallback` at the current `StreamOff` and advances the offset. Returns the number of bytes read.

### CloseFile

```pascal
function CloseFile(Filehandle : TFileHandle) : TError;
```

Releases the file descriptor, frees the pre-loaded data buffer and path strings. Returns `eNone` on success, `eInvalidHandle` if the handle is not open.

### WriteFileAsync

```pascal
procedure WriteFileAsync(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32; Callback : TIOCallback; CallbackData : pointer);
```

Non-blocking write. Returns immediately; `Callback` is fired on completion. Callers must keep all buffers alive until the callback fires.

### OpenFileAsync

```pascal
procedure OpenFileAsync(Filename : pchar; OpenMode : TOpenMode; WriteMode : TWriteMode; var OutHandle : TFileHandle; Error : PError; Callback : TIOCallback; CallbackData : pointer);
```

Non-blocking file open. Allocates the FD synchronously, then issues an async read to populate the data buffer. `Callback` fires when the FD is ready for use.

### FileSize

```pascal
function FileSize(Filename : pchar; error : PError) : uint32;
```

Returns the size in bytes of the named file by opening it, reading the size, and closing it. Returns 0 on failure.

### CreateDirectory

```pascal
function CreateDirectory(Handle : uint32; Path : pchar) : TError;
```

Creates a directory at `Path` on the volume identified by `Handle`. Delegates to the filesystem's `createDirCallback`.

### GetDirectories

```pascal
function GetDirectories(Handle : uint32; Path : pchar) : PHashMap;
```

Returns a `PHashMap` of directory entries for `Path` on the volume identified by `Handle`.

### PathValid

```pascal
function PathValid(Path : pchar) : TIsPathValid;
```

Resolves `Path` (which may contain `.` and `..`) and returns `pvFile`, `pvDirectory`, or `pvInvalid`. Handles paths that traverse into mounted volumes.

### changeDirectory

```pascal
function changeDirectory(Path : pchar) : TIsPathValid;
```

Changes the current process working directory to `Path`. Returns the validation result.

### getWorkingDirectory

```pascal
function getWorkingDirectory : pchar;
```

Returns the current process working directory string. The caller must not free this pointer.

### makeAbsolutePathFrom

```pascal
function makeAbsolutePathFrom(Path : pchar; BaseDir : pchar) : pchar;
```

If `Path` is already absolute, returns a copy. Otherwise, joins `BaseDir` and `Path`. Caller must free the result.

### resolvePathFrom

```pascal
function resolvePathFrom(Path : pchar; BaseDir : pchar) : TIsPathValid;
```

Resolves `Path` relative to `BaseDir` and returns its validity type without changing process state.

### GetDirectoryListingFrom

```pascal
function GetDirectoryListingFrom(Path : pchar; BaseDir : pchar) : PHashMap;
```

Returns the directory listing map for the resolved path. For virtual directories, returns the internal hashmap directly (do not free). For mounted volumes, returns a caller-owned map that should be freed with `FreeDirectoryListing`.

### FreeDirectoryListing

```pascal
procedure FreeDirectoryListing(map : PHashMap);
```

Frees a directory listing map returned by `GetDirectoryListingFrom` for disk-backed directories.

### changeDirectoryFrom

```pascal
function changeDirectoryFrom(Path : pchar; BaseDir : pchar; var NewDir : pchar) : TIsPathValid;
```

Resolves `Path` relative to `BaseDir`, and if valid, sets `NewDir` to the resolved absolute path (caller-owned). Does not modify process state.

### MakeAbsolutePath

```pascal
function MakeAbsolutePath(Path : PChar) : pchar;
```

Converts `Path` to an absolute path using the current process working directory. Caller must free the result.

### newVirtualDirectory

```pascal
function newVirtualDirectory(Path : pchar) : TError;
```

Creates a new in-memory virtual directory node at `Path`. The parent directory must already exist. Returns `eNone` on success, `eDirectoryDoesNotExist` if the parent is missing, or `eDirectoryAlreadyExists` if the path already exists.

### mountVolume

```pascal
function mountVolume(mountPath : pchar; volume : PStorage_Volume) : TRegError;
```

Mounts `volume` at `mountPath` in the VFS tree. The parent directory must exist. Returns `pvRegistered` on success.

### auto_mount_volumes

```pascal
procedure auto_mount_volumes();
```

Iterates all registered volumes and mounts each one under `/disk/vol<N>`. Called during boot after all devices are registered.

### UnitTest

```pascal
procedure UnitTest;
```

Runs the VFS unit test suite via `io.syslog`. Tests path manipulation, virtual directory creation, and directory listing correctness.

## Notes

- The VFS tree uses `core.ds.hashmap` at each virtual directory node for O(1) child lookup.
- The per-process FD table is managed by `driver.storage.fdtable`; the VFS accesses it via `proc.mgr.CurrentProcess^.FDTable`.
- Path evaluation (`evaluatePath`) resolves `.` and `..` using a forward-scan with stack semantics, handling consecutive `..` segments safely.
- For stream-mode handles, `ReadFile` advances `StreamOff` by the number of bytes actually returned by the offset hook, enabling sequential reads without the caller tracking position.
