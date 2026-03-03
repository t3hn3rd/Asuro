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
	Queue Circular - Fixed-capacity ring-buffer queue.

	@author(Aaron Hance <ah@aaronhance.me>)
}
unit circ;

interface

uses
    lmemorymanager,
    dstypes,
    util;

{ ============================================================================ }
{                     Circular Queue — circ_* API                            }
{ ============================================================================ }

  {**
    @abstract Creates a new fixed-capacity circular queue.
    @param Capacity    Maximum number of elements.
    @param ElementSize Size (in bytes) of each element.
    @returns Pointer to the new circular queue.
  **}
  function circ_New(Capacity : uint32; ElementSize : uint32) : PCircularQueue;

  {**
    @abstract Enqueues an element into the circular queue.
    @param Queue Pointer to the circular queue.
    @param Data  Pointer to the element data to copy in.
    @returns True if the element was enqueued, false if the queue is full.
  **}
  function circ_Enqueue(Queue : PCircularQueue; Data : void) : boolean;

  {**
    @abstract Dequeues the front element from the circular queue.
    @param Queue Pointer to the circular queue.
    @param Data  Pointer to a buffer that receives the dequeued element.
    @returns True if an element was dequeued, false if empty.
  **}
  function circ_Dequeue(Queue : PCircularQueue; Data : void) : boolean;

  {**
    @abstract Peeks at the front element without removing it.
    @param Queue Pointer to the circular queue.
    @returns Pointer to the front element data, or nil if empty.
  **}
  function circ_Peek(Queue : PCircularQueue) : void;

  {**
    @abstract Returns the number of elements in the circular queue.
    @param Queue Pointer to the circular queue.
    @returns Element count.
  **}
  function circ_Size(Queue : PCircularQueue) : uint32;

  {**
    @abstract Checks whether the circular queue is full.
    @param Queue Pointer to the circular queue.
    @returns True if full.
  **}
  function circ_IsFull(Queue : PCircularQueue) : boolean;

  {**
    @abstract Checks whether the circular queue is empty.
    @param Queue Pointer to the circular queue.
    @returns True if empty.
  **}
  function circ_IsEmpty(Queue : PCircularQueue) : boolean;

  {**
    @abstract Frees the circular queue and its buffer.
    @param Queue Pointer to the circular queue.
  **}
  procedure circ_Free(Queue : PCircularQueue);

implementation

function circ_New(Capacity : uint32; ElementSize : uint32) : PCircularQueue;
begin
  circ_New := PCircularQueue(kalloc(sizeof(TCircularQueue)));
  circ_New^.Capacity    := Capacity;
  circ_New^.ElementSize := ElementSize;
  circ_New^.Count       := 0;
  circ_New^.Head        := 0;
  circ_New^.Tail        := 0;
  circ_New^.Data        := kalloc(Capacity * ElementSize);
  memset(uint32(circ_New^.Data), 0, Capacity * ElementSize);
end;

function circ_Enqueue(Queue : PCircularQueue; Data : void) : boolean;
var
  dst : uint32;
begin
  circ_Enqueue := false;
  if Queue^.Count >= Queue^.Capacity then exit;

  dst := uint32(Queue^.Data) + (Queue^.Tail * Queue^.ElementSize);
  memcpy(uint32(Data), dst, Queue^.ElementSize);

  Queue^.Tail  := (Queue^.Tail + 1) mod Queue^.Capacity;
  Queue^.Count := Queue^.Count + 1;
  circ_Enqueue := true;
end;

function circ_Dequeue(Queue : PCircularQueue; Data : void) : boolean;
var
  src : uint32;
begin
  circ_Dequeue := false;
  if Queue^.Count = 0 then exit;

  src := uint32(Queue^.Data) + (Queue^.Head * Queue^.ElementSize);
  memcpy(src, uint32(Data), Queue^.ElementSize);

  Queue^.Head  := (Queue^.Head + 1) mod Queue^.Capacity;
  Queue^.Count := Queue^.Count - 1;
  circ_Dequeue := true;
end;

function circ_Peek(Queue : PCircularQueue) : void;
begin
  if Queue^.Count = 0 then
    circ_Peek := nil
  else
    circ_Peek := void(uint32(Queue^.Data) + (Queue^.Head * Queue^.ElementSize));
end;

function circ_Size(Queue : PCircularQueue) : uint32;
begin
  circ_Size := Queue^.Count;
end;

function circ_IsFull(Queue : PCircularQueue) : boolean;
begin
  circ_IsFull := (Queue^.Count = Queue^.Capacity);
end;

function circ_IsEmpty(Queue : PCircularQueue) : boolean;
begin
  circ_IsEmpty := (Queue^.Count = 0);
end;

procedure circ_Free(Queue : PCircularQueue);
begin
  if Queue = nil then exit;
  kfree(Queue^.Data);
  kfree(void(Queue));
end;

end.
