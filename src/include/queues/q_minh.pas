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
	Queue Min-Heap - Lowest priority value extracted first.

	@author(Aaron Hance <ah@aaronhance.me>)
}
unit q_minh;

interface

uses
    q_types,
    q_heap;

{ ============================================================================ }
{                       Min-Heap — Q_MINH_* API                                }
{ ============================================================================ }

  {**
    @abstract Creates a new min-heap.
    @param ElementSize     Size (in bytes) of each data element.
    @param InitialCapacity Starting number of slots (will grow as needed).
    @returns Pointer to the new heap.
  **}
  function Q_MINH_New(ElementSize : uint32; InitialCapacity : uint32) : PBinaryHeap;

  {**
    @abstract Inserts an element into the min-heap.
    @param Heap     Pointer to the heap.
    @param Priority Priority value (lower = higher priority).
    @param Data     Pointer to the element data to copy in.
  **}
  procedure Q_MINH_Insert(Heap : PBinaryHeap; Priority : uint32; Data : void);

  {**
    @abstract Extracts the minimum-priority element from the heap.
    @param Heap Pointer to the heap.
    @param Data Pointer to a buffer that receives the extracted element.
    @returns True if an element was extracted, false if the heap was empty.
  **}
  function Q_MINH_ExtractMin(Heap : PBinaryHeap; Data : void) : boolean;

  {**
    @abstract Peeks at the minimum-priority element without removing it.
    @param Heap Pointer to the heap.
    @returns Pointer to the element data, or nil if empty.
  **}
  function Q_MINH_PeekMin(Heap : PBinaryHeap) : void;

  {**
    @abstract Returns the number of elements in the min-heap.
    @param Heap Pointer to the heap.
    @returns Element count.
  **}
  function Q_MINH_Size(Heap : PBinaryHeap) : uint32;

  {**
    @abstract Checks whether the min-heap is empty.
    @param Heap Pointer to the heap.
    @returns True if empty.
  **}
  function Q_MINH_IsEmpty(Heap : PBinaryHeap) : boolean;

  {**
    @abstract Frees the min-heap and all its elements.
    @param Heap Pointer to the heap.
  **}
  procedure Q_MINH_Free(Heap : PBinaryHeap);

implementation

function Q_MINH_New(ElementSize : uint32; InitialCapacity : uint32) : PBinaryHeap;
begin
  Q_MINH_New := BH_New(ElementSize, InitialCapacity, true);
end;

procedure Q_MINH_Insert(Heap : PBinaryHeap; Priority : uint32; Data : void);
begin
  BH_Insert(Heap, Priority, Data);
end;

function Q_MINH_ExtractMin(Heap : PBinaryHeap; Data : void) : boolean;
begin
  Q_MINH_ExtractMin := BH_ExtractRoot(Heap, Data);
end;

function Q_MINH_PeekMin(Heap : PBinaryHeap) : void;
begin
  Q_MINH_PeekMin := BH_PeekRoot(Heap);
end;

function Q_MINH_Size(Heap : PBinaryHeap) : uint32;
begin
  Q_MINH_Size := Heap^.Count;
end;

function Q_MINH_IsEmpty(Heap : PBinaryHeap) : boolean;
begin
  Q_MINH_IsEmpty := (Heap^.Count = 0);
end;

procedure Q_MINH_Free(Heap : PBinaryHeap);
begin
  BH_Free(Heap);
end;

end.
