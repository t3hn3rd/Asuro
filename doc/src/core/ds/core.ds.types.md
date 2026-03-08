# core.ds.types

Shared type definitions for all kernel data structures.

## Overview

`core.ds.types` is a types-only unit that declares the record and pointer types used by the data structure units in the `core.ds` namespace. Centralising these definitions allows different data structure units to share types without circular dependencies. No functions or variables are defined here.

## Dependencies

None.

## Types

### TQueueNode / PQueueNode
```pascal
TQueueNode = record
    Next : PQueueNode;
    Data : void;
end;
```
Singly-linked node used by the linked-list FIFO (`core.ds.fifo`) and LIFO (`core.ds.lifo`) implementations. `Data` points to a heap-allocated copy of the stored element.

### TFIFOQueue / PFIFOQueue
```pascal
TFIFOQueue = record
    Head        : PQueueNode;
    Tail        : PQueueNode;
    Count       : uint32;
    ElementSize : uint32;
end;
```
First-In First-Out queue backed by a singly-linked list. `Head` is the dequeue end; `Tail` is the enqueue end.

### TCFIFOQueue / PCFIFOQueue
```pascal
TCFIFOQueue = record
    Data        : void;
    Head        : uint32;
    Count       : uint32;
    Capacity    : uint32;
    ElementSize : uint32;
end;
```
Array-backed contiguous FIFO queue with lazy compaction and automatic growth. Elements are stored contiguously starting at `Data + (Head * ElementSize)`. When `Head` advances past half the capacity, elements are shifted back to index 0. The buffer doubles when full.

### TCFIFOList / PCFIFOList
```pascal
TCFIFOList = record
    Items    : void;
    Count    : uint32;
    Capacity : uint32;
end;
```
Dynamic array of `PCFIFOQueue` pointers. Used to group related contiguous FIFO queues. `Items` is a flat buffer of pointer slots that grows automatically.

### TLIFOStack / PLIFOStack
```pascal
TLIFOStack = record
    Top         : PQueueNode;
    Count       : uint32;
    ElementSize : uint32;
end;
```
Last-In First-Out stack backed by a singly-linked list. `Top` points to the most recently pushed node.

### TCircularQueue / PCircularQueue
```pascal
TCircularQueue = record
    Data        : void;
    Head        : uint32;
    Tail        : uint32;
    Count       : uint32;
    Capacity    : uint32;
    ElementSize : uint32;
end;
```
Fixed-capacity ring-buffer queue. `Head` is the index of the front element; `Tail` is the index of the next free slot. Wrap-around is handled with modulo arithmetic.

### TBinaryHeap / PBinaryHeap
```pascal
TBinaryHeap = record
    Data        : void;
    Indices     : void;
    FreeSlots   : void;
    Count       : uint32;
    Capacity    : uint32;
    NextSlot    : uint32;
    FreeCount   : uint32;
    ElementSize : uint32;
    NodeStride  : uint32;
    IsMinHeap   : boolean;
end;
```
Array-backed binary heap with index-array indirection. Element data is stored inline in `Data` as `[Priority (uint32)][Element (ElementSize bytes)]` per slot. `Indices` maps heap positions to data slot indices, allowing O(1) swaps by exchanging indices rather than copying data. Freed data slots are recycled through `FreeSlots`/`FreeCount`. `IsMinHeap` controls whether the root holds the minimum (`true`) or maximum (`false`) priority.

### TBloomFilter / PBloomFilter
```pascal
TBloomFilter = record
    Bits      : void;
    BitCount  : uint32;
    HashCount : uint32;
    Count     : uint32;
end;
```
Probabilistic set-membership filter. `Bits` is a flat byte buffer of `ceil(BitCount / 8)` bytes. Membership tests use `k = HashCount` independent bit positions derived from two base hashes (FNV-1a + DJB2) via double hashing: `h_i(x) = (h1(x) + i * h2(x)) mod BitCount`. False positives are possible; false negatives are not.
