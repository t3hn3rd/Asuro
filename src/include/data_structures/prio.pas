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
	Queue Priority - Min-heap ordered priority queue
	(lowest uint32 = highest priority).

	@author(Aaron Hance <ah@aaronhance.me>)
}
unit prio;

interface

uses
  bheap,
  dstypes;

{ ============================================================================ }
{                    Priority Queue — prio_* API                             }
{ ============================================================================ }

  {**
    @abstract Creates a new priority queue (min-heap ordered).
    @param ElementSize     Size (in bytes) of each data element.
    @param InitialCapacity Starting number of slots.
    @returns Pointer to the new priority queue (a PBinaryHeap).
  **}
  function prio_New(ElementSize : uint32; InitialCapacity : uint32) : PBinaryHeap;

  {**
    @abstract Enqueues an element with a given priority.
    @param Heap     Pointer to the priority queue.
    @param Priority Priority value (lower = dequeued first).
    @param Data     Pointer to the element data to copy in.
  **}
  procedure prio_Enqueue(Heap : PBinaryHeap; Priority : uint32; Data : void);

  {**
    @abstract Dequeues the highest-priority (lowest value) element.
    @param Heap Pointer to the priority queue.
    @param Data Pointer to a buffer that receives the dequeued element.
    @returns True if an element was dequeued, false if empty.
  **}
  function prio_Dequeue(Heap : PBinaryHeap; Data : void) : boolean;

  {**
    @abstract Peeks at the highest-priority element without removing it.
    @param Heap Pointer to the priority queue.
    @returns Pointer to the element data, or nil if empty.
  **}
  function prio_Peek(Heap : PBinaryHeap) : void;

  {**
    @abstract Returns the number of elements in the priority queue.
    @param Heap Pointer to the priority queue.
    @returns Element count.
  **}
  function prio_Size(Heap : PBinaryHeap) : uint32;

  {**
    @abstract Checks whether the priority queue is empty.
    @param Heap Pointer to the priority queue.
    @returns True if empty.
  **}
  function prio_IsEmpty(Heap : PBinaryHeap) : boolean;

  {**
    @abstract Frees the priority queue and all its elements.
    @param Heap Pointer to the priority queue.
  **}
  procedure prio_Free(Heap : PBinaryHeap);

implementation

function prio_New(ElementSize : uint32; InitialCapacity : uint32) : PBinaryHeap;
begin
  prio_New := BHeap_New(ElementSize, InitialCapacity, true);
end;

procedure prio_Enqueue(Heap : PBinaryHeap; Priority : uint32; Data : void);
begin
  BHeap_Insert(Heap, Priority, Data);
end;

function prio_Dequeue(Heap : PBinaryHeap; Data : void) : boolean;
begin
  prio_Dequeue := BHeap_ExtractRoot(Heap, Data);
end;

function prio_Peek(Heap : PBinaryHeap) : void;
begin
  prio_Peek := BHeap_PeekRoot(Heap);
end;

function prio_Size(Heap : PBinaryHeap) : uint32;
begin
  prio_Size := Heap^.Count;
end;

function prio_IsEmpty(Heap : PBinaryHeap) : boolean;
begin
  prio_IsEmpty := (Heap^.Count = 0);
end;

procedure prio_Free(Heap : PBinaryHeap);
begin
  BHeap_Free(Heap);
end;

end.
