# core.enc.base64

Base64 encoding and decoding.

## Overview

`core.enc.base64` implements RFC 4648 Base64 encoding and decoding for the kernel. It operates on raw byte buffers or null-terminated strings and returns heap-allocated results. The encoder inserts a newline character every 72 output characters and appends `=` padding to complete the final group. The decoder ignores whitespace and newlines in the input.

## Dependencies

- `memory.heap` — `kalloc`, `kfree`
- `core.strings` — `stringSize`
- `debug.tracer` — call-stack tracing
- `core.util` — `memset`
- `arch.x86.util` — architecture utilities

## Constants

### base64_enc_map
A 64-element character array containing the standard Base64 alphabet (`A`–`Z`, `a`–`z`, `0`–`9`, `+`, `/`). Used by the encoder to map 6-bit values to output characters.

## Functions and Procedures

### b64_encode
```pascal
function b64_encode(src : PuInt8; len : uInt32; out_len : PuInt32) : PuInt8;
```
Encodes `len` bytes from `src` into a heap-allocated Base64 string. If `out_len` is not `nil`, the output length (including the trailing null byte) is written there. Returns `nil` if the output length calculation overflows.

### b64_decode
```pascal
function b64_decode(src : PuInt8; len : uInt32; out_len : PuInt32) : PuInt8;
```
Decodes `len` bytes of Base64 data from `src` into a heap-allocated raw byte buffer. If `out_len` is not `nil`, the decoded byte count is written there. Returns `nil` if the input is invalid or allocation fails.

### b64_encode_str
```pascal
function b64_encode_str(src : PChar) : PChar;
```
Convenience wrapper: encodes the null-terminated string `src` and returns a heap-allocated Base64 string. Pushes tracer entries on entry and return.

### b64_decode_str
```pascal
function b64_decode_str(src : PChar) : PChar;
```
Convenience wrapper: decodes the null-terminated Base64 string `src` and returns a heap-allocated decoded string. Pushes tracer entries on entry and return.

## Notes

The encoder output includes newlines after every 72 characters. Consumers that do not expect line breaks should strip them or use `b64_encode` directly and handle the output buffer themselves.

The decoder builds a 256-entry decode table on the stack at each call. Unknown characters are mapped to `$80` (the sentinel for "skip"). Padding characters (`=`) are mapped to `0` and their count is tracked to trim the output length.

If the input to `b64_decode` is not a multiple of 4 valid Base64 characters, the function currently enters an unhandled branch (silent error). Callers should validate input length before decoding.

Both `b64_encode` and `b64_decode` return heap-allocated buffers that must be freed by the caller with `kfree`.
