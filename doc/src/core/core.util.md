# core.util

Portable data manipulation utilities with no architecture-specific dependencies.

## Overview

`core.util` provides low-level helpers that operate on raw integers and memory without relying on any x86 assembly. It covers byte and nibble extraction, endian byte-order swapping, flat memory operations (`memset`/`memcpy`), BCD-to-integer conversion, hex character parsing, and a branchless absolute value. These primitives are used throughout the kernel wherever portable, assembly-free data manipulation is required.

## Dependencies

None.

## Functions and Procedures

### hi
```pascal
function hi(b : uint8) : uint8;
```
Returns the high nibble (bits 7–4) of a byte, shifted into the low four bits of the result. Exported with the alias `util_hi`.

### lo
```pascal
function lo(b : uint8) : uint8;
```
Returns the low nibble (bits 3–0) of a byte. Exported with the alias `util_lo`.

### switchendian
```pascal
function switchendian(b : uint8) : uint8;
```
Swaps the two nibbles of a byte (equivalent to a 4-bit rotate). Exported with the alias `util_switchendian`.

### switchendian16
```pascal
function switchendian16(b : uint16) : uint16;
```
Reverses the byte order of a 16-bit value, converting between big-endian and little-endian representations.

### switchendian32
```pascal
function switchendian32(b : uint32) : uint32;
```
Reverses the byte order of a 32-bit value for endian conversion.

### getWord
```pascal
function getWord(i : uint32; hi : boolean) : uint16;
```
Extracts the high or low 16-bit word from a 32-bit value. Returns bits 31–16 when `hi` is `true`; bits 15–0 otherwise.

### getByte
```pascal
function getByte(i : uint32; index : uint8) : uint8;
```
Extracts a single byte from a 32-bit value by zero-based byte index (0 = least significant byte).

### memset
```pascal
procedure memset(location : uint32; value : uint8; size : uint32);
```
Fills `size` bytes starting at address `location` with the byte `value`. Does nothing if `size` is zero.

### memcpy
```pascal
procedure memcpy(source : uint32; dest : uint32; size : uint32);
```
Copies `size` bytes from address `source` to address `dest` byte by byte. Behaviour is undefined if the regions overlap.

### BCDToUint8
```pascal
function BCDToUint8(bcd : uint8) : uint8;
```
Converts a Binary-Coded Decimal byte to its unsigned integer equivalent. The high nibble is the tens digit; the low nibble is the units digit.

### HexCharToDecimal
```pascal
function HexCharToDecimal(hex : char) : uint8;
```
Converts a single hexadecimal character (`0`–`9`, `a`–`f`, `A`–`F`) to its decimal value 0–15. Returns 0 for unrecognised characters.

### abs
```pascal
function abs(x : sint32) : uint32;
```
Returns the absolute value of a signed 32-bit integer using a branchless arithmetic technique based on sign-extension, XOR, and subtraction. The result type is `uint32`.

## Notes

`memcpy` is a simple byte loop and does not handle overlapping source and destination regions correctly. Callers must ensure regions do not overlap, or copy in the appropriate direction manually.

The `hi`, `lo`, and `switchendian` functions carry stable C-compatible export aliases (`util_hi`, `util_lo`, `util_switchendian`) for use from assembly or interop stubs.
