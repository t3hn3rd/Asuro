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
	Queue Binary Heap - Shared heap internals for min-heap, max-heap
	and priority queue. Uses index-array indirection for O(1) swaps
	with inline element storage and a free-slot recycling stack.

	@author(Aaron Hance <ah@aaronhance.me>)
}
unit q_heap;

interface

uses
    lmemorymanager,
    q_types,
    util;

  {** Creates a new BinaryHeap.
    @param ElementSize     Size (in bytes) of each data element.
    @param InitialCapacity Starting number of slots.
    @param MinHeap         True for min-heap ordering, false for max-heap.
    @returns Pointer to the new heap.
  **}
  function BH_New(ElementSize : uint32; InitialCapacity : uint32;
                  MinHeap : boolean) : PBinaryHeap;

  {** Inserts an element with the given priority into the heap. **}
  procedure BH_Insert(Heap : PBinaryHeap; Priority : uint32; Data : void);

  {** Extracts the root element from the heap. Copies data into OutData.
    @returns True if extracted, false if heap was empty.
  **}
  function BH_ExtractRoot(Heap : PBinaryHeap; OutData : void) : boolean;

  {** Peeks at the root element.
    @returns Pointer to root data, or nil if empty.
  **}
  function BH_PeekRoot(Heap : PBinaryHeap) : void;

  {** Frees the heap and its buffers. **}
  procedure BH_Free(Heap : PBinaryHeap);

implementation

{ ---------------------------------------------------------------------------- }
{  Data-slot layout in the flat buffer                                         }
{                                                                              }
{  offset 0              : Priority (uint32)                                   }
{  offset sizeof(uint32) : Element data (ElementSize bytes)                    }
{  Total per slot        : NodeStride = sizeof(uint32) + ElementSize           }
{ ---------------------------------------------------------------------------- }

{ ---------------------------------------------------------------------------- }
{  Internal helpers — index array                                              }
{ ---------------------------------------------------------------------------- }

{** Returns a pointer to Indices[i] (the uint32 slot stored there). **}
function BH_IdxPtr(Heap : PBinaryHeap; i : uint32) : void; inline;
begin
  BH_IdxPtr := void(uint32(Heap^.Indices) + i * sizeof(uint32));
end;

{** Returns the data-slot index stored at heap position i. **}
function BH_IdxGet(Heap : PBinaryHeap; i : uint32) : uint32; inline;
begin
  BH_IdxGet := void(uint32(Heap^.Indices) + i * sizeof(uint32))^;
end;

{** Writes a data-slot index into heap position i. **}
procedure BH_IdxSet(Heap : PBinaryHeap; i : uint32; slot : uint32); inline;
begin
  void(uint32(Heap^.Indices) + i * sizeof(uint32))^ := slot;
end;

{ ---------------------------------------------------------------------------- }
{  Internal helpers — data-slot access (goes through Indices)                  }
{ ---------------------------------------------------------------------------- }

{** Returns pointer to the start of the data slot for heap position i. **}
function BH_SlotPtr(Heap : PBinaryHeap; i : uint32) : void; inline;
begin
  BH_SlotPtr := void(uint32(Heap^.Data) + BH_IdxGet(Heap, i) * Heap^.NodeStride);
end;

{** Returns the priority of the element at heap position i. **}
function BH_GetPri(Heap : PBinaryHeap; i : uint32) : uint32; inline;
begin
  BH_GetPri := void(uint32(Heap^.Data) + BH_IdxGet(Heap, i) * Heap^.NodeStride)^;
end;

{** Returns pointer to the inline element data at heap position i. **}
function BH_DataPtr(Heap : PBinaryHeap; i : uint32) : void; inline;
begin
  BH_DataPtr := void(uint32(Heap^.Data)
                     + BH_IdxGet(Heap, i) * Heap^.NodeStride
                     + sizeof(uint32));
end;

