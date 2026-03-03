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
unit q_fifo;

interface

uses
    lmemorymanager,
    util,
    q_types;

{ ============================================================================ }
{                        FIFO Queue — Q_FIFO_* API                             }
{ ============================================================================ }

  {**
    @abstract Creates a new FIFO queue.
    @param ElementSize Size (in bytes) of each element.
    @returns Pointer to the new queue.
  **}
  function Q_FIFO_New(ElementSize : uint32) : PFIFOQueue;

  {**
    @abstract Enqueues an element at the back of the FIFO queue.
    @param Queue Pointer to the FIFO queue.
    @param Data  Pointer to the element data to copy in.
  **}
  procedure Q_FIFO_Enqueue(Queue : PFIFOQueue; Data : void);

  {**
    @abstract Dequeues the front element from the FIFO queue.
    @param Queue Pointer to the FIFO queue.
    @param Data  Pointer to a buffer that receives the dequeued element.
    @returns True if an element was dequeued, false if the queue was empty.
  **}
  function Q_FIFO_Dequeue(Queue : PFIFOQueue; Data : void) : boolean;

  {**
    @abstract Peeks at the front element without removing it.
    @param Queue Pointer to the FIFO queue.
    @returns Pointer to the front element data, or nil if empty.
  **}
  function Q_FIFO_Peek(Queue : PFIFOQueue) : void;

  {**
    @abstract Returns the number of elements in the FIFO queue.
    @param Queue Pointer to the FIFO queue.
    @returns Element count.
  **}
  function Q_FIFO_Size(Queue : PFIFOQueue) : uint32;

  {**
    @abstract Checks whether the FIFO queue is empty.
    @param Queue Pointer to the FIFO queue.
    @returns True if empty.
  **}
  function Q_FIFO_IsEmpty(Queue : PFIFOQueue) : boolean;

  {**
    @abstract Frees the FIFO queue and all its nodes.
    @param Queue Pointer to the FIFO queue.
  **}
  procedure Q_FIFO_Free(Queue : PFIFOQueue);

implementation

function Q_FIFO_New(ElementSize : uint32) : PFIFOQueue;
begin
  Q_FIFO_New := PFIFOQueue(kalloc(sizeof(TFIFOQueue)));
  Q_FIFO_New^.Head        := nil;
  Q_FIFO_New^.Tail        := nil;
  Q_FIFO_New^.Count       := 0;
  Q_FIFO_New^.ElementSize := ElementSize;
end;

procedure Q_FIFO_Enqueue(Queue : PFIFOQueue; Data : void);
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

function Q_FIFO_Dequeue(Queue : PFIFOQueue; Data : void) : boolean;
var
  Node : PQueueNode;
begin
  Q_FIFO_Dequeue := false;
  if Queue^.Head = nil then exit;

  Node := Queue^.Head;
  memcpy(uint32(Node^.Data), uint32(Data), Queue^.ElementSize);

  Queue^.Head := Node^.Next;
  if Queue^.Head = nil then
    Queue^.Tail := nil;

  Queue^.Count := Queue^.Count - 1;
  kfree(Node^.Data);
  kfree(void(Node));
  Q_FIFO_Dequeue := true;
end;

function Q_FIFO_Peek(Queue : PFIFOQueue) : void;
begin
  if Queue^.Head = nil then
    Q_FIFO_Peek := nil
  else
    Q_FIFO_Peek := Queue^.Head^.Data;
end;

function Q_FIFO_Size(Queue : PFIFOQueue) : uint32;
begin
  Q_FIFO_Size := Queue^.Count;
end;

function Q_FIFO_IsEmpty(Queue : PFIFOQueue) : boolean;
begin
  Q_FIFO_IsEmpty := (Queue^.Count = 0);
end;

procedure Q_FIFO_Free(Queue : PFIFOQueue);
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

end.
