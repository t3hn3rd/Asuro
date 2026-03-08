# core.rand

Pseudo-random number generator for the kernel.

## Overview

`core.rand` implements a linear congruential generator (LCG) using the classic glibc constants (multiplier 1103515245, increment 12345) to produce pseudo-random values of 8, 16, and 32-bit widths. A single global state variable is maintained. The unit is intended for non-cryptographic use cases such as randomised data placement, simple simulations, or test data generation.

## Dependencies

None.

## Functions and Procedures

### rand32
```pascal
function rand32 : uint32;
```
Returns a 32-bit pseudo-random value formed by combining two successive 15-bit LCG outputs in the high and low 16-bit halves.

### rand16
```pascal
function rand16 : uint16;
```
Returns a 16-bit pseudo-random value (low 16 bits of a `rand32` call).

### rand8
```pascal
function rand8 : uint8;
```
Returns an 8-bit pseudo-random value (low 8 bits of a `rand32` call).

### srand
```pascal
procedure srand(seed : uint32);
```
Seeds the generator by adding `seed` to the current internal state. The seed is added rather than assigned, so successive calls accumulate entropy rather than resetting the sequence to a fixed point.

## Notes

The generator is not cryptographically secure and must not be used for security-sensitive purposes such as key generation or nonce selection.

The internal `rand` function returns values in the range 0–32767 (15 bits), following the classic C `rand()` output convention. `rand32` combines two calls to produce a 32-bit value.

Because `srand` adds to the existing state, the output sequence cannot be exactly reproduced by setting a known seed after the generator has been called. Seed before first use for reproducible sequences.
