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
	Queue LIFO - Last-In First-Out stack, linked-list backed.

	@author(Aaron Hance <ah@aaronhance.me>)
}
unit q_lifo;

interface

uses
    lmemorymanager,
    util,
    q_types;

{ ============================================================================ }
{                        LIFO Stack — Q_LIFO_* API                             }
{ ============================================================================ }

  {**
    @abstract Creates a new LIFO stack.
    @param ElementSize Size (in bytes) of each element.
    @returns Pointer to the new stack.
  **}
  function Q_LIFO_New(ElementSize : uint32) : PLIFOStack;

  {**
    @abstract Pushes an element onto the top of the stack.
    @param Stack Pointer to the LIFO stack.
    @param Data  Pointer to the element data to copy in.
  **}
  procedure Q_LIFO_Push(Stack : PLIFOStack; Data : void);

  {**
    @abstract Pops the top element from the stack.
    @param Stack Pointer to the LIFO stack.
    @param Data  Pointer to a buffer that receives the popped element.
    @returns True if an element was popped, false if the stack was empty.
  **}
  function Q_LIFO_Pop(Stack : PLIFOStack; Data : void) : boolean;

  {**
    @abstract Peeks at the top element without removing it.
    @param Stack Pointer to the LIFO stack.
    @returns Pointer to the top element data, or nil if empty.
  **}
  function Q_LIFO_Peek(Stack : PLIFOStack) : void;

  {**
    @abstract Returns the number of elements on the stack.
    @param Stack Pointer to the LIFO stack.
    @returns Element count.
  **}
  function Q_LIFO_Size(Stack : PLIFOStack) : uint32;

  {**
    @abstract Checks whether the stack is empty.
    @param Stack Pointer to the LIFO stack.
    @returns True if empty.
  **}
  function Q_LIFO_IsEmpty(Stack : PLIFOStack) : boolean;

  {**
    @abstract Frees the stack and all its nodes.
    @param Stack Pointer to the LIFO stack.
  **}
  procedure Q_LIFO_Free(Stack : PLIFOStack);

implementation

function Q_LIFO_New(ElementSize : uint32) : PLIFOStack;
begin
  Q_LIFO_New := PLIFOStack(kalloc(sizeof(TLIFOStack)));
  Q_LIFO_New^.Top         := nil;
  Q_LIFO_New^.Count       := 0;
  Q_LIFO_New^.ElementSize := ElementSize;
end;

procedure Q_LIFO_Push(Stack : PLIFOStack; Data : void);
var
  Node : PQueueNode;
begin
  Node := PQueueNode(kalloc(sizeof(TQueueNode)));
  Node^.Data := kalloc(Stack^.ElementSize);
  memcpy(uint32(Data), uint32(Node^.Data), Stack^.ElementSize);
  Node^.Next := Stack^.Top;
  Stack^.Top   := Node;
  Stack^.Count := Stack^.Count + 1;
end;

function Q_LIFO_Pop(Stack : PLIFOStack; Data : void) : boolean;
var
  Node : PQueueNode;
begin
  Q_LIFO_Pop := false;
  if Stack^.Top = nil then exit;

  Node := Stack^.Top;
  memcpy(uint32(Node^.Data), uint32(Data), Stack^.ElementSize);

  Stack^.Top   := Node^.Next;
  Stack^.Count := Stack^.Count - 1;
  kfree(Node^.Data);
  kfree(void(Node));
  Q_LIFO_Pop := true;
end;

function Q_LIFO_Peek(Stack : PLIFOStack) : void;
begin
  if Stack^.Top = nil then
    Q_LIFO_Peek := nil
  else
    Q_LIFO_Peek := Stack^.Top^.Data;
end;

function Q_LIFO_Size(Stack : PLIFOStack) : uint32;
begin
  Q_LIFO_Size := Stack^.Count;
end;

function Q_LIFO_IsEmpty(Stack : PLIFOStack) : boolean;
begin
  Q_LIFO_IsEmpty := (Stack^.Count = 0);
end;

procedure Q_LIFO_Free(Stack : PLIFOStack);
var
  Node, Next : PQueueNode;
begin
  if Stack = nil then exit;
  Node := Stack^.Top;
  while Node <> nil do
  begin
    Next := Node^.Next;
    kfree(Node^.Data);
    kfree(void(Node));
    Node := Next;
  end;
  kfree(void(Stack));
end;

end.
