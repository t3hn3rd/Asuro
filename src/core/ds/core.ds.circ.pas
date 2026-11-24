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
unit core.ds.circ;

interface

uses
    memory.heap,
    core.ds.types,
    core.util;

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

  {** Runs unit tests for the circular queue. **}
  procedure UnitTest;

implementation

uses
    test.harness,
    io.syslog, core.strings;

function circ_New(Capacity : uint32; ElementSize : uint32) : PCircularQueue;
begin
  circ_New := nil;
  if (Capacity = 0) or (ElementSize = 0) or (Capacity > High(SizeUInt) div ElementSize) then exit;
  circ_New := PCircularQueue(kalloc(sizeof(TCircularQueue)));
  if circ_New = nil then exit;
  circ_New^.Capacity    := Capacity;
  circ_New^.ElementSize := ElementSize;
  circ_New^.Count       := 0;
  circ_New^.Head        := 0;
  circ_New^.Tail        := 0;
  circ_New^.Data        := kalloc(SizeUInt(Capacity) * ElementSize);
  if circ_New^.Data = nil then begin
    kfree(void(circ_New));
    circ_New := nil;
    exit;
  end;
  memset(PtrUInt(circ_New^.Data), 0, SizeUInt(Capacity) * ElementSize);
end;

function circ_Enqueue(Queue : PCircularQueue; Data : void) : boolean;
var
  dst : PtrUInt;
begin
  circ_Enqueue := false;
  if Queue^.Count >= Queue^.Capacity then exit;

  dst := PtrUInt(Queue^.Data) + (SizeUInt(Queue^.Tail) * Queue^.ElementSize);
  memcpy(PtrUInt(Data), dst, Queue^.ElementSize);

  Queue^.Tail  := (Queue^.Tail + 1) mod Queue^.Capacity;
  Queue^.Count := Queue^.Count + 1;
  circ_Enqueue := true;
end;

function circ_Dequeue(Queue : PCircularQueue; Data : void) : boolean;
var
  src : PtrUInt;
begin
  circ_Dequeue := false;
  if Queue^.Count = 0 then exit;

  src := PtrUInt(Queue^.Data) + (SizeUInt(Queue^.Head) * Queue^.ElementSize);
  memcpy(src, PtrUInt(Data), Queue^.ElementSize);

  Queue^.Head  := (Queue^.Head + 1) mod Queue^.Capacity;
  Queue^.Count := Queue^.Count - 1;
  circ_Dequeue := true;
end;

function circ_Peek(Queue : PCircularQueue) : void;
begin
  if Queue^.Count = 0 then
    circ_Peek := nil
  else
    circ_Peek := void(PtrUInt(Queue^.Data) + (SizeUInt(Queue^.Head) * Queue^.ElementSize));
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

procedure UnitTest;
var
    q    : PCircularQueue;
    v, r : uint32;
    ok   : boolean;
    p    : void;
    context : TTestContext;

begin
    test.harness.Start(@context, 'core.ds.circ');

    { === New / Empty / Full / Size === }
    q := circ_New(4, sizeof(uint32));
    test.harness.Assert(@context, q <> nil, 'New returns non-nil');
    test.harness.Assert(@context, circ_IsEmpty(q), 'Initially empty');
    test.harness.Assert(@context, not circ_IsFull(q), 'Initially not full');
    test.harness.Assert(@context, circ_Size(q) = 0, 'Initial size is 0');

    { === Fill to capacity === }
    v := 100; ok := circ_Enqueue(q, @v); test.harness.Assert(@context, ok, 'Enqueue 1 ok');
    v := 200; ok := circ_Enqueue(q, @v); test.harness.Assert(@context, ok, 'Enqueue 2 ok');
    v := 300; ok := circ_Enqueue(q, @v); test.harness.Assert(@context, ok, 'Enqueue 3 ok');
    v := 400; ok := circ_Enqueue(q, @v); test.harness.Assert(@context, ok, 'Enqueue 4 ok');
    test.harness.Assert(@context, circ_IsFull(q), 'Full after 4 enqueues');
    test.harness.Assert(@context, circ_Size(q) = 4, 'Size is 4 when full');

    { === Enqueue when full === }
    v := 999;
    ok := circ_Enqueue(q, @v);
    test.harness.Assert(@context, not ok, 'Enqueue on full returns false');

    { === Peek === }
    p := circ_Peek(q);
    test.harness.Assert(@context, p <> nil, 'Peek non-nil');
    test.harness.Assert(@context, uint32(p^) = 100, 'Peek returns first enqueued');

    { === Dequeue all — FIFO order === }
    ok := circ_Dequeue(q, @r); test.harness.Assert(@context, r = 100, 'Dequeue 1 value');
    ok := circ_Dequeue(q, @r); test.harness.Assert(@context, r = 200, 'Dequeue 2 value');
    ok := circ_Dequeue(q, @r); test.harness.Assert(@context, r = 300, 'Dequeue 3 value');
    ok := circ_Dequeue(q, @r); test.harness.Assert(@context, r = 400, 'Dequeue 4 value');
    test.harness.Assert(@context, circ_IsEmpty(q), 'Empty after all dequeued');

    { === Edge: dequeue/peek on empty === }
    ok := circ_Dequeue(q, @r);
    test.harness.Assert(@context, not ok, 'Dequeue on empty returns false');
    p := circ_Peek(q);
    test.harness.Assert(@context, p = nil, 'Peek on empty returns nil');

    { === Wrap-around === }
    v := 1; circ_Enqueue(q, @v);
    v := 2; circ_Enqueue(q, @v);
    circ_Dequeue(q, @r);
    v := 3; circ_Enqueue(q, @v);
    v := 4; circ_Enqueue(q, @v);
    circ_Dequeue(q, @r); test.harness.Assert(@context, r = 2, 'Wraparound order 2');
    circ_Dequeue(q, @r); test.harness.Assert(@context, r = 3, 'Wraparound order 3');
    circ_Dequeue(q, @r); test.harness.Assert(@context, r = 4, 'Wraparound order 4');
    test.harness.Assert(@context, circ_IsEmpty(q), 'Empty after wraparound');

    circ_Free(q);

    test.harness.Finish(@context);
end;

end.