{ ---------------------------------------------------------------------------- }
{  Internal helpers — free-slot stack                                          }
{ ---------------------------------------------------------------------------- }

{** Pushes a freed data-slot index onto the free stack. **}
procedure BH_FreePush(Heap : PBinaryHeap; slot : uint32); inline;
begin
  void(uint32(Heap^.FreeSlots) + Heap^.FreeCount * sizeof(uint32))^ := slot;
  Heap^.FreeCount := Heap^.FreeCount + 1;
end;

{** Pops a data-slot index from the free stack. **}
function BH_FreePop(Heap : PBinaryHeap) : uint32; inline;
begin
  Heap^.FreeCount := Heap^.FreeCount - 1;
  BH_FreePop := void(uint32(Heap^.FreeSlots) + Heap^.FreeCount * sizeof(uint32))^;
end;

{ ---------------------------------------------------------------------------- }
{  Internal helpers — ordering                                                 }
{ ---------------------------------------------------------------------------- }

{** Returns true if heap position A should be above position B. **}
function BH_Compare(Heap : PBinaryHeap; A, B : uint32) : boolean; inline;
begin
  if Heap^.IsMinHeap then
    BH_Compare := BH_GetPri(Heap, A) <= BH_GetPri(Heap, B)
  else
    BH_Compare := BH_GetPri(Heap, A) >= BH_GetPri(Heap, B);
end;

{** Swaps two heap positions by exchanging their index entries. **}
procedure BH_Swap(Heap : PBinaryHeap; A, B : uint32); inline;
var
  tmp : uint32;
begin
  tmp := BH_IdxGet(Heap, A);
  BH_IdxSet(Heap, A, BH_IdxGet(Heap, B));
  BH_IdxSet(Heap, B, tmp);
end;

{** Restores heap property upward from position i. **}
procedure BH_SiftUp(Heap : PBinaryHeap; i : uint32);
var
  parent : uint32;
begin
  while i > 0 do
  begin
    parent := (i - 1) div 2;
    if BH_Compare(Heap, i, parent) then
    begin
      BH_Swap(Heap, i, parent);
      i := parent;
    end
    else
      break;
  end;
end;

{** Restores heap property downward from position i. **}
procedure BH_SiftDown(Heap : PBinaryHeap; i : uint32);
var
  best, left, right : uint32;
begin
  while true do
  begin
    best  := i;
    left  := 2 * i + 1;
    right := 2 * i + 2;

    if (left < Heap^.Count) and BH_Compare(Heap, left, best) then
      best := left;
    if (right < Heap^.Count) and BH_Compare(Heap, right, best) then
      best := right;

    if best = i then
      break;

    BH_Swap(Heap, i, best);
    i := best;
  end;
end;

{** Doubles all three arrays (Data, Indices, FreeSlots). **}
procedure BH_Grow(Heap : PBinaryHeap);
var
  newCap     : uint32;
  newData    : void;
  newIdx     : void;
  newFree    : void;
  dataBytes  : uint32;
  idxBytes   : uint32;
  freeBytes  : uint32;
begin
  newCap := Heap^.Capacity * 2;

  { Grow Data buffer }
  dataBytes := Heap^.NextSlot * Heap^.NodeStride;
  newData   := kalloc(newCap * Heap^.NodeStride);
  if dataBytes > 0 then
    memcpy(uint32(Heap^.Data), uint32(newData), dataBytes);
  kfree(Heap^.Data);
  Heap^.Data := newData;

  { Grow Indices array }
  idxBytes := Heap^.Count * sizeof(uint32);
  newIdx   := kalloc(newCap * sizeof(uint32));
  if idxBytes > 0 then
    memcpy(uint32(Heap^.Indices), uint32(newIdx), idxBytes);
  kfree(Heap^.Indices);
  Heap^.Indices := newIdx;

  { Grow FreeSlots stack }
  freeBytes := Heap^.FreeCount * sizeof(uint32);
  newFree   := kalloc(newCap * sizeof(uint32));
  if freeBytes > 0 then
    memcpy(uint32(Heap^.FreeSlots), uint32(newFree), freeBytes);
  kfree(Heap^.FreeSlots);
  Heap^.FreeSlots := newFree;

  Heap^.Capacity := newCap;
