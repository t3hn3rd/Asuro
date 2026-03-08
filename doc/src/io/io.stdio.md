# io.stdio

Standard I/O abstraction providing output buffers, a dynamic command registry, and parameter parsing for shell commands.

## Overview

`io.stdio` is the central I/O layer that connects the shell, terminal emulators, and command implementations. It provides three services:

1. **Output buffers (`POutBuf`)** — heap-allocated, growable byte buffers used as stdin, stdout, and stderr for every command invocation. Buffers double in capacity when full.

2. **Command registry** — a dynamically-growing array of `TCommand` records. Commands are registered by name with a `TCommandMethod` callback; `findCommand` performs case-insensitive lookup. The registry starts at capacity 64 and doubles when full.

3. **Parameter parsing** — `getParams` splits a null-terminated command line into a singly-linked `TParamList`. `getParam(0, params)` returns the command name; arguments start at index 1, matching the convention used by `paramCount`.

A halt/resume mechanism (`halt`/`done`) allows async commands such as PING to signal completion back to the terminal.

`init` registers six built-in commands: `VERSION`, `CLEAR`, `HELP`, `ECHO`, `TIME`, and `REBOOT`.

## Dependencies

- `memory.heap`
- `core.strings`, `core.util`, `arch.x86.util`
- `debug.tracer`
- `core.version`, `driver.timer.rtc`, `driver.io.serial`, `driver.storage.vfs`, `io.syslog`

## Constants

### INITIAL_CMD_CAP
`64` — Initial capacity of the command registry array. Doubles on overflow.

## Types

### TOutBuf / POutBuf

```pascal
TOutBuf = record
    buf : pchar;
    len : uint32;
    cap : uint32;
end;
```

Growable output buffer. `buf` is a heap-allocated character array. `len` is the current byte count (excluding the null terminator). `cap` is the allocated capacity. The buffer always maintains a null terminator at `buf[len]`.

### TParamList / PParamList

```pascal
TParamList = record
    Param : pchar;
    Next  : PParamList;
end;
```

Singly-linked list of null-terminated parameter strings produced by `getParams`. The head node holds the command name; subsequent nodes hold the arguments.

### TCommandBuffer

```pascal
TCommandBuffer = array[0..1023] of byte;
```

Fixed-size input buffer type passed to `getParams` for command-line splitting.

### TCommandMethod

```pascal
TCommandMethod = procedure(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
```

Signature for all registered command callbacks. `params` is the parsed argument list. The three `POutBuf` pointers give the command access to its I/O streams.

### TCommand / PCommand

```pascal
TCommand = record
    registered  : boolean;
    hidden      : boolean;
    command     : pchar;
    method      : TCommandMethod;
    description : pchar;
end;
```

Entry in the command registry. `hidden` commands are omitted from `HELP` output.

### THaltCallback

```pascal
THaltCallback = procedure();
```

Optional callback invoked when `done` clears the halt state.

## Functions and Procedures

### createOutBuf / freeOutBuf / bufClear

```pascal
function  createOutBuf(initial_cap: uint32): POutBuf;
procedure freeOutBuf(buf: POutBuf);
procedure bufClear(buf: POutBuf);
```

Allocate a new output buffer with the given initial capacity (minimum 1), free a buffer and its internal storage, or reset a buffer's length to zero without releasing memory.

### bufWriteChar / bufWriteStr / bufWriteStrLn / bufWriteNewLine

```pascal
procedure bufWriteChar(buf: POutBuf; c: char);
procedure bufWriteStr(buf: POutBuf; s: pchar);
procedure bufWriteStrLn(buf: POutBuf; s: pchar);
procedure bufWriteNewLine(buf: POutBuf);
```

Append a single character, a null-terminated string, a string followed by LF (`#10`), or a bare LF to the buffer. The buffer is grown via `bufGrow` as needed.

### bufWriteInt / bufWriteIntLn

```pascal
procedure bufWriteInt(buf: POutBuf; i: integer);
procedure bufWriteIntLn(buf: POutBuf; i: integer);
```

