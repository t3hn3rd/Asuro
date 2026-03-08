# core.enc.fnv1a

FNV-1a (Fowler-Noll-Vo) non-cryptographic hash in 32-bit and 64-bit widths.

## Overview

`core.enc.fnv1a` implements the FNV-1a variant of the Fowler-Noll-Vo hash algorithm. FNV-1a XORs each input byte into the hash value before multiplying by the FNV prime, which provides better avalanche characteristics than the original FNV-1 (which multiplies first). The algorithm is simple, fast, and produces well-distributed hashes suitable for hash tables, Bloom filters, and checksums.

FNV-1a is the primary hash function used by `core.ds.hashmap` (key hashing) and `core.ds.bloom` (first of two hash functions in the double-hashing scheme).

## Dependencies

- `io.syslog` — test output (implementation only)
- `memory.heap` — `kfree` (implementation only)
- `core.strings` — test output formatting (implementation only)

## Functions and Procedures

### Hash_FNV1a32
```pascal
function Hash_FNV1a32(Data : void; DataLen : uint32) : uint32;
```
Computes a 32-bit FNV-1a hash of `DataLen` bytes starting at `Data`.
- Initial basis: `$811C9DC5`
- FNV prime: `$01000193`
- Per byte: `h = (h xor byte) * prime`

Zero-length input returns the basis value `$811C9DC5`.

### Hash_FNV1a64
```pascal
function Hash_FNV1a64(Data : void; DataLen : uint32) : uint64;
```
Computes a 64-bit FNV-1a hash.
- Initial basis: `$CBF29CE484222325`
- FNV prime: `$00000100000001B3`

Zero-length input returns the basis value.

### UnitTest
```pascal
procedure UnitTest;
```
Runs the FNV-1a test suite (known basis for empty input, determinism, distinctness for different inputs, length sensitivity, independence of 32-bit and 64-bit variants) and logs a pass/fail summary to syslog under the `'FNV1A'` channel.

## Notes

Both functions are purely computational with no side effects or allocations. They may be called from any context.

The low 32 bits of `Hash_FNV1a64` are not guaranteed to equal `Hash_FNV1a32` for the same input; they are independent algorithms.
