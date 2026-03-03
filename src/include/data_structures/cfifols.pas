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
	Queue Contiguous FIFO List - Dynamic list of contiguous FIFO queues.

	@author(Aaron Hance <ah@aaronhance.me>)
}
unit cfifols;

interface

uses
    lmemorymanager,
    dstypes,
    cfifo,
    util;

{ ============================================================================ }
{                 Contiguous FIFO List — CFIFOLS_* API                       }
{ ============================================================================ }

  {**
    @abstract Creates a new contiguous FIFO list.
    @param InitialCapacity Starting number of pointer slots.
    @returns Pointer to the new list.
  **}
  function CFIFOLS_New(InitialCapacity : uint32) : PCFIFOList;

  {**
    @abstract Appends an existing contiguous FIFO queue to the list.
    @param List  Pointer to the list.
    @param Queue Pointer to the contiguous FIFO queue to add.
  **}
  procedure CFIFOLS_Add(List : PCFIFOList; Queue : PCFIFOQueue);

  {**
    @abstract Returns the contiguous FIFO queue at the given index.
    @param List  Pointer to the list.
    @param Index Zero-based index.
    @returns The PCFIFOQueue at Index, or nil if Index is out of range.
  **}
  function CFIFOLS_Get(List : PCFIFOList; Index : uint32) : PCFIFOQueue;

  {**
    @abstract Removes the queue pointer at the given index.
    @discussion Shifts subsequent entries left. Does NOT free the removed
                queue itself — the caller retains ownership.
    @param List  Pointer to the list.
    @param Index Zero-based index to remove.
    @returns True if the index was valid and an entry was removed.
  **}
  function CFIFOLS_Remove(List : PCFIFOList; Index : uint32) : boolean;

  {**
    @abstract Returns the number of queues in the list.
    @param List Pointer to the list.
    @returns Queue count.
  **}
  function CFIFOLS_Count(List : PCFIFOList) : uint32;

  {**
    @abstract Checks whether the list is empty.
    @param List Pointer to the list.
    @returns True if empty.
  **}
  function CFIFOLS_IsEmpty(List : PCFIFOList) : boolean;

  {**
    @abstract Frees the list structure only.
    @discussion Does NOT free the contained queues. Use CFIFOLS_FreeAll
                to free both the list and every queue it holds.
    @param List Pointer to the list.
  **}
  procedure CFIFOLS_Free(List : PCFIFOList);

  {**
    @abstract Frees the list AND every queue it contains.
    @discussion Calls CFIFO_Free on each queue, then frees the list.
    @param List Pointer to the list.
  **}
  procedure CFIFOLS_FreeAll(List : PCFIFOList);

implementation

{ ---------------------------------------------------------------------------- }
{  Internal helpers                                                            }
{ ---------------------------------------------------------------------------- }

{** Returns pointer to the PCFIFOQueue slot at index i. **}
function CFIFOLS_SlotAt(List : PCFIFOList; i : uint32) : PCFIFOQueue; inline;
begin
  { Each slot is sizeof(PCFIFOQueue) = 4 bytes (pointer on i386) }
  CFIFOLS_SlotAt := PCFIFOQueue(pointer(uint32(List^.Items) + i * sizeof(PCFIFOQueue))^);
end;

{** Writes a PCFIFOQueue pointer into slot i. **}
procedure CFIFOLS_SetSlot(List : PCFIFOList; i : uint32; Queue : PCFIFOQueue); inline;
var
  slotPtr : ^PCFIFOQueue;
begin
  slotPtr := pointer(uint32(List^.Items) + i * sizeof(PCFIFOQueue));
  slotPtr^ := Queue;
end;

{** Doubles the list capacity. **}
procedure CFIFOLS_Grow(List : PCFIFOList);
var
  newCap  : uint32;
  newBuf  : void;
  oldSize : uint32;
begin
  newCap := List^.Capacity * 2;
  if newCap = 0 then newCap := 4;

  newBuf := kalloc(newCap * sizeof(PCFIFOQueue));
  memset(uint32(newBuf), 0, newCap * sizeof(PCFIFOQueue));

  oldSize := List^.Count * sizeof(PCFIFOQueue);
  if oldSize > 0 then
    memcpy(uint32(List^.Items), uint32(newBuf), oldSize);

  kfree(List^.Items);
  List^.Items    := newBuf;
  List^.Capacity := newCap;
end;

{ ---------------------------------------------------------------------------- }
{  Public API                                                                  }
{ ---------------------------------------------------------------------------- }

function CFIFOLS_New(InitialCapacity : uint32) : PCFIFOList;
begin
  CFIFOLS_New := PCFIFOList(kalloc(sizeof(TCFIFOList)));
  CFIFOLS_New^.Count    := 0;
  CFIFOLS_New^.Capacity := InitialCapacity;
  CFIFOLS_New^.Items    := kalloc(InitialCapacity * sizeof(PCFIFOQueue));
  memset(uint32(CFIFOLS_New^.Items), 0, InitialCapacity * sizeof(PCFIFOQueue));
end;

procedure CFIFOLS_Add(List : PCFIFOList; Queue : PCFIFOQueue);
begin
  if List^.Count >= List^.Capacity then
    CFIFOLS_Grow(List);

  CFIFOLS_SetSlot(List, List^.Count, Queue);
  List^.Count := List^.Count + 1;
end;

function CFIFOLS_Get(List : PCFIFOList; Index : uint32) : PCFIFOQueue;
begin
  if Index >= List^.Count then
    CFIFOLS_Get := nil
  else
    CFIFOLS_Get := CFIFOLS_SlotAt(List, Index);
end;

function CFIFOLS_Remove(List : PCFIFOList; Index : uint32) : boolean;
var
  src, dst, len : uint32;
begin
  CFIFOLS_Remove := false;
  if Index >= List^.Count then exit;

  List^.Count := List^.Count - 1;

  { Shift remaining entries left by one slot }
  if Index < List^.Count then
  begin
    dst := uint32(List^.Items) + Index * sizeof(PCFIFOQueue);
    src := dst + sizeof(PCFIFOQueue);
    len := (List^.Count - Index) * sizeof(PCFIFOQueue);
    memcpy(src, dst, len);
  end;

  CFIFOLS_Remove := true;
end;

function CFIFOLS_Count(List : PCFIFOList) : uint32;
begin
  CFIFOLS_Count := List^.Count;
end;

function CFIFOLS_IsEmpty(List : PCFIFOList) : boolean;
begin
  CFIFOLS_IsEmpty := (List^.Count = 0);
end;

procedure CFIFOLS_Free(List : PCFIFOList);
begin
  if List = nil then exit;
  kfree(List^.Items);
  kfree(void(List));
end;

procedure CFIFOLS_FreeAll(List : PCFIFOList);
var
  i : uint32;
  q : PCFIFOQueue;
begin
  if List = nil then exit;
  for i := 0 to List^.Count - 1 do
  begin
    q := CFIFOLS_SlotAt(List, i);
    if q <> nil then
      CFIFO_Free(q);
  end;
  kfree(List^.Items);
  kfree(void(List));
end;

end.
