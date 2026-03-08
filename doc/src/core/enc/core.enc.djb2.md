# core.enc.djb2

DJB2 non-cryptographic hash functions in 32-bit and 64-bit widths.

## Overview

`core.enc.djb2` implements the DJB2 hash algorithm created by Daniel J. Bernstein. It provides fast, well-distributed hashing suitable for hash tables, Bloom filters, and string hashing. Two mixing strategies are provided — XOR and addition — in both 32-bit and 64-bit variants. All four variants share the same initial seed (`5381`) and the same shift-add structure (`h = ((h << 5) + h) op c`).

The XOR variant (`Hash_DJB2_32` / `Hash_DJB2_64`) is the classic djb2: `h = ((h << 5) + h) ^ c`.

The addition variant (`Hash_DJB2Add_32` / `Hash_DJB2Add_64`) uses `h = ((h << 5) + h) + c`, also known as the sdbm-style variant. It produces a different distribution and is used as the independent second hash in the double-hashing scheme of `core.ds.bloom`.

## Dependencies

- `io.syslog` — test output (implementation only)
- `memory.heap` — `kfree` (implementation only)
- `core.strings` — test output formatting (implementation only)

## Functions and Procedures

### Hash_DJB2_32
```pascal
function Hash_DJB2_32(Data : void; DataLen : uint32) : uint32;
```
Computes a 32-bit DJB2 XOR hash of `DataLen` bytes starting at `Data`. Zero-length input returns the initial seed `5381`.

### Hash_DJB2_64
```pascal
function Hash_DJB2_64(Data : void; DataLen : uint32) : uint64;
```
Computes a 64-bit DJB2 XOR hash. Zero-length input returns `uint64(5381)`.

### Hash_DJB2Add_32
```pascal
function Hash_DJB2Add_32(Data : void; DataLen : uint32) : uint32;
```
Computes a 32-bit DJB2 addition (sdbm-style) hash. Produces a distribution independent from `Hash_DJB2_32`, useful as a second hash in double-hashing schemes.

### Hash_DJB2Add_64
```pascal
function Hash_DJB2Add_64(Data : void; DataLen : uint32) : uint64;
```
Computes a 64-bit DJB2 addition hash.

### UnitTest
```pascal
procedure UnitTest;
```
Runs the DJB2 test suite (determinism, distinctness for different inputs, length sensitivity, XOR vs. addition independence) and logs a pass/fail summary to syslog under the `'DJB2'` channel.

## Notes

All four functions are purely computational with no side effects or allocations. They may be called freely from any context, including interrupt handlers.

The 32-bit and 64-bit variants are independent algorithms; the low 32 bits of the 64-bit result are not guaranteed to equal the 32-bit result for the same input.
