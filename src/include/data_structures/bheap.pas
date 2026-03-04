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
	Binary Heap - Shared heap internals for min-heap, max-heap
	and priority queue. Uses index-array indirection for O(1) swaps
	with inline element storage and a free-slot recycling stack.

	@author(Aaron Hance <ah@aaronhance.me>)
}
unit bheap;

interface

uses
  dstypes,
  lmemorymanager,
  util;

  {** Creates a new BinaryHeap.
    @param ElementSize     Size (in bytes) of each data element.
    @param InitialCapacity Starting number of slots.
    @param MinHeap         True for min-heap ordering, false for max-heap.
    @returns Pointer to the new heap.
  **}
  function BHeap_New(ElementSize : uint32; InitialCapacity : uint32;
                  MinHeap : boolean) : PBinaryHeap;

  {** Inserts an element with the given priority into the heap. **}
  procedure BHeap_Insert(Heap : PBinaryHeap; Priority : uint32; Data : void);

  {** Extracts the root element from the heap. Copies data into OutData.
    @returns True if extracted, false if heap was empty.
  **}
  function BHeap_ExtractRoot(Heap : PBinaryHeap; OutData : void) : boolean;

  {** Peeks at the root element.
    @returns Pointer to root data, or nil if empty.
  **}
  function BHeap_PeekRoot(Heap : PBinaryHeap) : void;

  {** Frees the heap and its buffers. **}
  procedure BHeap_Free(Heap : PBinaryHeap);

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
function BHeap_IdxPtr(Heap : PBinaryHeap; i : uint32) : void; inline;
begin
  BHeap_IdxPtr := void(uint32(Heap^.Indices) + i * sizeof(uint32));
end;

{** Returns the data-slot index stored at heap position i. **}
function BHeap_IdxGet(Heap : PBinaryHeap; i : uint32) : uint32; inline;
begin
  BHeap_IdxGet := void(uint32(Heap^.Indices) + i * sizeof(uint32))^;
end;

{** Writes a data-slot index into heap position i. **}
procedure BHeap_IdxSet(Heap : PBinaryHeap; i : uint32; slot : uint32); inline;
begin
  void(uint32(Heap^.Indices) + i * sizeof(uint32))^ := slot;
end;

{ ---------------------------------------------------------------------------- }
{  Internal helpers — data-slot access (goes through Indices)                  }
{ ---------------------------------------------------------------------------- }

{** Returns pointer to the start of the data slot for heap position i. **}
function BHeap_SlotPtr(Heap : PBinaryHeap; i : uint32) : void; inline;
begin
  BHeap_SlotPtr := void(uint32(Heap^.Data) + BHeap_IdxGet(Heap, i) * Heap^.NodeStride);
end;

{** Returns the priority of the element at heap position i. **}
function BHeap_GetPri(Heap : PBinaryHeap; i : uint32) : uint32; inline;
begin
  BHeap_GetPri := void(uint32(Heap^.Data) + BHeap_IdxGet(Heap, i) * Heap^.NodeStride)^;
end;

{** Returns pointer to the inline element data at heap position i. **}
function BHeap_DataPtr(Heap : PBinaryHeap; i : uint32) : void; inline;
begin
  BHeap_DataPtr := void(uint32(Heap^.Data)
                     + BHeap_IdxGet(Heap, i) * Heap^.NodeStride
                     + sizeof(uint32));
end;

{ ---------------------------------------------------------------------------- }
{  Internal helpers — free-slot stack                                          }
{ ---------------------------------------------------------------------------- }

{** Pushes a freed data-slot index onto the free stack. **}
procedure BHeap_FreePush(Heap : PBinaryHeap; slot : uint32); inline;
begin
  void(uint32(Heap^.FreeSlots) + Heap^.FreeCount * sizeof(uint32))^ := slot;
  Heap^.FreeCount := Heap^.FreeCount + 1;
end;

{** Pops a data-slot index from the free stack. **}
function BHeap_FreePop(Heap : PBinaryHeap) : uint32; inline;
begin
  Heap^.FreeCount := Heap^.FreeCount - 1;
  BHeap_FreePop := void(uint32(Heap^.FreeSlots) + Heap^.FreeCount * sizeof(uint32))^;
end;

{ ---------------------------------------------------------------------------- }
{  Internal helpers — ordering                                                 }
{ ---------------------------------------------------------------------------- }

{** Returns true if heap position A should be above position B. **}
function BHeap_Compare(Heap : PBinaryHeap; A, B : uint32) : boolean; inline;
begin
  if Heap^.IsMinHeap then
    BHeap_Compare := BHeap_GetPri(Heap, A) <= BHeap_GetPri(Heap, B)
  else
    BHeap_Compare := BHeap_GetPri(Heap, A) >= BHeap_GetPri(Heap, B);
