# core.ds.lists

Managed linked list, string linked list, and dynamic array list implementations.

## Overview

`core.ds.lists` provides three related list abstractions used throughout the kernel:

- **Managed Linked List (`LL_*`)** — a doubly-linked list that allocates and owns a heap buffer for each element's data. Suitable for arbitrary element sizes with infrequent insertions and deletions.
- **String Linked List (`STRLL_*`)** — a thin wrapper over the managed linked list specialised for storing heap-allocated `pchar` pointers, with convenience functions for string operations including delimiter-based splitting.
- **Dynamic List (`DL_*`)** — a contiguous array that grows by doubling and shrinks by halving. Provides O(1) indexed access and is the most cache-friendly of the three. Supports insert, delete, set, reserve, and shrink-to-fit operations.

## Dependencies

- `io.syslog` — logging and test output
- `memory.heap` — `kalloc`, `kfree`
- `debug.tracer` — call-stack tracing
- `core.util` — `memcpy`, `memset`
- `arch.x86.util` — architecture utilities
- `core.strings` — `stringNew`, `intToString` (implementation only)

## Types

### TLinkedList / PLinkedList
```pascal
TLinkedList = record
    Previous : PLinkedList;
    Data     : void;
    Next     : PLinkedList;
end;
```
A doubly-linked list node. `Data` is a pointer to a heap-allocated buffer of `ElementSize` bytes.

### TLinkedListBase / PLinkedListBase
```pascal
TLinkedListBase = record
    Count       : uint32;
    Head        : PLinkedList;
    ElementSize : uint32;
end;
```
The head record for both the managed linked list and the string linked list. `ElementSize` is set to `sizeof(uint32)` for string lists (each element stores a pointer).

### TDList / PDList
```pascal
TDList = record
    Count       : uint32;
    Data        : void;
    ElementSize : uint32;
    DataSize    : uint32;
end;
```
Dynamic array list. `Data` is a flat heap buffer. `DataSize` is total allocated bytes; `Count` is the number of live elements.

## Functions and Procedures

### LL_New
```pascal
function LL_New(ElementSize : uint32) : PLinkedListBase;
```
Creates a new empty managed linked list with the given element size.

### LL_Add
```pascal
function LL_Add(LinkedList : PLinkedListBase) : void;
```
Appends a new zero-initialised element to the list. Returns a pointer to the allocated data space.

### LL_Insert
```pascal
function LL_Insert(LinkedList : PLinkedListBase; idx : uint32) : void;
```
Inserts a new zero-initialised element before the node at `idx`. Returns a pointer to the allocated data space, or `nil` if `idx` exceeds the list count.

### LL_Get
```pascal
function LL_Get(LinkedList : PLinkedListBase; idx : uint32) : void;
```
Returns a pointer to the data of the element at zero-based `idx`, or `nil` if out of range.

### LL_Delete
```pascal
function LL_Delete(LinkedList : PLinkedListBase; idx : uint32) : boolean;
```
Removes the element at `idx`, relinks adjacent nodes, and frees the node and its data buffer. Returns `false` if `idx` is out of range.

### LL_Size
```pascal
function LL_Size(LinkedList : PLinkedListBase) : uint32;
```
Returns the number of elements in the list.

### LL_Free
```pascal
procedure LL_Free(LinkedList : PLinkedListBase);
```
Deletes all elements and frees the list base structure.

### LL_FromString
```pascal
function LL_FromString(str : pchar; delimter : char) : PLinkedListBase;
```
Splits `str` by `delimter` and returns a managed linked list where each element's `uint32` data field holds a pointer to a heap-allocated substring.

---

### STRLL_New
```pascal
function STRLL_New : PLinkedListBase;
```
Creates a new empty string linked list (element size `sizeof(uint32)`).

### STRLL_Add
```pascal
procedure STRLL_Add(LinkedList : PLinkedListBase; str : pchar);
```
Appends `str` to the list. The pointer is stored directly; ownership is transferred to the list.

### STRLL_Get
```pascal
function STRLL_Get(LinkedList : PLinkedListBase; idx : uint32) : pchar;
```
Returns the string pointer at `idx`, or `nil` if out of range.

### STRLL_Size
```pascal
function STRLL_Size(LinkedList : PLinkedListBase) : uint32;
```
Returns the number of strings in the list.

