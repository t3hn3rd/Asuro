# core.strings

Null-terminated string manipulation library for the kernel.

## Overview

`core.strings` provides a comprehensive set of routines for working with null-terminated (`pchar`) strings in a bare-metal environment. Because the kernel cannot use the Free Pascal runtime library string support, all allocation is performed through the kernel heap (`kalloc`/`kfree`) and all operations work on raw pointer-based C-style strings. The unit covers string creation, copying, comparison, searching, case conversion, concatenation, substring extraction, replacement, and conversion to and from integer types. A built-in `UnitTest` procedure exercises the full API and reports results via syslog.

## Dependencies

- `core.util` — `memcpy`, `memset`, `HexCharToDecimal`
- `arch.x86.util` — architecture-level utilities
- `memory.heap` — `kalloc`, `kfree`
- `core.ds.lists` — transitively required
- `io.syslog` — test output (implementation section only)

## Functions and Procedures

### stringNew
```pascal
function stringNew(size : uint32) : pchar;
```
Allocates a new zero-initialised string buffer of `size` bytes plus a null terminator. Returns a pointer to the buffer.

### stringCopy
```pascal
function stringCopy(str : pchar) : pchar;
```
Allocates and returns a heap copy of `str`.

### stringSize
```pascal
function stringSize(str : pchar) : uint32;
```
Returns the length of `str` in characters, excluding the null terminator. Returns 0 for `nil`.

### stringEquals
```pascal
function stringEquals(str1, str2 : pchar) : boolean;
```
Returns `true` if `str1` and `str2` have identical length and content.

### stringToUpper
```pascal
function stringToUpper(str : pchar) : pchar;
```
Returns a heap-allocated copy of `str` with all lowercase ASCII letters converted to uppercase.

### stringToLower
```pascal
function stringToLower(str : pchar) : pchar;
```
Returns a heap-allocated copy of `str` with all uppercase ASCII letters converted to lowercase.

### stringConcat
```pascal
function stringConcat(str1, str2 : pchar) : pchar;
```
Returns a heap-allocated string containing `str1` followed by `str2`.

### stringTrim
```pascal
function stringTrim(str : pchar; length : uint32) : pchar;
```
Returns a heap-allocated copy of `str` truncated to at most `length` characters. If `length` exceeds the string length, the full string is copied.

### stringSub
```pascal
function stringSub(str : pchar; start, size : uint32) : pchar;
```
Returns a heap-allocated substring of `str` beginning at byte offset `start` with at most `size` characters. Returns an empty string if `start` is past the end. If `start + size` exceeds the string length, the result is clamped to the end.

### stringMatchAt
```pascal
function stringMatchAt(str : pchar; pos : uint32; find : pchar) : boolean;
```
Returns `true` if `find` matches the characters in `str` starting at position `pos`. An empty `find` always returns `true`.

### stringIndexOf
```pascal
function stringIndexOf(str, find : pchar) : sint32;
```
Returns the zero-based index of the first occurrence of `find` within `str`, or `-1` if not found. An empty `find` returns `0`.

### stringContains
```pascal
function stringContains(str : pchar; sub : pchar) : boolean;
```
Returns `true` if `sub` appears anywhere within `str`.

### stringReplace
```pascal
function stringReplace(str, find, replace : pchar) : pchar;
```
Returns a heap-allocated copy of `str` with the first occurrence of `find` replaced by `replace`. If `find` is not present, a copy of `str` is returned unchanged.

### stringToInt
```pascal
function stringToInt(str : pchar) : uint32;
```
Parses a decimal integer string and returns its `uint32` value. Non-digit characters are ignored.

### intToString
```pascal
function intToString(i : uint32) : pchar;
```
Returns a heap-allocated decimal string representation of `i`.

### hexStringToInt
```pascal
function hexStringToInt(str : pchar) : uint32;
```
Parses a hexadecimal string (no `0x` prefix) and returns its `uint32` value.

### boolToString
```pascal
function boolToString(b : boolean; ext : boolean) : pchar;
```
Returns a heap-allocated string for the boolean `b`. When `ext` is `true`, returns `'true'` or `'false'`; when `false`, returns `'1'` or `'0'`.

### UnitTest
```pascal
procedure UnitTest;
```
Runs the complete string function test suite and logs a pass/fail summary to syslog under the `'STRINGS'` channel.

## Notes

All functions returning `pchar` return newly heap-allocated strings. Callers are responsible for freeing the result with `kfree` when it is no longer needed.

`stringReplace` replaces only the first occurrence of `find`. There is no bulk-replace variant.
