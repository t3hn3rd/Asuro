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
	Queue FIFO - First-In First-Out queue, linked-list backed.

	@author(Aaron Hance <ah@aaronhance.me>)
}
unit fifo;

interface

uses
    lmemorymanager,
    util,
    dstypes;

{ ============================================================================ }
{                        FIFO Queue — FIFO_* API                             }
{ ============================================================================ }

  {**
    @abstract Creates a new FIFO queue.
    @param ElementSize Size (in bytes) of each element.
    @returns Pointer to the new queue.
  **}
  function FIFO_New(ElementSize : uint32) : PFIFOQueue;

  {**
    @abstract Enqueues an element at the back of the FIFO queue.
    @param Queue Pointer to the FIFO queue.
    @param Data  Pointer to the element data to copy in.
  **}
  procedure FIFO_Enqueue(Queue : PFIFOQueue; Data : void);

  {**
    @abstract Dequeues the front element from the FIFO queue.
    @param Queue Pointer to the FIFO queue.
    @param Data  Pointer to a buffer that receives the dequeued element.
    @returns True if an element was dequeued, false if the queue was empty.
  **}
  function FIFO_Dequeue(Queue : PFIFOQueue; Data : void) : boolean;

  {**
    @abstract Peeks at the front element without removing it.
    @param Queue Pointer to the FIFO queue.
    @returns Pointer to the front element data, or nil if empty.
  **}
  function FIFO_Peek(Queue : PFIFOQueue) : void;

  {**
    @abstract Returns the number of elements in the FIFO queue.
    @param Queue Pointer to the FIFO queue.
    @returns Element count.
  **}
  function FIFO_Size(Queue : PFIFOQueue) : uint32;

  {**
    @abstract Checks whether the FIFO queue is empty.
    @param Queue Pointer to the FIFO queue.
    @returns True if empty.
  **}
  function FIFO_IsEmpty(Queue : PFIFOQueue) : boolean;

  {**
    @abstract Frees the FIFO queue and all its nodes.
    @param Queue Pointer to the FIFO queue.
  **}
  procedure FIFO_Free(Queue : PFIFOQueue);

  {** Runs unit tests for the FIFO queue. **}
  procedure UnitTest;

implementation

uses
    syslog, strings;

function FIFO_New(ElementSize : uint32) : PFIFOQueue;
begin
  FIFO_New := PFIFOQueue(kalloc(sizeof(TFIFOQueue)));
  FIFO_New^.Head        := nil;
  FIFO_New^.Tail        := nil;
  FIFO_New^.Count       := 0;
  FIFO_New^.ElementSize := ElementSize;
end;

procedure FIFO_Enqueue(Queue : PFIFOQueue; Data : void);
var
  Node : PQueueNode;
begin
  Node := PQueueNode(kalloc(sizeof(TQueueNode)));
  Node^.Next := nil;
  Node^.Data := kalloc(Queue^.ElementSize);
  memcpy(uint32(Data), uint32(Node^.Data), Queue^.ElementSize);

  if Queue^.Tail <> nil then
    Queue^.Tail^.Next := Node
  else
    Queue^.Head := Node;

  Queue^.Tail  := Node;
  Queue^.Count := Queue^.Count + 1;
end;

function FIFO_Dequeue(Queue : PFIFOQueue; Data : void) : boolean;
var
  Node : PQueueNode;
begin
  FIFO_Dequeue := false;
  if Queue^.Head = nil then exit;

  Node := Queue^.Head;
  memcpy(uint32(Node^.Data), uint32(Data), Queue^.ElementSize);

  Queue^.Head := Node^.Next;
  if Queue^.Head = nil then
    Queue^.Tail := nil;

  Queue^.Count := Queue^.Count - 1;
  kfree(Node^.Data);
  kfree(void(Node));
  FIFO_Dequeue := true;
end;

function FIFO_Peek(Queue : PFIFOQueue) : void;
begin
  if Queue^.Head = nil then
    FIFO_Peek := nil
  else
    FIFO_Peek := Queue^.Head^.Data;
end;

function FIFO_Size(Queue : PFIFOQueue) : uint32;
begin
  FIFO_Size := Queue^.Count;
end;

function FIFO_IsEmpty(Queue : PFIFOQueue) : boolean;
begin
  FIFO_IsEmpty := (Queue^.Count = 0);
end;

procedure FIFO_Free(Queue : PFIFOQueue);
var
  Node, Next : PQueueNode;
begin
  if Queue = nil then exit;
  Node := Queue^.Head;
  while Node <> nil do
  begin
    Next := Node^.Next;
    kfree(Node^.Data);
    kfree(void(Node));
    Node := Next;
  end;
  kfree(void(Queue));
end;

procedure UnitTest;
var
    q    : PFIFOQueue;
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
            syslog.logln('FIFO', msg);
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
        syslog.logln('FIFO', msg);
        kfree(void(msg));
        kfree(void(pStr));
        kfree(void(fStr));
    end;

begin
    passed := 0;
    failed := 0;
    syslog.logln('FIFO', 'Unit tests starting...');

    { === New / Empty / Size === }
    q := FIFO_New(sizeof(uint32));
    Assert(q <> nil, 'New returns non-nil');
    Assert(FIFO_IsEmpty(q), 'Initially empty');
    Assert(FIFO_Size(q) = 0, 'Initial size is 0');

    { === Enqueue / Size === }
    v := 10; FIFO_Enqueue(q, @v);
    v := 20; FIFO_Enqueue(q, @v);
    v := 30; FIFO_Enqueue(q, @v);
    Assert(FIFO_Size(q) = 3, 'Size after 3 enqueues');
    Assert(not FIFO_IsEmpty(q), 'Not empty after enqueue');

    { === Peek === }
    p := FIFO_Peek(q);
    Assert(p <> nil, 'Peek non-nil');
    Assert(uint32(p^) = 10, 'Peek returns first enqueued');

    { === Dequeue order === }
    ok := FIFO_Dequeue(q, @r);
    Assert(ok, 'Dequeue 1 succeeds');
    Assert(r = 10, 'Dequeue 1 value');

    ok := FIFO_Dequeue(q, @r);
    Assert(ok, 'Dequeue 2 succeeds');
    Assert(r = 20, 'Dequeue 2 value');

    ok := FIFO_Dequeue(q, @r);
    Assert(ok, 'Dequeue 3 succeeds');
    Assert(r = 30, 'Dequeue 3 value');

    Assert(FIFO_IsEmpty(q), 'Empty after all dequeued');

    { === Edge: dequeue/peek on empty === }
    ok := FIFO_Dequeue(q, @r);
    Assert(not ok, 'Dequeue on empty returns false');
    p := FIFO_Peek(q);
    Assert(p = nil, 'Peek on empty returns nil');

    FIFO_Free(q);

    PrintSummary;
end;

end.