### STRLL_Delete
```pascal
procedure STRLL_Delete(LinkedList : PLinkedListBase; idx : uint32);
```
Frees the string at `idx` with `kfree`, then removes the node. Only heap-allocated strings should be stored in the list; static string literals must not be added.

### STRLL_Clear
```pascal
procedure STRLL_Clear(LinkedList : PLinkedListBase);
```
Deletes all strings from the list, freeing each string's memory.

### STRLL_Free
```pascal
procedure STRLL_Free(LinkedList : PLinkedListBase);
```
Clears all strings and frees the list base structure.

### STRLL_FromString
```pascal
function STRLL_FromString(str : pchar; delimter : char) : PLinkedListBase;
```
Splits `str` by `delimter` and returns a string linked list of heap-allocated substrings.

---

### DL_New
```pascal
function DL_New(ElementSize : uint32) : PDList;
```
Creates a new dynamic list. The initial buffer size is chosen heuristically based on `ElementSize` (smaller elements get larger initial capacities).

### DL_Add
```pascal
function DL_Add(DList : PDList) : void;
```
Appends a new zero-initialised slot to the list. Doubles the buffer if required. Returns a pointer to the new slot.

### DL_Insert
```pascal
function DL_Insert(DList : PDList; idx : uint32) : void;
```
Inserts a new zero-initialised element at `idx` by shifting subsequent elements right. Doubles the buffer if required. Returns `nil` if `idx` exceeds the current count.

### DL_Get
```pascal
function DL_Get(DList : PDList; idx : uint32) : void;
```
Returns a direct pointer to the element at `idx`, or `nil` if out of range.

### DL_Set
```pascal
function DL_Set(DList : PDList; idx : uint32; elm : puint32) : boolean;
```
Copies `ElementSize` bytes from `elm` into the slot at `idx`. Returns `false` if `idx` is out of range.

### DL_Delete
```pascal
function DL_Delete(DList : PDList; idx : uint32) : boolean;
```
Removes the element at `idx` by shifting subsequent elements left. Halves the buffer if usage falls below 50%. Returns `false` if `idx` is out of range.

### DL_Size
```pascal
function DL_Size(DList : PDList) : uint32;
```
Returns the number of live elements.

### DL_Capacity
```pascal
function DL_Capacity(DList : PDList) : uint32;
```
Returns the total number of elements the current buffer can hold without reallocation.

### DL_Reserve
```pascal
procedure DL_Reserve(DList : PDList; NewCapacity : uint32);
```
Ensures the buffer can hold at least `NewCapacity` elements, reallocating if necessary.

### DL_ShrinkToFit
```pascal
procedure DL_ShrinkToFit(DList : PDList);
```
Reallocates the buffer to exactly fit the current element count, reclaiming excess memory.

### DL_Clear
```pascal
procedure DL_Clear(DList : PDList);
```
Resets the element count to zero without freeing or zeroing the buffer, allowing fast reuse.

### DL_Concat
```pascal
function DL_Concat(DList1 : PDList; DList2 : PDList) : PDList;
```
Appends all elements of `DList2` to `DList1`. Returns `DList1`, or `nil` if the element sizes differ.

### DL_IndexOf
```pascal
function DL_IndexOf(DList : PDList; elm : puint32) : uint32;
```
Returns the index of the element whose address equals `elm`, or `uint32(-1)` if not found. Comparison is by pointer address, not by value.

### DL_Contains
```pascal
function DL_Contains(DList : PDList; elm : puint32) : boolean;
```
Returns `true` if `elm`'s address is present in the list.

### TestAllLists
```pascal
procedure TestAllLists;
```
Exercises managed linked list, string linked list, and dynamic list operations and logs results to syslog. Intended for development and bring-up use.

## Notes

`STRLL_Delete` emits a tracer push advising that static string literals must not be stored in string linked lists, because it always calls `kfree` on the retrieved pointer.

`DL_Insert` uses `memcpy` to shift elements and does not account for overlapping regions. The shift direction (right) means the source is always lower in memory than the destination; callers on platforms with strict aliasing should verify behaviour.

The dynamic list does not zero its buffer on `DL_Clear`. Old element data remains in memory until overwritten by a subsequent `DL_Add`.
