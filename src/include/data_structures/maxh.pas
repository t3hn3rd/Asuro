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
	Max-Heap - Highest priority value extracted first.

	@author(Aaron Hance <ah@aaronhance.me>)
}
unit maxh;

interface

uses
    dstypes,
    bheap;

{ ============================================================================ }
{                       Max-Heap — maxh_* API                                }
{ ============================================================================ }

  {**
    @abstract Creates a new max-heap.
    @param ElementSize     Size (in bytes) of each data element.
    @param InitialCapacity Starting number of slots (will grow as needed).
    @returns Pointer to the new heap.
  **}
  function maxh_New(ElementSize : uint32; InitialCapacity : uint32) : PBinaryHeap;

  {**
    @abstract Inserts an element into the max-heap.
    @param Heap     Pointer to the heap.
    @param Priority Priority value (higher = higher priority).
    @param Data     Pointer to the element data to copy in.
  **}
  procedure maxh_Insert(Heap : PBinaryHeap; Priority : uint32; Data : void);

  {**
    @abstract Extracts the maximum-priority element from the heap.
    @param Heap Pointer to the heap.
    @param Data Pointer to a buffer that receives the extracted element.
    @returns True if an element was extracted, false if the heap was empty.
  **}
  function maxh_ExtractMax(Heap : PBinaryHeap; Data : void) : boolean;

  {**
    @abstract Peeks at the maximum-priority element without removing it.
    @param Heap Pointer to the heap.
    @returns Pointer to the element data, or nil if empty.
  **}
  function maxh_PeekMax(Heap : PBinaryHeap) : void;

  {**
    @abstract Returns the number of elements in the max-heap.
    @param Heap Pointer to the heap.
    @returns Element count.
  **}
  function maxh_Size(Heap : PBinaryHeap) : uint32;

  {**
    @abstract Checks whether the max-heap is empty.
    @param Heap Pointer to the heap.
    @returns True if empty.
  **}
  function maxh_IsEmpty(Heap : PBinaryHeap) : boolean;

  {**
    @abstract Frees the max-heap and all its elements.
    @param Heap Pointer to the heap.
  **}
  procedure maxh_Free(Heap : PBinaryHeap);

implementation

function maxh_New(ElementSize : uint32; InitialCapacity : uint32) : PBinaryHeap;
begin
  maxh_New := BHeap_New(ElementSize, InitialCapacity, false);
end;

procedure maxh_Insert(Heap : PBinaryHeap; Priority : uint32; Data : void);
begin
  BHeap_Insert(Heap, Priority, Data);
end;

function maxh_ExtractMax(Heap : PBinaryHeap; Data : void) : boolean;
begin
  maxh_ExtractMax := BHeap_ExtractRoot(Heap, Data);
end;

function maxh_PeekMax(Heap : PBinaryHeap) : void;
begin
  maxh_PeekMax := BHeap_PeekRoot(Heap);
end;

function maxh_Size(Heap : PBinaryHeap) : uint32;
begin
  maxh_Size := Heap^.Count;
end;

function maxh_IsEmpty(Heap : PBinaryHeap) : boolean;
begin
  maxh_IsEmpty := (Heap^.Count = 0);
end;

procedure maxh_Free(Heap : PBinaryHeap);
begin
  BHeap_Free(Heap);
end;

end.
