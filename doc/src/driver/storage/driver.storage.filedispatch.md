# driver.storage.filedispatch

File-type based dispatch registry for executable file formats.

## Overview

When the terminal encounters a token that is not a registered shell command, it asks the file dispatcher to identify the file and route execution to an appropriate handler. Handlers register a magic byte sequence and a callback function. On dispatch, the unit opens the file via VFS, reads the first bytes, matches them against all registered magic sequences, and invokes the matching handler.

This allows the kernel to support multiple executable formats (e.g., WASM) without hardcoding any format knowledge in the shell.

## Dependencies

- `io.stdio`
- `driver.storage.vfs` (implementation)
- `driver.storage.types` (implementation)
- `memory.heap` (implementation)
- `core.strings` (implementation)
- `debug.tracer` (implementation)
- `io.syslog` (implementation)
- `core.util`, `arch.x86.util` (implementation)

## Constants

### MAX_MAGIC_LEN

`8` — Maximum length of a magic byte sequence.

### MAX_HANDLERS

`16` — Maximum number of registered file-type handlers.

## Types

### TFileHandler

```pascal
TFileHandler = function(path : pchar;
                        params : PParamList;
                        stdin_buf, stdout_buf, stderr_buf : POutBuf) : uint32;
```

Handler callback invoked when a file's magic bytes match. Receives the resolved absolute path and the I/O buffers for the spawned process. Returns the PID of the created process, or 0 on failure.

## Functions and Procedures

### init

```pascal
procedure init;
```

Zeroes the handler table and resets the handler count. Must be called before any other function in this unit.

### registerHandler

```pascal
procedure registerHandler(magic : puint8; magicLen : uint8;
                          name : pchar; handler : TFileHandler);
```

Registers a file-type handler. `magic` points to `magicLen` bytes (1..`MAX_MAGIC_LEN`) that identify the format. `name` is a human-readable label stored in the entry (truncated to 15 characters). `handler` is invoked when a file matches. Does nothing if `magicLen` is out of range or the handler table is full.

### dispatch

```pascal
function dispatch(absPath : pchar;
                  params : PParamList;
                  stdin_buf, stdout_buf, stderr_buf : POutBuf) : uint32;
```

Attempts to dispatch `absPath` to a registered handler. The path must be a fully-resolved absolute VFS path.

1. Validates that `absPath` resolves to a file (`pvFile`).
2. Opens the file in read-only mode, reads up to `MAX_MAGIC_LEN` bytes, and closes the handle.
3. Iterates registered handlers and calls `matchMagic` against the header bytes.
4. Invokes the first matching handler and returns its PID result.
5. Returns 0 if no handler matched or if the file cannot be opened.

## Notes

- Handler matching iterates in registration order; there is no longest-match preference.
- The dispatcher performs no extension-based fallback; only magic-byte matching is implemented.
- All handler entries are stored in a fixed-size static array (`Handlers[0..MAX_HANDLERS-1]`); registration beyond `MAX_HANDLERS` entries is silently dropped.