end;

{ ---------------------------------------------------------------------------- }
{  Public API                                                                  }
{ ---------------------------------------------------------------------------- }

function BH_New(ElementSize : uint32; InitialCapacity : uint32;
                MinHeap : boolean) : PBinaryHeap;
var
  stride : uint32;
begin
  stride := sizeof(uint32) + ElementSize;

  BH_New := PBinaryHeap(kalloc(sizeof(TBinaryHeap)));
  BH_New^.Count       := 0;
  BH_New^.Capacity    := InitialCapacity;
  BH_New^.NextSlot    := 0;
  BH_New^.FreeCount   := 0;
  BH_New^.ElementSize := ElementSize;
  BH_New^.NodeStride  := stride;
  BH_New^.IsMinHeap   := MinHeap;
  BH_New^.Data        := kalloc(InitialCapacity * stride);
  BH_New^.Indices     := kalloc(InitialCapacity * sizeof(uint32));
  BH_New^.FreeSlots   := kalloc(InitialCapacity * sizeof(uint32));
  memset(uint32(BH_New^.Data), 0, InitialCapacity * stride);
end;

procedure BH_Insert(Heap : PBinaryHeap; Priority : uint32; Data : void);
var
  slot    : uint32;
  slotPtr : void;
begin
  if Heap^.Count >= Heap^.Capacity then
    BH_Grow(Heap);

  { Acquire a data slot — recycle freed slot or take next sequential }
  if Heap^.FreeCount > 0 then
    slot := BH_FreePop(Heap)
  else
  begin
    slot := Heap^.NextSlot;
    Heap^.NextSlot := Heap^.NextSlot + 1;
  end;

  { Write priority + element data into the data slot }
  slotPtr := void(uint32(Heap^.Data) + slot * Heap^.NodeStride);
  slotPtr^ := Priority;
  memcpy(uint32(Data), uint32(slotPtr) + sizeof(uint32), Heap^.ElementSize);

  { Map the new heap position to this data slot }
  BH_IdxSet(Heap, Heap^.Count, slot);

  Heap^.Count := Heap^.Count + 1;
  BH_SiftUp(Heap, Heap^.Count - 1);
end;

function BH_ExtractRoot(Heap : PBinaryHeap; OutData : void) : boolean;
var
  rootSlot : uint32;
begin
  BH_ExtractRoot := false;
  if Heap^.Count = 0 then
    exit;

  { Copy root element data to caller }
  memcpy(uint32(BH_DataPtr(Heap, 0)), uint32(OutData), Heap^.ElementSize);

  { Recycle the root's data slot }
  rootSlot := BH_IdxGet(Heap, 0);
  BH_FreePush(Heap, rootSlot);

  Heap^.Count := Heap^.Count - 1;
  if Heap^.Count > 0 then
  begin
    { Move last index into root position and restore heap order }
    BH_IdxSet(Heap, 0, BH_IdxGet(Heap, Heap^.Count));
    BH_SiftDown(Heap, 0);
  end;

  BH_ExtractRoot := true;
end;

function BH_PeekRoot(Heap : PBinaryHeap) : void;
begin
  if Heap^.Count = 0 then
    BH_PeekRoot := nil
  else
    BH_PeekRoot := BH_DataPtr(Heap, 0);
end;

procedure BH_Free(Heap : PBinaryHeap);
begin
  if Heap = nil then exit;
  kfree(Heap^.Data);
  kfree(Heap^.Indices);
  kfree(Heap^.FreeSlots);
  kfree(void(Heap));
end;

end.
