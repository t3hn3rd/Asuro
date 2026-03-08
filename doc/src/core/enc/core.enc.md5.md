# core.enc.md5

MD5 message-digest checksum.

## Overview

`core.enc.md5` implements the MD5 hash algorithm (RFC 1321) for the kernel. It provides an incremental streaming interface (`MD5Init` / `MD5Update` / `MD5Final`) for computing digests over data that arrives in multiple chunks, as well as a single-call convenience function (`MD5Buffer`) for hashing a complete buffer at once. A utility function (`MD5To32`) folds a 128-bit digest to a 32-bit value for use as a compact key.

MD5 is used in Asuro for file integrity verification and as a legacy key-hash function (replaced by FNV-1a in the hash map but retained for compatibility).

## Dependencies

- `core.util` — `memset`, `memcpy`
- `arch.x86.util` — `roldword` (32-bit left rotate)
- `memory.heap` — `kalloc`, `kfree`
- `debug.tracer` — call-stack tracing

## Constants

### MD5DefineBufferSize
Internal working buffer size: `1024`. Not directly used by callers.

## Types

### TMD5Context / PMD5Context
```pascal
TMD5Context = record
    Align       : uInt32;
    State       : array[0..3] of uInt32;
    BufferCount : uInt64;
    Buffer      : array[0..63] of uInt8;
    Length      : uInt64;
    Checksum    : array[0..15] of uInt8;
end;
```
Incremental hashing context. `State` holds the four 32-bit MD5 state words. `Buffer` is an internal 64-byte accumulation buffer. `Length` tracks the total number of bytes processed by `MD5Transform`. `BufferCount` tracks how many bytes are currently buffered. `Align` is set to 64 (the block size).

### TMD5Digest / PMD5Digest
```pascal
TMD5Digest = array[0..15] of uInt8;
```
A 16-byte MD5 digest. Returned as a heap-allocated pointer by `MD5Final` and `MD5Buffer`.

## Functions and Procedures

### MD5Init
```pascal
procedure MD5Init(context : PMD5Context);
```
Initialises an `MD5Context` to the standard MD5 initial state. Must be called before any `MD5Update` calls.

### MD5Update
```pascal
procedure MD5Update(context : PMD5Context; buffer : PuInt8; bufferLen : uInt32);
```
Feeds `bufferLen` bytes from `buffer` into the hash context. May be called multiple times to hash data arriving in chunks.

### MD5Final
```pascal
function MD5Final(context : PMD5Context) : PMD5Digest;
```
Finalises the hash by appending MD5 padding and the message length, then extracts and returns a heap-allocated 16-byte digest. Zeroes the context after use. The caller must free the returned digest with `kfree`.

### MD5Buffer
```pascal
function MD5Buffer(buffer : PuInt8; bufferLen : uInt32) : PMD5Digest;
```
Convenience function: allocates a context, runs `MD5Init` + `MD5Update` + `MD5Final`, frees the context, and returns the digest. The caller must free the returned digest with `kfree`.

### MD5To32
```pascal
function MD5To32(Input : PuInt128) : uint32;
```
Folds a 128-bit MD5 digest to a 32-bit value by XOR-ing the four 32-bit words of the digest. Useful as a compact hash key derived from a full MD5 digest.

## Notes

MD5 is not cryptographically secure and must not be used for security-critical purposes such as password hashing or digital signatures. It is retained in Asuro for non-security integrity checks and legacy compatibility.

`MD5Transform` operates on data in little-endian byte order, consistent with the MD5 specification. The internal `Invert` helper reorders bytes from a byte buffer into little-endian `uint32` words.
