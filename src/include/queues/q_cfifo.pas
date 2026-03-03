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
	Queue Contiguous FIFO - Array-backed FIFO with lazy compaction.

	@author(Aaron Hance <ah@aaronhance.me>)
}
unit q_cfifo;

interface

uses
    lmemorymanager,
    q_types,
    util;

{ ============================================================================ }
{                  Contiguous FIFO Queue — Q_CFIFO_* API                       }
{ ============================================================================ }

  {**
    @abstract Creates a new contiguous FIFO queue.
    @param ElementSize     Size (in bytes) of each element.
    @param InitialCapacity Starting number of slots (will grow as needed).
    @returns Pointer to the new contiguous FIFO queue.
  **}
  function Q_CFIFO_New(ElementSize : uint32; InitialCapacity : uint32) : PCFIFOQueue;

  {**
    @abstract Enqueues an element at the back of the contiguous FIFO queue.
    @param Queue Pointer to the contiguous FIFO queue.
    @param Data  Pointer to the element data to copy in.
  **}
  procedure Q_CFIFO_Enqueue(Queue : PCFIFOQueue; Data : void);

  {**
    @abstract Dequeues the front element from the contiguous FIFO queue.
    @param Queue Pointer to the contiguous FIFO queue.
    @param Data  Pointer to a buffer that receives the dequeued element.
    @returns True if an element was dequeued, false if the queue was empty.
  **}
  function Q_CFIFO_Dequeue(Queue : PCFIFOQueue; Data : void) : boolean;

  {**
    @abstract Peeks at the front element without removing it.
    @param Queue Pointer to the contiguous FIFO queue.
    @returns Pointer to the front element data, or nil if empty.
  **}
  function Q_CFIFO_Peek(Queue : PCFIFOQueue) : void;

  {**
    @abstract Returns the number of elements in the contiguous FIFO queue.
    @param Queue Pointer to the contiguous FIFO queue.
    @returns Element count.
  **}
  function Q_CFIFO_Size(Queue : PCFIFOQueue) : uint32;

  {**
    @abstract Checks whether the contiguous FIFO queue is empty.
    @param Queue Pointer to the contiguous FIFO queue.
    @returns True if empty.
  **}
  function Q_CFIFO_IsEmpty(Queue : PCFIFOQueue) : boolean;

  {**
    @abstract Returns the current capacity of the contiguous FIFO queue.
    @param Queue Pointer to the contiguous FIFO queue.
    @returns Capacity in number of elements.
  **}
  function Q_CFIFO_Capacity(Queue : PCFIFOQueue) : uint32;

  {**
    @abstract Frees the contiguous FIFO queue and its buffer.
    @param Queue Pointer to the contiguous FIFO queue.
  **}
  procedure Q_CFIFO_Free(Queue : PCFIFOQueue);

implementation

{ ---------------------------------------------------------------------------- }
{  Internal helpers                                                            }
{ ---------------------------------------------------------------------------- }

{** Shifts elements back to index 0, called when Head >= Capacity div 2. **}
procedure CFIFO_Compact(Queue : PCFIFOQueue);
var
  src : uint32;
  len : uint32;
begin
  if (Queue^.Head = 0) or (Queue^.Count = 0) then exit;
  src := uint32(Queue^.Data) + (Queue^.Head * Queue^.ElementSize);
  len := Queue^.Count * Queue^.ElementSize;
  { memcpy is safe here because dst < src (Head > 0), so no overlap issue }
  memcpy(src, uint32(Queue^.Data), len);
  Queue^.Head := 0;
end;

{** Doubles the buffer capacity, compacting first. **}
procedure CFIFO_Grow(Queue : PCFIFOQueue);
var
  newCap  : uint32;
  newBuf  : void;
