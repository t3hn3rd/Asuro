# io.syslog

Kernel logging subsystem with multi-hook fan-out to registered output consumers.

## Overview

`io.syslog` is the primary logging interface for all kernel and driver code. It maintains a static array of up to eight `TLogHook` callbacks and routes completed log lines to all registered hooks simultaneously. Additionally, every character written through `logChar` is sent immediately to `driver.io.serial` on COM1, providing a low-latency byte-level output channel that does not depend on the line-buffer flush cycle.

Log lines are accumulated in an internal 256-byte `LineBuf`. When a newline (`#10`) is received by `logChar`, `dispatchLine` null-terminates the buffer and calls each registered hook with the complete line string. CR characters (`#13`) are ignored during buffering.

The hook system targets line-level consumers such as file loggers or on-screen debug panels that prefer complete strings rather than individual characters. Because `logChar` already delivers characters to serial directly, registering a serial hook would cause duplicate output; no serial hook is registered by `init` for this reason.

## Dependencies

- `driver.io.serial`
- `core.strings`

## Constants

### MAX_HOOKS
`8` — Maximum number of simultaneously registered log hooks.

### LINE_BUF_SIZE
`256` — Internal line accumulation buffer capacity in bytes.

## Types

### TLogHook

```pascal
TLogHook = procedure(msg: pchar);
```

Callback signature for line-level log consumers. Called with a null-terminated string containing the completed line (without the trailing CR/LF).

## Functions and Procedures

### registerHook

```pascal
function registerHook(hook: TLogHook): boolean;
```

Adds `hook` to the hook array. Returns `true` on success, `false` if the array is full (`MAX_HOOKS` reached).

### removeHook

```pascal
procedure removeHook(hook: TLogHook);
```

Removes the first matching hook by compacting the array. Does nothing if the hook is not found.

### logChar

```pascal
procedure logChar(c: char);
```

Core character-level logging entry point. Sends `c` to COM1 via `driver.io.serial.send` immediately, then accumulates it in `LineBuf`. On newline, calls `dispatchLine` to fan out to all hooks.

### logFlush

```pascal
procedure logFlush;
```

Forces a dispatch of whatever is currently in `LineBuf`, even if no newline has been received. Useful for flushing partial lines before a halt or panic.

### log / logln

```pascal
procedure log(identifier: pchar; str: pchar);
procedure logln(identifier: pchar; str: pchar);
```

Write a bracketed log entry in the format `[identifier] str`. `logln` appends CR+LF. These are the standard logging macros used throughout the kernel.

### writestring / writestringln

```pascal
procedure writestring(str: pchar);
procedure writestringln(str: pchar);
```

Write a raw string without an identifier prefix, with or without a trailing CR+LF.

### writeint / writeintln

```pascal
procedure writeint(i: integer);
procedure writeintln(i: integer);
```

Format a signed decimal integer and write it to the log.

### writehexpair / writehex / writehexln

```pascal
procedure writehexpair(b: uint8);
procedure writehex(i: uint32);
procedure writehexln(i: uint32);
```

Write a two-digit hex byte, a `0x`-prefixed 8-digit hex value, or the same with a trailing newline.

### writebin8 / writebin8ln / writebin16 / writebin16ln / writebin32 / writebin32ln

Write binary representations of 8-, 16-, or 32-bit values (MSB first), with or without a trailing CR+LF.

### init

```pascal
procedure init;
```

Zeroes the hook array and resets `LinePos`. Does not register any hook; serial output is handled directly in `logChar`.

## Notes

`logChar` bypasses the line buffer for serial output by calling `driver.io.serial.send` on every character, ensuring that even partial lines and messages produced before a crash are visible on the serial console.

The line buffer is bounded at `LINE_BUF_SIZE - 1` characters; characters beyond this limit are silently dropped. This prevents unbounded accumulation during high-volume logging.

Hook functions must be non-blocking and must not call back into `io.syslog` as there is no re-entrancy protection. Suitable consumers include file writers and on-screen log panels that copy the string into their own buffers.
