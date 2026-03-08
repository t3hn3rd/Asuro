# app.base64

Terminal command for Base64 encoding and decoding of text.

## Overview

`app.base64` registers the `BASE64` shell command, which allows the user to encode an arbitrary text string to Base64 or decode a Base64 string back to plain text. Multiple words passed after `encode` are joined with spaces before encoding.

## Dependencies

- `io.stdio`
- `core.util`, `arch.x86.util`
- `core.strings`
- `debug.tracer`
- `core.enc.base64`
- `memory.heap`

## Functions and Procedures

### init

```pascal
procedure init();
```

Registers the `BASE64` command with `io.stdio`. Must be called once at startup, typically from `app.mgr.init`.

### run (internal)

```pascal
procedure run(Params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
```

Command entry point. The first parameter selects the operation (`encode` or `decode`). For encoding, all subsequent parameters are concatenated with spaces into a single string before being passed to `b64_encode_str`. The resulting string is written to `stdout_buf` and then freed. For decoding, the second parameter is passed directly to `b64_decode_str`.

Usage: `BASE64 encode <text...>` or `BASE64 decode <base64string>`

## Notes

The encoded or decoded result is heap-allocated by the `core.enc.base64` routines and freed by this unit after writing to the output buffer. Passing an invalid operation string (anything other than `encode` or `decode`) prints usage information to `stderr_buf`.
