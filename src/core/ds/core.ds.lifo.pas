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
	LIFO Stack - Last-In First-Out stack, linked-list backed.

	@author(Aaron Hance <ah@aaronhance.me>)
}
unit core.ds.lifo;

interface

uses
    memory.heap,
    core.util,
    core.ds.types;

{ ============================================================================ }
{                        LIFO Stack — lifo_* API                             }
{ ============================================================================ }

  {**
    @abstract Creates a new LIFO stack.
    @param ElementSize Size (in bytes) of each element.
    @returns Pointer to the new stack.
  **}
  function lifo_New(ElementSize : uint32) : PLIFOStack;

  {**
    @abstract Pushes an element onto the top of the stack.
    @param Stack Pointer to the LIFO stack.
    @param Data  Pointer to the element data to copy in.
  **}
  procedure lifo_Push(Stack : PLIFOStack; Data : void);

  {**
    @abstract Pops the top element from the stack.
    @param Stack Pointer to the LIFO stack.
    @param Data  Pointer to a buffer that receives the popped element.
    @returns True if an element was popped, false if the stack was empty.
  **}
  function lifo_Pop(Stack : PLIFOStack; Data : void) : boolean;

  {**
    @abstract Peeks at the top element without removing it.
    @param Stack Pointer to the LIFO stack.
    @returns Pointer to the top element data, or nil if empty.
  **}
  function lifo_Peek(Stack : PLIFOStack) : void;

  {**
    @abstract Returns the number of elements on the stack.
    @param Stack Pointer to the LIFO stack.
    @returns Element count.
  **}
  function lifo_Size(Stack : PLIFOStack) : uint32;

  {**
    @abstract Checks whether the stack is empty.
    @param Stack Pointer to the LIFO stack.
    @returns True if empty.
  **}
  function lifo_IsEmpty(Stack : PLIFOStack) : boolean;

  {**
    @abstract Frees the stack and all its nodes.
    @param Stack Pointer to the LIFO stack.
  **}
  procedure lifo_Free(Stack : PLIFOStack);

  {** Runs unit tests for the LIFO stack. **}
  procedure UnitTest;

implementation

uses
    test.harness,
    io.syslog, core.strings;

function lifo_New(ElementSize : uint32) : PLIFOStack;
begin
  lifo_New := PLIFOStack(kalloc(sizeof(TLIFOStack)));
  lifo_New^.Top         := nil;
  lifo_New^.Count       := 0;
  lifo_New^.ElementSize := ElementSize;
end;

procedure lifo_Push(Stack : PLIFOStack; Data : void);
var
  Node : PQueueNode;
begin
  Node := PQueueNode(kalloc(sizeof(TQueueNode)));
  Node^.Data := kalloc(Stack^.ElementSize);
  memcpy(PtrUInt(Data), PtrUInt(Node^.Data), Stack^.ElementSize);
  Node^.Next := Stack^.Top;
  Stack^.Top   := Node;
  Stack^.Count := Stack^.Count + 1;
end;

function lifo_Pop(Stack : PLIFOStack; Data : void) : boolean;
var
  Node : PQueueNode;
begin
  lifo_Pop := false;
  if Stack^.Top = nil then exit;

  Node := Stack^.Top;
  memcpy(PtrUInt(Node^.Data), PtrUInt(Data), Stack^.ElementSize);

  Stack^.Top   := Node^.Next;
  Stack^.Count := Stack^.Count - 1;
  kfree(Node^.Data);
  kfree(void(Node));
  lifo_Pop := true;
end;

function lifo_Peek(Stack : PLIFOStack) : void;
begin
  if Stack^.Top = nil then
    lifo_Peek := nil
  else
    lifo_Peek := Stack^.Top^.Data;
end;

function lifo_Size(Stack : PLIFOStack) : uint32;
begin
  lifo_Size := Stack^.Count;
end;

function lifo_IsEmpty(Stack : PLIFOStack) : boolean;
begin
  lifo_IsEmpty := (Stack^.Count = 0);
end;

procedure lifo_Free(Stack : PLIFOStack);
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

procedure UnitTest;
var
    s    : PLIFOStack;
    v, r : uint32;
    ok   : boolean;
    p    : void;
    context : TTestContext;

begin
    test.harness.Start(@context, 'core.ds.lifo');

    { === New / Empty / Size === }
    s := lifo_New(sizeof(uint32));
    test.harness.Assert(@context, s <> nil, 'New returns non-nil');
    test.harness.Assert(@context, lifo_IsEmpty(s), 'Initially empty');
    test.harness.Assert(@context, lifo_Size(s) = 0, 'Initial size is 0');

    { === Push / Size === }
    v := 10; lifo_Push(s, @v);
    v := 20; lifo_Push(s, @v);
    v := 30; lifo_Push(s, @v);
    test.harness.Assert(@context, lifo_Size(s) = 3, 'Size after 3 pushes');

    { === Peek (should return last pushed) === }
    p := lifo_Peek(s);
    test.harness.Assert(@context, p <> nil, 'Peek non-nil');
    test.harness.Assert(@context, uint32(p^) = 30, 'Peek returns last pushed');

    { === Pop order (reverse) === }
    ok := lifo_Pop(s, @r);
    test.harness.Assert(@context, ok, 'Pop 1 succeeds');
    test.harness.Assert(@context, r = 30, 'Pop 1 value');

    ok := lifo_Pop(s, @r);
    test.harness.Assert(@context, ok, 'Pop 2 succeeds');
    test.harness.Assert(@context, r = 20, 'Pop 2 value');

    ok := lifo_Pop(s, @r);
    test.harness.Assert(@context, ok, 'Pop 3 succeeds');
    test.harness.Assert(@context, r = 10, 'Pop 3 value');

    test.harness.Assert(@context, lifo_IsEmpty(s), 'Empty after all popped');

    { === Edge: pop/peek on empty === }
    ok := lifo_Pop(s, @r);
    test.harness.Assert(@context, not ok, 'Pop on empty returns false');
    p := lifo_Peek(s);
    test.harness.Assert(@context, p = nil, 'Peek on empty returns nil');

    lifo_Free(s);

    test.harness.Finish(@context);
end;

end.