begin
  { Compact so elements start at index 0 before copying }
  CFIFO_Compact(Queue);

  newCap := Queue^.Capacity * 2;
  if newCap = 0 then newCap := 8;

  newBuf := kalloc(newCap * Queue^.ElementSize);
  memset(uint32(newBuf), 0, newCap * Queue^.ElementSize);

  if Queue^.Count > 0 then
    memcpy(uint32(Queue^.Data), uint32(newBuf), Queue^.Count * Queue^.ElementSize);

  kfree(Queue^.Data);
  Queue^.Data     := newBuf;
  Queue^.Capacity := newCap;
end;

{ ---------------------------------------------------------------------------- }
{  Public API                                                                  }
{ ---------------------------------------------------------------------------- }

function Q_CFIFO_New(ElementSize : uint32; InitialCapacity : uint32) : PCFIFOQueue;
begin
  Q_CFIFO_New := PCFIFOQueue(kalloc(sizeof(TCFIFOQueue)));
  Q_CFIFO_New^.ElementSize := ElementSize;
  Q_CFIFO_New^.Capacity    := InitialCapacity;
  Q_CFIFO_New^.Count       := 0;
  Q_CFIFO_New^.Head        := 0;
  Q_CFIFO_New^.Data        := kalloc(InitialCapacity * ElementSize);
  memset(uint32(Q_CFIFO_New^.Data), 0, InitialCapacity * ElementSize);
end;

procedure Q_CFIFO_Enqueue(Queue : PCFIFOQueue; Data : void);
var
  tail : uint32;
  dst  : uint32;
begin
  { Grow if all slots are consumed }
  if Queue^.Count >= Queue^.Capacity then
    CFIFO_Grow(Queue);

  { Compact if there's no room at the back even though Count < Capacity,
    which happens when Head has advanced past zero }
  tail := Queue^.Head + Queue^.Count;
  if tail >= Queue^.Capacity then
  begin
    CFIFO_Compact(Queue);
    tail := Queue^.Count;  { Head is now 0 }
  end;

  dst := uint32(Queue^.Data) + (tail * Queue^.ElementSize);
  memcpy(uint32(Data), dst, Queue^.ElementSize);
  Queue^.Count := Queue^.Count + 1;
end;

function Q_CFIFO_Dequeue(Queue : PCFIFOQueue; Data : void) : boolean;
var
  src : uint32;
begin
  Q_CFIFO_Dequeue := false;
  if Queue^.Count = 0 then exit;

  src := uint32(Queue^.Data) + (Queue^.Head * Queue^.ElementSize);
  memcpy(src, uint32(Data), Queue^.ElementSize);

  Queue^.Head  := Queue^.Head + 1;
  Queue^.Count := Queue^.Count - 1;

  { Lazy compact: shift back to 0 when Head passes half the capacity }
  if (Queue^.Count > 0) and (Queue^.Head >= Queue^.Capacity div 2) then
    CFIFO_Compact(Queue);

  { Reset Head when queue becomes empty }
  if Queue^.Count = 0 then
    Queue^.Head := 0;

  Q_CFIFO_Dequeue := true;
end;

function Q_CFIFO_Peek(Queue : PCFIFOQueue) : void;
begin
  if Queue^.Count = 0 then
    Q_CFIFO_Peek := nil
  else
    Q_CFIFO_Peek := void(uint32(Queue^.Data) + (Queue^.Head * Queue^.ElementSize));
end;

function Q_CFIFO_Size(Queue : PCFIFOQueue) : uint32;
begin
  Q_CFIFO_Size := Queue^.Count;
end;

function Q_CFIFO_IsEmpty(Queue : PCFIFOQueue) : boolean;
begin
  Q_CFIFO_IsEmpty := (Queue^.Count = 0);
end;

function Q_CFIFO_Capacity(Queue : PCFIFOQueue) : uint32;
begin
  Q_CFIFO_Capacity := Queue^.Capacity;
end;

procedure Q_CFIFO_Free(Queue : PCFIFOQueue);
begin
  if Queue = nil then exit;
  kfree(Queue^.Data);
  kfree(void(Queue));
end;

end.