end;

{** Swaps two heap positions by exchanging their index entries. **}
procedure BHeap_Swap(Heap : PBinaryHeap; A, B : uint32); inline;
var
  tmp : uint32;
begin
  tmp := BHeap_IdxGet(Heap, A);
  BHeap_IdxSet(Heap, A, BHeap_IdxGet(Heap, B));
  BHeap_IdxSet(Heap, B, tmp);
end;

{** Restores heap property upward from position i. **}
procedure BHeap_SiftUp(Heap : PBinaryHeap; i : uint32);
var
  parent : uint32;
begin
  while i > 0 do
  begin
    parent := (i - 1) div 2;
    if BHeap_Compare(Heap, i, parent) then
    begin
      BHeap_Swap(Heap, i, parent);
      i := parent;
    end
    else
      break;
  end;
end;

{** Restores heap property downward from position i. **}
procedure BHeap_SiftDown(Heap : PBinaryHeap; i : uint32);
var
  best, left, right : uint32;
begin
  while true do
  begin
    best  := i;
    left  := 2 * i + 1;
    right := 2 * i + 2;

    if (left < Heap^.Count) and BHeap_Compare(Heap, left, best) then
      best := left;
    if (right < Heap^.Count) and BHeap_Compare(Heap, right, best) then
      best := right;

    if best = i then
      break;

    BHeap_Swap(Heap, i, best);
    i := best;
  end;
end;

{** Doubles all three arrays (Data, Indices, FreeSlots). **}
procedure BHeap_Grow(Heap : PBinaryHeap);
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

function BHeap_New(ElementSize : uint32; InitialCapacity : uint32;
                MinHeap : boolean) : PBinaryHeap;
var
  stride : uint32;
begin
  stride := sizeof(uint32) + ElementSize;

  BHeap_New := PBinaryHeap(kalloc(sizeof(TBinaryHeap)));
  BHeap_New^.Count       := 0;
  BHeap_New^.Capacity    := InitialCapacity;
  BHeap_New^.NextSlot    := 0;
  BHeap_New^.FreeCount   := 0;
  BHeap_New^.ElementSize := ElementSize;
  BHeap_New^.NodeStride  := stride;
  BHeap_New^.IsMinHeap   := MinHeap;
  BHeap_New^.Data        := kalloc(InitialCapacity * stride);
  BHeap_New^.Indices     := kalloc(InitialCapacity * sizeof(uint32));
  BHeap_New^.FreeSlots   := kalloc(InitialCapacity * sizeof(uint32));
  memset(uint32(BHeap_New^.Data), 0, InitialCapacity * stride);
end;

procedure BHeap_Insert(Heap : PBinaryHeap; Priority : uint32; Data : void);
var
  slot    : uint32;
  slotPtr : void;
begin
  if Heap^.Count >= Heap^.Capacity then
    BHeap_Grow(Heap);

  { Acquire a data slot — recycle freed slot or take next sequential }
  if Heap^.FreeCount > 0 then
    slot := BHeap_FreePop(Heap)
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
  BHeap_IdxSet(Heap, Heap^.Count, slot);

  Heap^.Count := Heap^.Count + 1;
  BHeap_SiftUp(Heap, Heap^.Count - 1);
end;

function BHeap_ExtractRoot(Heap : PBinaryHeap; OutData : void) : boolean;
var
  rootSlot : uint32;
begin
  BHeap_ExtractRoot := false;
  if Heap^.Count = 0 then
    exit;

  { Copy root element data to caller }
  memcpy(uint32(BHeap_DataPtr(Heap, 0)), uint32(OutData), Heap^.ElementSize);

  { Recycle the root's data slot }
  rootSlot := BHeap_IdxGet(Heap, 0);
  BHeap_FreePush(Heap, rootSlot);

  Heap^.Count := Heap^.Count - 1;
  if Heap^.Count > 0 then
  begin
    { Move last index into root position and restore heap order }
    BHeap_IdxSet(Heap, 0, BHeap_IdxGet(Heap, Heap^.Count));
    BHeap_SiftDown(Heap, 0);
  end;

  BHeap_ExtractRoot := true;
end;

function BHeap_PeekRoot(Heap : PBinaryHeap) : void;
begin
  if Heap^.Count = 0 then
    BHeap_PeekRoot := nil
  else
    BHeap_PeekRoot := BHeap_DataPtr(Heap, 0);
end;

procedure BHeap_Free(Heap : PBinaryHeap);
begin
  if Heap = nil then exit;
  kfree(Heap^.Data);
  kfree(Heap^.Indices);
  kfree(Heap^.FreeSlots);
  kfree(void(Heap));
end;

end.
