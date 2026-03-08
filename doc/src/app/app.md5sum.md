# app.md5sum

Terminal command for computing the MD5 checksum of a string.

## Overview

`app.md5sum` registers the `MD5SUM` shell command, which computes and prints the MD5 digest of the first command-line argument. The 16-byte digest is printed as 32 uppercase hexadecimal characters.

## Dependencies

- `io.stdio`
- `core.util`, `arch.x86.util`
- `core.strings`
- `debug.tracer`
- `core.enc.md5`

## Functions and Procedures

### init

```pascal
procedure init();
```

Registers the `MD5SUM` command with `io.stdio`.

### run (internal)

```pascal
procedure run(Params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
```

Command entry point. Takes the first parameter as the input string, computes its MD5 digest using `core.enc.md5.MD5Buffer`, and writes the 16 digest bytes to `stdout_buf` as hex pairs using `bufWriteHexPair`. A trailing space and newline are appended.

## Notes

Only the first parameter is hashed. Multi-word input must be quoted or joined before passing. The `PMD5Digest` pointer returned by `MD5Buffer` is used directly; the caller does not free it (it is assumed to be a static or stack-local result from the MD5 implementation).
