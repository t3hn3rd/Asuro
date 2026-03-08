# driver.storage.ctl.ram

In-memory RAM drive for testing and built-in file hosting.

## Overview

The RAM drive provides a virtual storage device backed entirely by memory. It is mounted at `/disk/ram` in the VFS at initialisation time and exposes a flat namespace of files. Files are stored as `(name, pointer, size)` tuples in a fixed-size table of up to `MAX_RAM_FILES` (32) entries.

The RAM drive is used for two purposes:
1. **Testing**: allows kernel and user-mode code to read and write files without requiring a physical disk.
2. **Built-in programs**: pre-loads compiled WASM binaries (e.g., a Hello World program) so they are available immediately after boot without mounting any filesystem.

The driver implements three VFS callbacks: `readCallback` (full-file load), `readOffsetCallback` (streaming partial reads), and `readDirCallback` (directory listing). It does not implement write callbacks; the RAM drive is effectively read-only through the VFS layer (write is done via the `storeFile` / `storeFileCopy` API).

## Dependencies

- `driver.storage.vfs`
- `debug.tracer`
- `io.syslog`
- `driver.storage.types`
- `core.strings` (implementation)
- `memory.heap` (implementation)
- `core.ds.lists` (implementation)
- `core.util`, `arch.x86.util` (implementation)

## Functions and Procedures

### init

```pascal
procedure init;
```

Zeroes the file table, sets up the `RAMFS` filesystem descriptor with the three read callbacks, creates a virtual `RAMVolume`, mounts it at `/disk/ram` via `driver.storage.vfs.mountVolume`, and pre-loads built-in programs by calling `loadBuiltins`.

### storeFile

```pascal
function storeFile(name : pchar; data : puint8; size : uint32) : boolean;
```

Registers a file in the RAM drive. The `data` pointer is stored directly — the buffer is **not** copied. If a file with the same name already exists, its data pointer and size are updated. Returns true on success, false if the table is full or parameters are invalid.

### storeFileCopy

```pascal
function storeFileCopy(name : pchar; data : puint8; size : uint32) : boolean;
```

Like `storeFile`, but first allocates a heap copy of `data`. Use this when the original buffer may be freed after the call.

### removeFile

```pascal
procedure removeFile(name : pchar; freeBuf : boolean);
```

Removes a file entry by name. If `freeBuf` is true, `kfree`s the data buffer. The name string stored in the entry is always freed.

## Notes

- `MAX_RAM_FILES` is 32. Exceeding this limit causes `storeFile` to return false without storing the file.
- The built-in Hello World WASM binary (`hello`) is pre-loaded by `loadBuiltins`. It is a 185-byte WASM module that calls `fd_write` to print `"Hello, World!\n"` and then exits.
- VFS passes paths to the read callbacks with a leading `/`; the internal `stripLeadingSlash` helper removes it before the name table lookup.
- The RAM drive has no persistent storage; all files are lost when the system powers off or reboots.