Format a signed integer in decimal and append it to the buffer, with or without a trailing newline.

### bufWriteHexPair / bufWriteHex / bufWriteHexLn

```pascal
procedure bufWriteHexPair(buf: POutBuf; b: uint8);
procedure bufWriteHex(buf: POutBuf; i: uint32);
procedure bufWriteHexLn(buf: POutBuf; i: uint32);
```

Append a two-digit uppercase hex byte pair, a `0x`-prefixed 8-digit hex value, or the same with a trailing newline.

### bufWriteBin8 / bufWriteBin8Ln / bufWriteBin16 / bufWriteBin16Ln / bufWriteBin32 / bufWriteBin32Ln

Append binary representations of 8-, 16-, or 32-bit values (MSB first), with or without a trailing newline.

### bufSetColor / bufResetColor

```pascal
procedure bufSetColor(buf: POutBuf; fg: uint8);
procedure bufResetColor(buf: POutBuf);
```

Append ANSI escape sequences. `bufSetColor` writes `ESC[38;5;<n>m` (256-color foreground); `bufResetColor` writes `ESC[0m`.

### registerCommand / registerCommandEx

```pascal
procedure registerCommand(command: pchar; method: TCommandMethod; description: pchar);
procedure registerCommandEx(command: pchar; method: TCommandMethod; description: pchar; hide: boolean);
```

Add a command to the registry. `registerCommandEx` additionally accepts a `hide` flag; hidden commands are excluded from `HELP` listing.

### getCommandCount / getCommand / findCommand

```pascal
function getCommandCount: uint32;
function getCommand(index: uint32): PCommand;
function findCommand(name: pchar): PCommand;
```

Query the registry. `findCommand` performs a case-insensitive linear search; temporary uppercase copies of the name and each command are allocated from the heap and freed immediately.

### getParams / freeParams / paramCount / getParam

```pascal
function  getParams(var buf: TCommandBuffer): PParamList;
procedure freeParams(params: PParamList);
function  paramCount(params: PParamList): uint32;
function  getParam(index: uint32; params: PParamList): pchar;
```

Split a command buffer into a linked list, free it, count non-command parameters (i.e. `paramCount` returns the argument count excluding the command name at index 0), or retrieve the parameter at a given index.

### getWorkingDirectory / setWorkingDirectory

```pascal
function  getWorkingDirectory: pchar;
procedure setWorkingDirectory(str: pchar);
```

Delegate to `driver.storage.vfs.getWorkingDirectory` and `driver.storage.vfs.changeDirectory` respectively.

### halt / done

```pascal
function halt(id: uint32; cb: THaltCallback): boolean;
function done(id: uint32): boolean;
```

Claim the global halt state for async commands. `halt` sets `Halted := true` and returns `true` if no halt is already active; `done` clears the halt for the matching ID, invokes the optional callback, and returns `true`. Only one halt is active at a time.

### init

```pascal
procedure init;
```

Allocates the initial command array, initializes the halt state, and registers the six built-in commands.

## Built-in Commands

| Command | Description |
|---|---|
| `VERSION` | Displays version string, compile date/time, line count, file count, driver count, and checksum. |
| `CLEAR` | Sends ANSI clear-screen escape sequences (`ESC[2J ESC[H`). |
| `HELP` | Lists all non-hidden registered commands and their descriptions, aligned to the longest command name. |
| `ECHO` | Echoes all arguments (from index 1 onwards) separated by spaces. |
| `TIME` | Prints the current RTC date and time in `DD/MM/YYYY HH:MM:SS` format plus the weekday name. |
| `REBOOT` | Calls `resetSystem` to reboot the machine. |

## Notes

`getParam(0, params)` returns the command name (the first token). Arguments begin at index 1, so `paramCount` returns `total_tokens - 1` to reflect the number of arguments available to the command.

All nil-pointer guards are present on buffer write helpers; passing a nil buffer is a silent no-op, making it safe to discard stdout or stderr by passing nil.
