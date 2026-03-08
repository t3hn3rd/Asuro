# core.enc.sha1

SHA-1 message-digest hash.

## Overview

`core.enc.sha1` implements the SHA-1 hash algorithm (FIPS 180-4) for the kernel. It provides an incremental streaming interface (`SHA1Init` / `SHA1Update` / `SHA1Final`) for computing 160-bit digests over data arriving in multiple chunks. The implementation uses big-endian byte order for state words and digest output, as required by the SHA-1 specification.

## Dependencies

- `core.util` — `memset`
- `arch.x86.util` — `RolDWord`, `RorDWord` (32-bit rotate operations)

## Types

### TSHA1Digest / PSHA1Digest
```pascal
TSHA1Digest = array[0..19] of byte;
```
A 20-byte (160-bit) SHA-1 digest.

### TSHA1Context / PSHA1Context
```pascal
TSHA1Context = record
    State : array[0..4] of cardinal;
    Buffer: array[0..63] of uint8;
    BufCnt: uint32;
    Length: QWord;
end;
```
Incremental hashing context. `State` holds the five 32-bit SHA-1 state words initialised to the standard constants. `Buffer` is a 64-byte block accumulation buffer. `BufCnt` tracks the number of bytes currently in `Buffer`. `Length` accumulates the total number of complete 64-byte blocks processed (in bytes).

## Functions and Procedures

### SHA1Init
```pascal
procedure SHA1Init(ctx : PSHA1Context);
```
Initialises the SHA-1 context to the standard initial state:
- `State[0] = $67452301`
- `State[1] = $EFCDAB89`
- `State[2] = $98BADCFE`
- `State[3] = $10325476`
- `State[4] = $C3D2E1F0`

Must be called before any `SHA1Update` calls.

### SHA1Update
```pascal
procedure SHA1Update(ctx : PSHA1Context; buffer : puint8; bufferLen : uint32);
```
Feeds `bufferLen` bytes from `buffer` into the hash context. Internally buffers partial blocks and calls `SHA1Transform` when a complete 64-byte block is assembled. May be called multiple times.

### SHA1Final
```pascal
procedure SHA1Final(ctx : PSHA1Context; digest : PSHA1Digest);
```
Finalises the hash by appending SHA-1 padding (0x80 followed by zeroes) and the 64-bit big-endian message bit-length. Writes the 20-byte digest into the caller-supplied `digest` buffer. Zeroes the context after extraction.

Unlike `MD5Final`, `SHA1Final` does not allocate a digest buffer; the caller must provide one.

## Notes

SHA-1 is no longer considered cryptographically secure for collision resistance. It should not be used for new security-critical applications. It is included in Asuro for compatibility with existing protocols or formats that require it.

The internal `SHA1Transform` function processes data in big-endian format using the helper `Invert` to convert the 64-byte input buffer into 16 big-endian `uint32` words before applying the four SHA-1 rounds (0–19, 20–39, 40–59, 60–79).

`SHA1Final` does not allocate memory; the caller is responsible for providing a `TSHA1Digest`-sized buffer.
