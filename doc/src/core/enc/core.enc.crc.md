# core.enc.crc

CRC-32 checksum computation.

## Overview

`core.enc.crc` implements the standard CRC-32 algorithm using a pre-computed 256-entry lookup table (IEEE 802.3 polynomial `0xEDB88320` reflected). It is used for data integrity verification throughout the kernel.

## Dependencies

None.

## Functions and Procedures

### CRC32
```pascal
function CRC32(p : puint8; size : uint32) : uint32;
```
Computes the CRC-32 checksum of `size` bytes starting at pointer `p`. The initial value is `$FFFFFFFF` and the result is bitwise inverted before returning, following the standard CRC-32 finalisation step.

## Notes

The lookup table is a compile-time constant array of 256 `uint32` values. No initialisation is required at runtime.

The algorithm processes one byte at a time using the standard table-driven update: `CRC = table[(CRC xor byte) and $FF] xor (CRC shr 8)`.

This implementation is suitable for file/block integrity checks but is not cryptographically secure.
