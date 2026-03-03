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

  {** Runs unit tests for the priority queue. **}
  procedure UnitTest;

implementation

uses
    syslog, strings, lmemorymanager;

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

procedure UnitTest;
var
    h    : PBinaryHeap;
    v, r : uint32;
    ok   : boolean;
    p    : void;
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
            syslog.logln('PRIO', msg);
            kfree(void(msg));
        end;
    end;

    procedure PrintSummary;
    var
        pStr, fStr, msg, tmp : pchar;
    begin
        pStr := intToString(passed);
        fStr := intToString(failed);
        msg := stringConcat(pStr, ' passed, ');
        tmp := stringConcat(msg, fStr);
        kfree(void(msg));
        msg := stringConcat(tmp, ' failed.');
        kfree(void(tmp));
        syslog.logln('PRIO', msg);
        kfree(void(msg));
        kfree(void(pStr));
        kfree(void(fStr));
    end;

begin
    passed := 0;
    failed := 0;
    syslog.logln('PRIO', 'Unit tests starting...');

    { === New / Empty === }
    h := prio_New(sizeof(uint32), 4);
    Assert(h <> nil, 'New returns non-nil');
    Assert(prio_IsEmpty(h), 'Initially empty');

    { === Enqueue with varying priorities === }
    v := 300; prio_Enqueue(h, 3, @v);
    v := 100; prio_Enqueue(h, 1, @v);
    v := 500; prio_Enqueue(h, 5, @v);
    v := 200; prio_Enqueue(h, 2, @v);
    v := 400; prio_Enqueue(h, 4, @v);
    Assert(prio_Size(h) = 5, 'Size after 5 enqueues');

    { === Peek (highest priority = lowest value) === }
    p := prio_Peek(h);
    Assert(p <> nil, 'Peek non-nil');
    Assert(uint32(p^) = 100, 'Peek returns data with priority 1');

    { === Dequeue by priority 1,2,3,4,5 === }
    ok := prio_Dequeue(h, @r); Assert(ok, 'Dequeue 1 ok'); Assert(r = 100, 'Dequeue pri=1');
    ok := prio_Dequeue(h, @r); Assert(ok, 'Dequeue 2 ok'); Assert(r = 200, 'Dequeue pri=2');
    ok := prio_Dequeue(h, @r); Assert(ok, 'Dequeue 3 ok'); Assert(r = 300, 'Dequeue pri=3');
    ok := prio_Dequeue(h, @r); Assert(ok, 'Dequeue 4 ok'); Assert(r = 400, 'Dequeue pri=4');
    ok := prio_Dequeue(h, @r); Assert(ok, 'Dequeue 5 ok'); Assert(r = 500, 'Dequeue pri=5');
    Assert(prio_IsEmpty(h), 'Empty after all dequeued');

    { === Edge: dequeue/peek on empty === }
    ok := prio_Dequeue(h, @r);
    Assert(not ok, 'Dequeue on empty returns false');
    p := prio_Peek(h);
    Assert(p = nil, 'Peek on empty returns nil');

    prio_Free(h);

    PrintSummary;
end;

end.