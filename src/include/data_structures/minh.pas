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
	Min-Heap - Lowest priority value extracted first.

	@author(Aaron Hance <ah@aaronhance.me>)
}
unit minh;

interface

uses
    dstypes,
    bheap;

{ ============================================================================ }
{                       Min-Heap — minh_* API                                }
{ ============================================================================ }

  {**
    @abstract Creates a new min-heap.
    @param ElementSize     Size (in bytes) of each data element.
    @param InitialCapacity Starting number of slots (will grow as needed).
    @returns Pointer to the new heap.
  **}
  function minh_New(ElementSize : uint32; InitialCapacity : uint32) : PBinaryHeap;

  {**
    @abstract Inserts an element into the min-heap.
    @param Heap     Pointer to the heap.
    @param Priority Priority value (lower = higher priority).
    @param Data     Pointer to the element data to copy in.
  **}
  procedure minh_Insert(Heap : PBinaryHeap; Priority : uint32; Data : void);

  {**
    @abstract Extracts the minimum-priority element from the heap.
    @param Heap Pointer to the heap.
    @param Data Pointer to a buffer that receives the extracted element.
    @returns True if an element was extracted, false if the heap was empty.
  **}
  function minh_ExtractMin(Heap : PBinaryHeap; Data : void) : boolean;

  {**
    @abstract Peeks at the minimum-priority element without removing it.
    @param Heap Pointer to the heap.
    @returns Pointer to the element data, or nil if empty.
  **}
  function minh_PeekMin(Heap : PBinaryHeap) : void;

  {**
    @abstract Returns the number of elements in the min-heap.
    @param Heap Pointer to the heap.
    @returns Element count.
  **}
  function minh_Size(Heap : PBinaryHeap) : uint32;

  {**
    @abstract Checks whether the min-heap is empty.
    @param Heap Pointer to the heap.
    @returns True if empty.
  **}
  function minh_IsEmpty(Heap : PBinaryHeap) : boolean;

  {**
    @abstract Frees the min-heap and all its elements.
    @param Heap Pointer to the heap.
  **}
  procedure minh_Free(Heap : PBinaryHeap);

implementation

function minh_New(ElementSize : uint32; InitialCapacity : uint32) : PBinaryHeap;
begin
  minh_New := BHeap_New(ElementSize, InitialCapacity, true);
end;

procedure minh_Insert(Heap : PBinaryHeap; Priority : uint32; Data : void);
begin
  BHeap_Insert(Heap, Priority, Data);
end;

function minh_ExtractMin(Heap : PBinaryHeap; Data : void) : boolean;
begin
  minh_ExtractMin := BHeap_ExtractRoot(Heap, Data);
end;

function minh_PeekMin(Heap : PBinaryHeap) : void;
begin
  minh_PeekMin := BHeap_PeekRoot(Heap);
end;

function minh_Size(Heap : PBinaryHeap) : uint32;
begin
  minh_Size := Heap^.Count;
end;

function minh_IsEmpty(Heap : PBinaryHeap) : boolean;
begin
  minh_IsEmpty := (Heap^.Count = 0);
end;

procedure minh_Free(Heap : PBinaryHeap);
begin
  BHeap_Free(Heap);
end;

end.
