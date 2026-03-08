# core.ds.bloom

Probabilistic set-membership filter using double hashing.

## Overview

`core.ds.bloom` implements a Bloom filter — a space-efficient probabilistic data structure for testing whether an element is a member of a set. Insertions and membership tests run in O(k) time where k is the number of hash functions. Double hashing is used to derive k independent bit positions from two base hash functions (FNV-1a 32-bit and DJB2 32-bit), avoiding the need to store or compute k separate functions.

False positives are possible at a rate determined by the filter size and the number of hash functions. False negatives are not possible: if `Bloom_Test` returns `false`, the element was definitely not inserted.

## Dependencies

- `core.ds.types` — `TBloomFilter`, `PBloomFilter`
- `memory.heap` — `kalloc`, `kfree`
- `core.util` — `memset`
- `core.enc.fnv1a` — `Hash_FNV1a32`
- `core.enc.djb2` — `Hash_DJB2_32`
- `io.syslog` — test output
- `core.strings` — test output formatting

## Functions and Procedures

### Bloom_New
```pascal
function Bloom_New(BitCount : uint32; HashCount : uint32) : PBloomFilter;
```
Creates a new Bloom filter with `BitCount` bits and `HashCount` hash functions per element. The bit buffer is zero-initialised. Returns `nil` on allocation failure.

A common sizing guideline: `m = -n * ln(p) / (ln(2)^2)` for `n` expected elements and target false-positive rate `p`. Optimal `k = (m/n) * ln(2)`.

### Bloom_Add
```pascal
procedure Bloom_Add(Filter : PBloomFilter; Data : void; DataLen : uint32);
```
Inserts `DataLen` bytes pointed to by `Data` into the filter by setting the k bit positions derived from double hashing. Increments `Filter^.Count`.

### Bloom_Test
```pascal
function Bloom_Test(Filter : PBloomFilter; Data : void; DataLen : uint32) : boolean;
```
Tests whether `Data` (of `DataLen` bytes) was probably inserted. Returns `true` if all k bit positions are set, `false` if any bit is clear (definite non-member).

### Bloom_Clear
```pascal
procedure Bloom_Clear(Filter : PBloomFilter);
```
Resets all bits to zero and sets `Count` to zero without freeing the filter structure or bit buffer.

### Bloom_Free
```pascal
procedure Bloom_Free(Filter : PBloomFilter);
```
Frees the bit buffer and the filter structure. After this call the pointer is invalid.

### UnitTest
```pascal
procedure UnitTest;
```
Runs the Bloom filter test suite and logs a pass/fail summary to syslog under the `'BLOOM'` channel.

## Notes

The second hash `h2` is forced to be odd (`h2 := h2 or 1`) before use. This guarantees full period coverage of the bit array when stepping by `h2`, because an odd step and a power-of-two (or arbitrary) modulus are coprime.

`Bloom_Free` does not check for `nil` on the bit buffer pointer; callers should not call it on a partially initialised filter.
