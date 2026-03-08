# app.inio

Inline file I/O command for reading and writing VFS files from the terminal.

## Overview

`app.inio` registers the `INIO` shell command, which provides simple redirection-style file access directly from the terminal prompt. It supports two operations: reading a file's contents to the system log (`<`) and writing text to a file (`>`). Path arguments are resolved relative to the current working directory.

## Dependencies

- `io.syslog`, `io.stdio`, `debug.tracer`
- `memory.heap`
- `driver.storage.types`, `driver.storage.vfs`
- `core.strings`
- `core.util`, `arch.x86.util`

## Functions and Procedures

### init

```pascal
procedure init();
```

Registers the `INIO` command with `io.stdio`.

### Run (internal)

```pascal
procedure Run(Params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
```

Command entry point. Expects at least two parameters: a file path and an operator (`<` or `>`).

**Read mode (`<`):** Opens the file read-only, reads up to 32 KB, and writes the content to `io.syslog`. The read buffer is zeroed and freed after use.

**Write mode (`>`):** Joins all parameters from index 2 onward with spaces to form the content string, then opens the file for writing (attempting read-write rewrite first, then write-only new), writes the content, and closes the file.

The file path is resolved to an absolute path via `driver.storage.vfs.MakeAbsolutePath` before any VFS call.

Usage: `INIO <file> <` or `INIO <file> > text...`

## Notes

The read buffer is fixed at 32 KB. Files larger than this limit are silently truncated. Write operations overwrite the entire file contents.
