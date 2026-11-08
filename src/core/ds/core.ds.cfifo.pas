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
unit core.ds.cfifo;

interface

uses
  core.ds.types,
  memory.heap,
  core.util;

{ ============================================================================ }
{                  Contiguous FIFO Queue — CFIFO_* API                       }
{ ============================================================================ }

  {**
    @abstract Creates a new contiguous FIFO queue.
    @param ElementSize     Size (in bytes) of each element.
    @param InitialCapacity Starting number of slots (will grow as needed).
    @returns Pointer to the new contiguous FIFO queue.
  **}
  function CFIFO_New(ElementSize : uint32; InitialCapacity : uint32) : PCFIFOQueue;

  {**
    @abstract Enqueues an element at the back of the contiguous FIFO queue.
    @param Queue Pointer to the contiguous FIFO queue.
    @param Data  Pointer to the element data to copy in.
  **}
  procedure CFIFO_Enqueue(Queue : PCFIFOQueue; Data : void);

  {**
    @abstract Dequeues the front element from the contiguous FIFO queue.
    @param Queue Pointer to the contiguous FIFO queue.
    @param Data  Pointer to a buffer that receives the dequeued element.
    @returns True if an element was dequeued, false if the queue was empty.
  **}
  function CFIFO_Dequeue(Queue : PCFIFOQueue; Data : void) : boolean;

  {**
    @abstract Peeks at the front element without removing it.
    @param Queue Pointer to the contiguous FIFO queue.
    @returns Pointer to the front element data, or nil if empty.
  **}
  function CFIFO_Peek(Queue : PCFIFOQueue) : void;

  {**
    @abstract Returns the number of elements in the contiguous FIFO queue.
    @param Queue Pointer to the contiguous FIFO queue.
    @returns Element count.
  **}
  function CFIFO_Size(Queue : PCFIFOQueue) : uint32;

  {**
    @abstract Checks whether the contiguous FIFO queue is empty.
    @param Queue Pointer to the contiguous FIFO queue.
    @returns True if empty.
  **}
  function CFIFO_IsEmpty(Queue : PCFIFOQueue) : boolean;

  {**
    @abstract Returns the current capacity of the contiguous FIFO queue.
    @param Queue Pointer to the contiguous FIFO queue.
    @returns Capacity in number of elements.
  **}
  function CFIFO_Capacity(Queue : PCFIFOQueue) : uint32;

  {**
    @abstract Frees the contiguous FIFO queue and its buffer.
    @param Queue Pointer to the contiguous FIFO queue.
  **}
  procedure CFIFO_Free(Queue : PCFIFOQueue);

  {** Runs unit tests for the contiguous FIFO queue. **}
  procedure UnitTest;

implementation

uses
    arch.platform.diagnostics, core.strings;

{ ---------------------------------------------------------------------------- }
{  Internal helpers                                                            }
{ ---------------------------------------------------------------------------- }

{** Shifts elements back to index 0, called when Head >= Capacity div 2. **}
procedure CFIFO_Compact(Queue : PCFIFOQueue);
var
  src : PtrUInt;
  len : SizeUInt;
begin
  if (Queue^.Head = 0) or (Queue^.Count = 0) then exit;
  src := PtrUInt(Queue^.Data) + (SizeUInt(Queue^.Head) * Queue^.ElementSize);
  len := SizeUInt(Queue^.Count) * Queue^.ElementSize;
  { memcpy is safe here because dst < src (Head > 0), so no overlap issue }
  memcpy(src, PtrUInt(Queue^.Data), len);
  Queue^.Head := 0;
end;

{** Doubles the buffer capacity, compacting first. **}
function CFIFO_Grow(Queue : PCFIFOQueue): boolean;
var
  newCap  : uint32;
  newBuf  : void;
