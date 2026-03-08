# core.ds.hashmap

String-keyed hash map with chained collision resolution and automatic rehashing.

## Overview

`core.ds.hashmap` provides a general-purpose hash map that maps null-terminated string keys to opaque `void` pointers. Collisions are resolved by chaining (linked lists per bucket). When the load factor threshold is exceeded, the table doubles in size and all existing entries are re-distributed. Key strings are heap-copied on insertion so callers do not need to keep the original key alive.

The hash function used is FNV-1a 32-bit, replacing an earlier MD5-based scheme.

## Dependencies

- `memory.heap` — `kalloc`, `kfree`
- `core.enc.fnv1a` — `Hash_FNV1a32`
- `core.strings` — `stringEquals`, `stringCopy`, `stringSize`
- `io.syslog` — `printMap` debug output
- `debug.tracer` — call-stack tracing
- `core.util` — `memcpy`
- `arch.x86.util` — architecture utilities

## Constants

### HASHMAP_DEFAULT_SIZE
Default initial bucket count: `16`.

### HASHMAP_DEFAULT_LOADFACTOR
Default load factor threshold for rehashing: `0.75`.

## Types

### THashItem / PHashItem / DPHashItem
```pascal
THashItem = record
    Next : PHashItem;
    Key  : pchar;
    Hash : uint32;
    Data : void;
end;
```
A single hash map entry. `Next` links to the next entry in the same bucket (collision chain). `Key` is a heap-allocated copy of the key string. `Hash` caches the computed key hash. `Data` is the caller-supplied value pointer.

### THashMap / PHashMap
```pascal
THashMap = record
    Size       : uint32;
    LoadFactor : Single;
    Count      : uint32;
    Table      : DPHashItem;
end;
```
The map header. `Size` is the current bucket count. `Table` is the bucket array (an array of `PHashItem` pointers). `Count` tracks the total number of entries across all buckets.

### THashForEachCb
```pascal
THashForEachCb = procedure(key: pchar; data: void; ud: void);
```
Callback type for the `forEach` iterator. `key` is the entry's key string, `data` is the stored value, and `ud` is the caller-supplied user data pointer passed to `forEach`.

## Functions and Procedures

### new
```pascal
function new : PHashMap;
```
Creates a new hash map with `HASHMAP_DEFAULT_SIZE` buckets and `HASHMAP_DEFAULT_LOADFACTOR`.

### newEx
```pascal
function newEx(size : uint32; loadFactor : Single) : PHashMap;
```
Creates a new hash map with the specified initial bucket count and load factor.

### add
```pascal
procedure add(map : PHashMap; key : pchar; value : void);
```
Inserts or updates an entry for `key` with value `value`. If the key already exists, its value is replaced. The key string is heap-copied. Triggers a rehash if the load factor is exceeded after insertion.

### get
```pascal
function get(map : PHashMap; key : pchar) : void;
```
Returns the value associated with `key`, or `nil` if not found.

### delete
```pascal
procedure delete(map : PHashMap; key : pchar; freeItem : boolean);
```
Removes the entry for `key`. The key string's heap copy is always freed. If `freeItem` is `true`, the stored `Data` pointer is also freed with `kfree`.

### forEach
```pascal
procedure forEach(map : PHashMap; cb : THashForEachCb; ud : void);
```
Iterates over all entries in the map (in unspecified bucket order) and calls `cb` for each one. `ud` is passed through to the callback unchanged.

### printMap
```pascal
procedure printMap(map : PHashMap);
```
Writes a debug representation of all buckets and their collision chains to syslog. Intended for development use only.

## Notes

The `add` procedure increments `Count` on every call, including for key updates (overwrites). This means `Count` may overcount if the same key is added multiple times. Callers should use `get` to check for an existing key before calling `add` if accurate counting matters.

Rehashing allocates a new bucket array and re-inserts all existing items without copying their key or data — only the item pointers are moved. The old bucket array is freed.

There is no `free` procedure exported for the map. Callers managing map lifetime should iterate with `forEach` to free values, then call `kfree` on the table and the map structure directly, or arrange for the heap to be torn down wholesale.
