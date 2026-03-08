//  Copyright 2024 Aaron Hance
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

{
	Data Structure Types - Shared type definitions for all data structures.

	@author(Aaron Hance <ah@aaronhance.me>)
}
unit core.ds.types;

interface

type
  { ------ Shared node for FIFO & LIFO ------ }

  {**
    @abstract Pointer to a queue node.
  **}
  PQueueNode = ^TQueueNode;

  {**
    @abstract Singly-linked node used by FIFO and LIFO queues.
    @field Next Pointer to the next node in the chain.
    @field Data Pointer to the stored element data (kalloc'd copy).
  **}
  TQueueNode = record
    Next : PQueueNode;
    Data : void;
  end;

  { ------ FIFO Queue ------ }

  {**
    @abstract Pointer to a FIFO queue.
  **}
  PFIFOQueue = ^TFIFOQueue;

  {**
    @abstract First-In First-Out queue.
    @field Head        Pointer to the front node (dequeue end).
    @field Tail        Pointer to the back node (enqueue end).
    @field Count       Number of elements in the queue.
    @field ElementSize Size (in bytes) of each element.
  **}
  TFIFOQueue = record
    Head        : PQueueNode;
    Tail        : PQueueNode;
    Count       : uint32;
    ElementSize : uint32;
  end;

  { ------ Contiguous FIFO Queue ------ }

  {**
    @abstract Pointer to a contiguous FIFO queue.
  **}
  PCFIFOQueue = ^TCFIFOQueue;

  {**
    @abstract Array-backed contiguous FIFO queue with lazy compaction and
             automatic growth.
    @discussion Elements are always stored contiguously starting at
                Data + (Head * ElementSize). When Head passes half the
                Capacity, elements are shifted back to index 0 (compact).
                The buffer doubles when full.
    @field Data        Pointer to the flat element buffer.
    @field Head        Index of the front element.
    @field Count       Number of elements currently stored.
    @field Capacity    Allocated number of element slots.
    @field ElementSize Size (in bytes) of each element.
  **}
  TCFIFOQueue = record
    Data        : void;
    Head        : uint32;
    Count       : uint32;
    Capacity    : uint32;
    ElementSize : uint32;
  end;

  { ------ Contiguous FIFO List ------ }

  {**
    @abstract Pointer to a contiguous FIFO list.
  **}
  PCFIFOList = ^TCFIFOList;

  {**
    @abstract Dynamic array of contiguous FIFO queue pointers.
    @discussion Manages a growable list of PCFIFOQueue references.
               Used to group related contiguous FIFO queues.
    @field Items    Pointer to a flat buffer of PCFIFOQueue pointers.
    @field Count    Number of queues currently stored.
    @field Capacity Allocated number of pointer slots.
  **}
  TCFIFOList = record
    Items    : void;
    Count    : uint32;
    Capacity : uint32;
  end;

  { ------ LIFO Stack ------ }

  {**
    @abstract Pointer to a LIFO stack.
  **}
  PLIFOStack = ^TLIFOStack;

  {**
    @abstract Last-In First-Out stack.
    @field Top         Pointer to the top node.
    @field Count       Number of elements on the stack.
    @field ElementSize Size (in bytes) of each element.
  **}
  TLIFOStack = record
    Top         : PQueueNode;
    Count       : uint32;
    ElementSize : uint32;
  end;

  { ------ Circular Queue ------ }

  {**
    @abstract Pointer to a circular queue.
  **}
  PCircularQueue = ^TCircularQueue;

  {**
    @abstract Fixed-capacity ring-buffer queue.
    @field Data        Pointer to the flat element buffer.
    @field Head        Index of the front element.
    @field Tail        Index of the next free slot.
    @field Count       Number of elements currently stored.
    @field Capacity    Maximum number of elements.
    @field ElementSize Size (in bytes) of each element.
  **}
  TCircularQueue = record
    Data        : void;
    Head        : uint32;
    Tail        : uint32;
    Count       : uint32;
    Capacity    : uint32;
    ElementSize : uint32;
  end;

  { ------ Binary Heap (shared backing for Min/Max/Priority) ------ }

  {**
    @abstract Pointer to a binary heap.
  **}
  PBinaryHeap = ^TBinaryHeap;

  {**
    @abstract Array-backed binary heap with index-array indirection.
    @discussion Element data is stored inline in a flat buffer. Each data
                slot occupies NodeStride bytes: a uint32 priority followed
                by ElementSize bytes of element data.
                A separate Indices array maps heap positions to data slot
                indices. Sift-up / sift-down only swap uint32 indices
                rather than copying entire nodes, which is faster when
                ElementSize is non-trivial.
                Freed data slots are recycled through a simple free-stack
                (FreeSlots / FreeCount).
    @field Data        Flat data buffer ([Priority][Element] per slot).
    @field Indices     uint32 array — Indices[heap_pos] = data slot index.
    @field FreeSlots   uint32 stack of recyclable data slot indices.
    @field Count       Number of live elements in the heap.
    @field Capacity    Allocated number of slots in Data / Indices / FreeSlots.
    @field NextSlot    Next never-used data slot index.
    @field FreeCount   Number of entries on the FreeSlots stack.
    @field ElementSize Size (in bytes) of each data element.
    @field NodeStride  Bytes per data slot (sizeof(uint32) + ElementSize).
    @field IsMinHeap   True = min-heap ordering; False = max-heap ordering.
  **}
  TBinaryHeap = record
    Data        : void;    { flat buffer: [pri0][elem0][pri1][elem1]... }
    Indices     : void;    { heap-position -> data-slot mapping }
    FreeSlots   : void;    { stack of freed data slot indices }
    Count       : uint32;
    Capacity    : uint32;
    NextSlot    : uint32;
    FreeCount   : uint32;
    ElementSize : uint32;
    NodeStride  : uint32;
    IsMinHeap   : boolean;
  end;

implementation

end.