begin
  CFIFO_Grow := false;
  if Queue^.Capacity > High(uint32) div 2 then exit;

  { Compact so elements start at index 0 before copying }
  CFIFO_Compact(Queue);

  newCap := Queue^.Capacity * 2;
  if newCap = 0 then newCap := 8;

  if SizeUInt(newCap) > High(SizeUInt) div Queue^.ElementSize then exit;
  newBuf := kalloc(SizeUInt(newCap) * Queue^.ElementSize);
  if newBuf = nil then exit;

  if Queue^.Count > 0 then
    memcpy(PtrUInt(Queue^.Data), PtrUInt(newBuf), SizeUInt(Queue^.Count) * Queue^.ElementSize);

  kfree(Queue^.Data);
  Queue^.Data     := newBuf;
  Queue^.Capacity := newCap;
  CFIFO_Grow := true;
end;

{ ---------------------------------------------------------------------------- }
{  Public API                                                                  }
{ ---------------------------------------------------------------------------- }

function CFIFO_New(ElementSize : uint32; InitialCapacity : uint32) : PCFIFOQueue;
var
    queue: PCFIFOQueue;
begin
    CFIFO_New := nil;
    if ElementSize = 0 then exit;
    if InitialCapacity = 0 then InitialCapacity := 8;
    if SizeUInt(InitialCapacity) > High(SizeUInt) div ElementSize then exit;

    queue := PCFIFOQueue(kalloc(sizeof(TCFIFOQueue)));
    if queue = nil then exit;
    queue^.Data := kalloc(SizeUInt(InitialCapacity) * ElementSize);
    if queue^.Data = nil then begin
        kfree(void(queue));
        exit;
    end;
    queue^.ElementSize := ElementSize;
    queue^.Capacity := InitialCapacity;
    CFIFO_New := queue;
end;

procedure CFIFO_Enqueue(Queue : PCFIFOQueue; Data : void);
var
  tail : uint32;
  dst  : PtrUInt;
begin
  if (Queue = nil) or (Data = nil) then exit;

  { Grow if all slots are consumed }
  if Queue^.Count >= Queue^.Capacity then
    if not CFIFO_Grow(Queue) then exit;

  { Compact if there's no room at the back even though Count < Capacity,
    which happens when Head has advanced past zero }
  tail := Queue^.Head + Queue^.Count;
  if tail >= Queue^.Capacity then
  begin
    CFIFO_Compact(Queue);
    tail := Queue^.Count;  { Head is now 0 }
  end;

  dst := PtrUInt(Queue^.Data) + (SizeUInt(tail) * Queue^.ElementSize);
  memcpy(PtrUInt(Data), dst, Queue^.ElementSize);
  Queue^.Count := Queue^.Count + 1;
end;

function CFIFO_Dequeue(Queue : PCFIFOQueue; Data : void) : boolean;
var
  src : PtrUInt;
begin
  CFIFO_Dequeue := false;
  if Queue^.Count = 0 then exit;

  src := PtrUInt(Queue^.Data) + (SizeUInt(Queue^.Head) * Queue^.ElementSize);
  memcpy(src, PtrUInt(Data), Queue^.ElementSize);

  Queue^.Head  := Queue^.Head + 1;
  Queue^.Count := Queue^.Count - 1;

  { Lazy compact: shift back to 0 when Head passes half the capacity }
  if (Queue^.Count > 0) and (Queue^.Head >= Queue^.Capacity div 2) then
    CFIFO_Compact(Queue);

  { Reset Head when queue becomes empty }
  if Queue^.Count = 0 then
    Queue^.Head := 0;

  CFIFO_Dequeue := true;
end;

function CFIFO_Peek(Queue : PCFIFOQueue) : void;
begin
  if Queue^.Count = 0 then
    CFIFO_Peek := nil
  else
    CFIFO_Peek := void(PtrUInt(Queue^.Data) + (SizeUInt(Queue^.Head) * Queue^.ElementSize));
end;

function CFIFO_Size(Queue : PCFIFOQueue) : uint32;
begin
  CFIFO_Size := Queue^.Count;
end;

function CFIFO_IsEmpty(Queue : PCFIFOQueue) : boolean;
begin
  CFIFO_IsEmpty := (Queue^.Count = 0);
end;

function CFIFO_Capacity(Queue : PCFIFOQueue) : uint32;
begin
  CFIFO_Capacity := Queue^.Capacity;
end;

procedure CFIFO_Free(Queue : PCFIFOQueue);
begin
  if Queue = nil then exit;
  kfree(Queue^.Data);
  kfree(void(Queue));
end;

procedure UnitTest;
var
    q    : PCFIFOQueue;
    v, r : uint32;
    nativeValue, nativeResult: PtrUInt;
    ok   : boolean;
    p    : void;
    i    : uint32;
    passed, failed : uint32;

    procedure Assert(condition : boolean; testName : pchar);
    var
        msg : pchar;
    begin
        if condition then begin
            inc(passed);
        end else begin
            inc(failed);
            msg := stringConcat('FAIL: ', testName);
            arch.platform.diagnostics.log('CFIFO', msg);
            kfree(void(msg));
        end;
    end;


begin
    passed := 0;
    failed := 0;
    arch.platform.diagnostics.log('CFIFO', 'Unit tests starting...');

    { === New / Empty / Size / Capacity === }
    q := CFIFO_New(sizeof(uint32), 4);
    Assert(q <> nil, 'New returns non-nil');
    Assert(CFIFO_IsEmpty(q), 'Initially empty');
    Assert(CFIFO_Size(q) = 0, 'Initial size is 0');
    Assert(CFIFO_Capacity(q) = 4, 'Initial capacity is 4');

    { === Fill initial capacity === }
    for i := 1 to 4 do
    begin
        v := i * 10;
        CFIFO_Enqueue(q, @v);
    end;
    Assert(CFIFO_Size(q) = 4, 'Size after 4 enqueues');

    { === Dequeue first two to advance Head === }
    ok := CFIFO_Dequeue(q, @r);
    Assert(ok, 'Dequeue 1 succeeds');
    Assert(r = 10, 'Dequeue 1 value');
    ok := CFIFO_Dequeue(q, @r);
    Assert(ok, 'Dequeue 2 succeeds');
    Assert(r = 20, 'Dequeue 2 value');
    Assert(CFIFO_Size(q) = 2, 'Size after 2 dequeues');

    { === Enqueue more to trigger compaction/growth === }
    for i := 5 to 8 do
    begin
        v := i * 10;
        CFIFO_Enqueue(q, @v);
    end;
    Assert(CFIFO_Size(q) = 6, 'Size after grow');

    { === Verify FIFO order: 30,40,50,60,70,80 === }
    ok := CFIFO_Dequeue(q, @r);
    Assert(r = 30, 'Order 30');
    ok := CFIFO_Dequeue(q, @r);
    Assert(r = 40, 'Order 40');
    ok := CFIFO_Dequeue(q, @r);
    Assert(r = 50, 'Order 50');
    ok := CFIFO_Dequeue(q, @r);
    Assert(r = 60, 'Order 60');
    ok := CFIFO_Dequeue(q, @r);
    Assert(r = 70, 'Order 70');
    ok := CFIFO_Dequeue(q, @r);
    Assert(r = 80, 'Order 80');
    Assert(CFIFO_IsEmpty(q), 'Empty after drain');

    { === Edge: peek/dequeue on empty === }
    p := CFIFO_Peek(q);
    Assert(p = nil, 'Peek on empty returns nil');
    ok := CFIFO_Dequeue(q, @r);
    Assert(not ok, 'Dequeue on empty returns false');

    CFIFO_Free(q);

    q := CFIFO_New(sizeof(PtrUInt), 0);
    nativeValue := PtrUInt(q);
    CFIFO_Enqueue(q, void(@nativeValue));
    Assert(CFIFO_Dequeue(q, void(@nativeResult)) and (nativeResult = nativeValue),
        'Native pointer survives queue storage');
    CFIFO_Free(q);
    Assert(CFIFO_New(0, 4) = nil, 'Zero-sized elements rejected');

    testSummary('CFIFO', 'CFIFO_TESTS_PASSED', 'CFIFO_TESTS_FAILED', passed, failed);
end;

end.
