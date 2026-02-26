//
//  lists.pas
//
//  Copyright 2021 Kieron Morris
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
//
//  @author  (Kieron Morris <kjm@kieronmorris.me>)
//  @author  (Aaron Hance  <ah@aaronhance.me>)
unit lists;

interface

uses
    console,
    lmemorymanager,
    tracer,
    util;

type
  {**
    @abstract Pointer to a managed linked list node.
  **}
  PLinkedList = ^TLinkedList;

  {**
    @abstract Managed linked list node record.
    @field Previous Pointer to the previous node.
    @field Data     Pointer to the stored data.
    @field Next     Pointer to the next node.
  **}
  TLinkedList = record
    Previous : PLinkedList;
    Data     : void;
    Next     : PLinkedList;
  end;

  {**
    @abstract Pointer to the base of a managed linked list.
  **}
  PLinkedListBase = ^TLinkedListBase;

  {**
    @abstract Base record for a managed linked list.
    @field Count       Number of elements in the list.
    @field Head        Pointer to the first node.
    @field ElementSize Size (in bytes) of each element.
  **}
  TLinkedListBase = record
    Count       : uint32;
    Head        : PLinkedList;
    ElementSize : uint32;
  end;

  {**
    @abstract Pointer to a dynamic list.
  **}
  PDList = ^TDList;

  {**
    @abstract Record for a dynamic list.
    @field Count       Number of elements in use.
    @field Data        Pointer to the underlying buffer.
    @field ElementSize Size (in bytes) of each element.
    @field DataSize    Total allocated bytes for Data.
  **}
  TDList = record
    Count       : uint32;  // number of elements in use
    Data        : void;    // pointer to the underlying buffer
    ElementSize : uint32;  // size of each element in bytes
    DataSize    : uint32;  // total allocated bytes for Data
  end;
  
  { Function/Procedure definitions }

  // ******************* String Linked List Routines *******************

  {**
    @abstract Adds a string to a string linked list.
    @param LinkedList Pointer to the linked list.
    @param str        Pointer to the null-terminated string to add.
  **}
  procedure STRLL_Add(LinkedList : PLinkedListBase; str : pchar);

  {**
    @abstract Retrieves a string at the given index from a string linked list.
    @param LinkedList Pointer to the linked list.
    @param idx        Zero-based index of the string.
    @returns Pointer to the string, or nil if not found.
  **}
  function STRLL_Get(LinkedList : PLinkedListBase; idx : uint32) : pchar;

  {**
    @abstract Creates a new string linked list.
    @returns Pointer to the newly created linked list.
  **}
  function STRLL_New : PLinkedListBase;

  {**
    @abstract Returns the number of elements in the string linked list.
    @param LinkedList Pointer to the linked list.
    @returns The count of elements.
  **}
  function STRLL_Size(LinkedList : PLinkedListBase) : uint32;

  {**
    @abstract Deletes the string at the specified index from the string linked list.
    @param LinkedList Pointer to the linked list.
    @param idx        Index of the string to delete.
  **}
  procedure STRLL_Delete(LinkedList : PLinkedListBase; idx : uint32);

  {**
    @abstract Frees the entire string linked list.
    @param LinkedList Pointer to the linked list.
  **}
  procedure STRLL_Free(LinkedList : PLinkedListBase);

  {**
    @abstract Clears all elements from the string linked list.
    @param LinkedList Pointer to the linked list.
  **}
  procedure STRLL_Clear(LinkedList : PLinkedListBase);

  {**
    @abstract Creates a string linked list by splitting a string.
    @param str      The source string.
    @param delimter The delimiter character.
    @returns A pointer to the resulting linked list.
  **}
  function STRLL_FromString(str : pchar; delimter : char) : PLinkedListBase;

  // ******************* Managed Linked List Routines *******************

  {**
    @abstract Creates a new managed linked list.
    @param ElementSize The size (in bytes) of each element.
    @returns A pointer to the newly created linked list base.
  **}
  function LL_New(ElementSize : uint32) : PLinkedListBase;

  {**
    @abstract Adds a new element to the managed linked list.
    @param LinkedList Pointer to the linked list.
    @returns Pointer to the newly allocated data space.
  **}
  function LL_Add(LinkedList : PLinkedListBase) : Void;

  {**
    @abstract Deletes the element at the specified index from the linked list.
    @param LinkedList Pointer to the linked list.
    @param idx        Zero-based index of the element to delete.
    @returns True if deletion was successful, false otherwise.
  **}
  function LL_Delete(LinkedList : PLinkedListBase; idx : uint32) : boolean;

  {**
    @abstract Retrieves the count of elements in the linked list.
    @param LinkedList Pointer to the linked list.
    @returns The number of elements.
  **}
  function LL_Size(LinkedList : PLinkedListBase) : uint32;

  {**
    @abstract Inserts a new element at the specified index in the linked list.
    @param LinkedList Pointer to the linked list.
    @param idx        Zero-based index where the element should be inserted.
    @returns Pointer to the newly allocated data space, or nil if insertion failed.
  **}
  function LL_Insert(LinkedList : PLinkedListBase; idx : uint32) : Void;

  {**
    @abstract Retrieves the element data at the specified index.
    @param LinkedList Pointer to the linked list.
    @param idx        Zero-based index of the element.
    @returns Pointer to the element data, or nil if index is out of range.
  **}
  function LL_Get(LinkedList : PLinkedListBase; idx : uint32) : Void;

  {**
    @abstract Frees the entire managed linked list.
    @param LinkedList Pointer to the linked list.
  **}
  procedure LL_Free(LinkedList : PLinkedListBase);

  {**
    @abstract Creates a managed linked list by splitting a string using a delimiter.
    @param str      The source string.
    @param delimter The delimiter character.
    @returns A pointer to the resulting linked list.
  **}
  function LL_FromString(str : pchar; delimter : char) : PLinkedListBase;

  // ******************* Dynamic List Routines *******************

  {**
    @abstract Creates a new dynamic list.
    @param ElementSize The size (in bytes) of each element.
    @returns Pointer to the newly created dynamic list.
  **}
  function DL_New(ElementSize : uint32) : PDList;

  {**
    @abstract Adds a new element to the dynamic list.
    @param DList Pointer to the dynamic list.
    @returns Pointer to the newly allocated slot.
    @discussion The routine automatically resizes the underlying buffer if necessary.
  **}
  function DL_Add(DList : PDList) : Void;

  {**
    @abstract Deletes the element at the specified index from the dynamic list.
    @param DList Pointer to the dynamic list.
    @param idx   Zero-based index of the element to delete.
    @returns True if deletion was successful, false otherwise.
    @discussion Subsequent elements are shifted left and the buffer may be shrunk.
  **}
  function DL_Delete(DList : PDList; idx : uint32) : boolean;

  {**
    @abstract Retrieves the element data at the specified index from the dynamic list.
    @param DList Pointer to the dynamic list.
    @param idx   Zero-based index of the element.
    @returns Pointer to the element data, or nil if index is out of range.
  **}
  function DL_Get(DList : PDList; idx : uint32) : Void;

  {**
    @abstract Sets the element at the specified index by copying from the provided data.
    @param DList Pointer to the dynamic list.
    @param idx   Zero-based index where the data should be copied.
    @param elm   Pointer to the source data.
    @returns True if the set operation was successful, false otherwise.
  **}
  function DL_Set(DList : PDList; idx : uint32; elm : puint32) : boolean;

  {**
    @abstract Retrieves the count of elements currently in the dynamic list.
    @param DList Pointer to the dynamic list.
    @returns The number of elements.
  **}
  function DL_Size(DList : PDList) : uint32;

  {**
    @abstract Frees the entire dynamic list and its underlying buffer.
    @param DList Pointer to the dynamic list.
  **}
  procedure DL_Free(DList : PDList);

  {**
    @abstract Searches for the given element in the dynamic list.
    @param DList Pointer to the dynamic list.
    @param elm   Pointer to the element to search for.
    @returns The index of the element if found; otherwise, returns -1.
    @discussion Comparison is performed on pointer addresses.
  **}
  function DL_IndexOf(DList : PDList; elm : puint32) : uint32;

  {**
    @abstract Determines whether the dynamic list contains the specified element.
    @param DList Pointer to the dynamic list.
    @param elm   Pointer to the element to search for.
    @returns True if the element is found, false otherwise.
  **}
  function DL_Contains(DList : PDList; elm : puint32) : boolean;

  {**
    @abstract Concatenates two dynamic lists.
    @param DList1 Pointer to the destination dynamic list.
    @param DList2 Pointer to the source dynamic list.
    @returns Pointer to the concatenated dynamic list (same as DList1), or nil if element sizes differ.
  **}
  function DL_Concat(DList1 : PDList; DList2 : PDList) : PDList;

  {**
    @abstract Clears the dynamic list by setting the count to zero.
    @param DList Pointer to the dynamic list.
    @discussion The underlying buffer is not shrunk to allow fast reuse.
  **}
  procedure DL_Clear(DList : PDList);

  {**
    @abstract Inserts a new element at the specified index in the dynamic list.
    @param DList Pointer to the dynamic list.
    @param idx   Zero-based index where the new element should be inserted.
    @returns Pointer to the newly allocated slot, or nil if index is out of range.
    @discussion Subsequent elements are shifted right.
  **}
  function DL_Insert(DList : PDList; idx : uint32) : Void;

  {**
    @abstract Returns the current capacity of the dynamic list.
    @param DList Pointer to the dynamic list.
    @returns The maximum number of elements that can be stored without reallocation.
  **}
  function DL_Capacity(DList : PDList) : uint32;

  {**
    @abstract Ensures the dynamic list has enough allocated space for at least NewCapacity elements.
    @param DList       Pointer to the dynamic list.
    @param NewCapacity The desired capacity (number of elements).
  **}
  procedure DL_Reserve(DList : PDList; NewCapacity : uint32);

  {**
    @abstract Shrinks the allocated memory to exactly fit the current number of elements.
    @param DList Pointer to the dynamic list.
  **}
  procedure DL_ShrinkToFit(DList : PDList);

  procedure TestAllLists();

implementation

uses
    strings;

{ ---------------------------------------------------------------------------- }
{                           Managed Linked List                                }
{ ---------------------------------------------------------------------------- }

{**
  @abstract Creates a new managed linked list.
  @param ElementSize The size (in bytes) of each element.
  @returns A pointer to the newly created linked list base.
**}
function LL_New(ElementSize : uint32) : PLinkedListBase;
begin
  LL_New := PLinkedListBase(kalloc(sizeof(TLinkedListBase)));
  LL_New^.ElementSize := ElementSize;
  LL_New^.Count := 0;
  LL_New^.Head := nil;
end;

{**
  @abstract Adds a new element to the managed linked list.
  @param LinkedList Pointer to the linked list.
  @returns Pointer to the newly allocated data space.
**}
function LL_Add(LinkedList : PLinkedListBase) : Void;
var
  Element : PLinkedList;
  Base    : PLinkedList;
begin
  if LinkedList^.Head = nil then
  begin
    Element := PLinkedList(kalloc(sizeof(TLinkedList)));
    Element^.Previous := nil;
    Element^.Next := nil;
    Element^.Data := kalloc(LinkedList^.ElementSize);
    memset(uint32(Element^.Data), 0, LinkedList^.ElementSize);

    LinkedList^.Head := Element;
    LinkedList^.Count := 1;
    LL_Add := Element^.Data;
  end
  else
  begin
    Base := LinkedList^.Head;
    while Base^.Next <> nil do
      Base := Base^.Next;

    Element := PLinkedList(kalloc(sizeof(TLinkedList)));
    Element^.Previous := Base;
    Element^.Next := nil;
    Element^.Data := kalloc(LinkedList^.ElementSize);
    memset(uint32(Element^.Data), 0, LinkedList^.ElementSize);

    Base^.Next := Element;
    LinkedList^.Count := LinkedList^.Count + 1;
    LL_Add := Element^.Data;
  end;
end;

{**
  @abstract Deletes the element at the specified index from the linked list.
  @param LinkedList Pointer to the linked list.
  @param idx        Zero-based index of the element to delete.
  @returns True if deletion was successful, false otherwise.
**}
function LL_Delete(LinkedList : PLinkedListBase; idx : uint32) : boolean;
var
  Base : PLinkedList;
  i    : uint32;
  Prev, Next : PLinkedList;
begin
  Base := LinkedList^.Head;
  i := 0;
  while (i < idx) and (Base <> nil) do
  begin
    Base := Base^.Next;
    Inc(i);
  end;

  if Base = nil then
  begin
    LL_Delete := false;
    exit;
  end;

  Prev := Base^.Previous;
  Next := Base^.Next;

  if Prev = nil then
    LinkedList^.Head := Next
  else
    Prev^.Next := Next;

  if Next <> nil then
    Next^.Previous := Prev;

  LinkedList^.Count := LinkedList^.Count - 1;
  kfree(void(Base^.Data));
  kfree(void(Base));
  LL_Delete := true;
end;

{**
  @abstract Retrieves the number of elements in the linked list.
  @param LinkedList Pointer to the linked list.
  @returns The element count.
**}
function LL_Size(LinkedList : PLinkedListBase) : uint32;
begin
  LL_Size := LinkedList^.Count;
end;

{**
  @abstract Inserts a new element at the specified index in the linked list.
  @param LinkedList Pointer to the linked list.
  @param idx        Zero-based index where the element is to be inserted.
  @returns Pointer to the newly allocated data space, or nil if insertion failed.
**}
function LL_Insert(LinkedList : PLinkedListBase; idx : uint32) : void;
var
  i : uint32;
  Base : PLinkedList;
  Prev, Next : PLinkedList;
  Element : PLinkedList;
begin
  LL_Insert := nil;
  if idx > LinkedList^.Count then
    Exit;

  Base := LinkedList^.Head;
  i := 0;
  while (i < idx) and (Base <> nil) do
  begin
    Base := Base^.Next;
    Inc(i);
  end;

  // Insert at head
  if i = 0 then
  begin
    Element := PLinkedList(kalloc(sizeof(TLinkedList)));
    Element^.Data := kalloc(LinkedList^.ElementSize);
    memset(uint32(Element^.Data), 0, LinkedList^.ElementSize);
    Element^.Next := LinkedList^.Head;
    Element^.Previous := nil;
    if LinkedList^.Head <> nil then
      LinkedList^.Head^.Previous := Element;
    LinkedList^.Head := Element;
    LinkedList^.Count := LinkedList^.Count + 1;
    LL_Insert := Element^.Data;
  end
  else
  begin
    // Insert in the middle or end
    if Base = nil then
      Exit;
    Prev := Base^.Previous;
    Next := Base;

    Element := PLinkedList(kalloc(sizeof(TLinkedList)));
    Element^.Data := kalloc(LinkedList^.ElementSize);
    memset(uint32(Element^.Data), 0, LinkedList^.ElementSize);

    Element^.Previous := Prev;
    Element^.Next := Next;

    if Prev = nil then
      LinkedList^.Head := Element
    else
      Prev^.Next := Element;

    if Next <> nil then
      Next^.Previous := Element;

    LinkedList^.Count := LinkedList^.Count + 1;
    LL_Insert := Element^.Data;
  end;
end;

{**
  @abstract Retrieves the element data at the specified index.
  @param LinkedList Pointer to the linked list.
  @param idx        Zero-based index of the desired element.
  @returns Pointer to the element data, or nil if index is out of range.
**}
function LL_Get(LinkedList : PLinkedListBase; idx : uint32) : void;
var
  i : uint32;
  Base : PLinkedList;
begin
  LL_Get := nil;
  if idx >= LinkedList^.Count then
    exit;

  Base := LinkedList^.Head;
  i := 0;
  while (i < idx) and (Base <> nil) do
  begin
    Base := Base^.Next;
    Inc(i);
  end;

  if Base <> nil then
    LL_Get := Base^.Data;
end;

{**
  @abstract Frees the entire managed linked list.
  @param LinkedList Pointer to the linked list.
  @discussion All nodes are deleted and their memory freed.
**}
procedure LL_Free(LinkedList : PLinkedListBase);
begin
  while LL_Size(LinkedList) > 0 do
    LL_Delete(LinkedList, 0);
  kfree(void(LinkedList));
end;

{**
  @abstract Creates a managed linked list by splitting a string using a delimiter.
  @param str      The source string.
  @param delimter The delimiter character.
  @returns Pointer to the resulting linked list.
**}
function LL_FromString(str : pchar; delimter : char) : PLinkedListBase;
var
  list       : PLinkedListBase;
  head, tail : pchar;
  size       : uint32;
  null_delim : boolean;
  elm        : puint32;
  out_str    : pchar;
begin
  list := LL_New(sizeof(uint32));
  LL_FromString := list;

  head := str;
  tail := head;
  null_delim := false;

  while not null_delim do
  begin
    if (head^ = delimter) or (head^ = char(0)) then
    begin
      if head^ = char(0) then
        null_delim := true;
      size := uint32(head) - uint32(tail);
      if size > 0 then
      begin
        elm := puint32(LL_Add(list));
        out_str := stringNew(size + 1);
        // Copy from tail -> out_str
        memcpy(uint32(tail), uint32(out_str), size);
        elm^ := uint32(out_str);
      end;
      tail := head + 1;
    end;
    Inc(head);
  end;
end;

{ ---------------------------------------------------------------------------- }
{                          String Linked List                                  }
{ ---------------------------------------------------------------------------- }

{**
  @abstract Adds a string to the string linked list.
  @param LinkedList Pointer to the linked list.
  @param str        Pointer to the null-terminated string.
**}
procedure STRLL_Add(LinkedList : PLinkedListBase; str : pchar);
var
  ptr : puint32;
begin
  ptr := puint32(LL_Add(LinkedList));
  ptr^ := uint32(str);
end;

{**
  @abstract Retrieves a string from the string linked list at the specified index.
  @param LinkedList Pointer to the linked list.
  @param idx        Zero-based index.
  @returns Pointer to the string, or nil if index is out of range.
**}
function STRLL_Get(LinkedList : PLinkedListBase; idx : uint32) : pchar;
var
  ptr : puint32;
begin
  ptr := puint32(LL_Get(LinkedList, idx));
  STRLL_Get := nil;
  if ptr <> nil then
    STRLL_Get := pchar(ptr^);
end;

{**
  @abstract Creates a new string linked list.
  @returns Pointer to the newly created list.
**}
function STRLL_New : PLinkedListBase;
begin
  STRLL_New := LL_New(sizeof(uint32));
end;

{**
  @abstract Returns the count of strings in the string linked list.
  @param LinkedList Pointer to the linked list.
  @returns The number of elements.
**}
function STRLL_Size(LinkedList : PLinkedListBase) : uint32;
begin
  STRLL_Size := LL_Size(LinkedList);
end;

{**
  @abstract Deletes a string from the string linked list at the specified index.
  @param LinkedList Pointer to the linked list.
  @param idx        Zero-based index of the string to delete.
  @discussion Frees the string memory before deleting the node.
**}
procedure STRLL_Delete(LinkedList : PLinkedListBase; idx : uint32);
var
  ptr : pchar;
begin
  tracer.push_trace('lists.STRLL_Delete (Don''t add static strings)');
  ptr := STRLL_Get(LinkedList, idx);
  if ptr <> nil then
    kfree(void(ptr));
  LL_Delete(LinkedList, idx);
end;

{**
  @abstract Frees the entire string linked list.
  @param LinkedList Pointer to the linked list.
  @discussion Clears all elements before freeing the list structure.
**}
procedure STRLL_Free(LinkedList : PLinkedListBase);
begin
  STRLL_Clear(LinkedList);
  LL_Free(LinkedList);
end;

{**
  @abstract Clears all elements from the string linked list.
  @param LinkedList Pointer to the linked list.
  @discussion Each string is deleted in turn.
**}
procedure STRLL_Clear(LinkedList : PLinkedListBase);
begin
  while STRLL_Size(LinkedList) > 0 do
    STRLL_Delete(LinkedList, 0);
end;

{**
  @abstract Creates a string linked list by splitting a string.
  @param str      The source string.
  @param delimter The delimiter character.
  @returns Pointer to the newly created list.
**}
function STRLL_FromString(str : pchar; delimter : char) : PLinkedListBase;
var
  list       : PLinkedListBase;
  head, tail : pchar;
  size       : uint32;
  null_delim : boolean;
  elm        : puint32;
  out_str    : pchar;
begin
  list := LL_New(sizeof(uint32));
  STRLL_FromString := list;

  head := str;
  tail := head;
  null_delim := false;

  while not null_delim do
  begin
    if (head^ = delimter) or (head^ = char(0)) then
    begin
      if head^ = char(0) then
        null_delim := true;
      size := uint32(head) - uint32(tail);
      if size > 0 then
      begin
        elm := puint32(LL_Add(list));
        out_str := stringNew(size + 1);
        memcpy(uint32(tail), uint32(out_str), size);
        elm^ := uint32(out_str);
      end;
      tail := head + 1;
    end;
    Inc(head);
  end;
end;

{ ---------------------------------------------------------------------------- }
{                              Dynamic List                                    }
{ ---------------------------------------------------------------------------- }

{**
  @abstract Creates a new dynamic list.
  @param ElementSize The size (in bytes) of each element.
  @returns Pointer to the newly allocated dynamic list.
**}
function DL_New(ElementSize : uint32) : PDList;
var
  DL : PDList;
  initialBytes : uint32;
begin
  DL := PDList(kalloc(sizeof(TDList)));
  DL^.ElementSize := ElementSize;
  DL^.Count := 0;

  // Pick an initial capacity based on the element size
  if ElementSize > 128 then
    initialBytes := ElementSize * 4
  else if ElementSize > 64 then
    initialBytes := ElementSize * 8
  else if ElementSize > 32 then
    initialBytes := ElementSize * 16
  else if ElementSize > 16 then
    initialBytes := ElementSize * 32
  else
    initialBytes := ElementSize * 64;

  DL^.Data := kalloc(initialBytes);
  DL^.DataSize := initialBytes;

  DL_New := DL;
end;

{**
  @abstract Adds a new element to the dynamic list.
  @param DList Pointer to the dynamic list.
  @returns Pointer to the newly allocated slot.
  @discussion Resizes the underlying buffer (doubling its size) if necessary.
**}
function DL_Add(DList : PDList) : Void;
var
  newElem : pointer;
  oldData : pointer;
  oldSize : uint32;
begin
  // Check if we need to resize
  if ((DList^.Count + 1) * DList^.ElementSize) > DList^.DataSize then
  begin
    push_trace('lists.DL_Add: Resizing');
    oldData := DList^.Data;
    oldSize := DList^.DataSize;

    DList^.DataSize := DList^.DataSize * 2;
    DList^.Data := kalloc(DList^.DataSize);
    memset(uint32(DList^.Data), 0, DList^.DataSize);

    // Copy old data into the new buffer
    memcpy(uint32(oldData), uint32(DList^.Data), oldSize);

    kfree(oldData);
  end;

  // Address of the new element
  newElem := pointer(uint32(DList^.Data) + (DList^.Count * DList^.ElementSize));
  // Zero out the newly added slot
  memset(uint32(newElem), 0, DList^.ElementSize);

  DList^.Count := DList^.Count + 1;
  DL_Add := newElem;
end;

{**
  @abstract Deletes the element at the specified index from the dynamic list.
  @param DList Pointer to the dynamic list.
  @param idx   Zero-based index of the element to delete.
  @returns True if deletion was successful, false otherwise.
  @discussion Shifts subsequent elements left and shrinks the buffer if underutilized.
**}
function DL_Delete(DList : PDList; idx : uint32) : boolean;
var
  sourcePtr, destPtr : pointer;
  shiftSize          : uint32;
  oldData            : pointer;
  oldSize            : uint32;
begin
  if (idx >= DList^.Count) then
  begin
    DL_Delete := false;
    exit;
  end;

  // If not removing the last element, shift the tail left by one element.
  if idx < (DList^.Count - 1) then
  begin
    sourcePtr := pointer(uint32(DList^.Data) + ((idx + 1) * DList^.ElementSize));
    destPtr   := pointer(uint32(DList^.Data) + (idx * DList^.ElementSize));
    shiftSize := (DList^.Count - idx - 1) * DList^.ElementSize;
    memcpy(uint32(sourcePtr), uint32(destPtr), shiftSize);
  end;

  // Decrement element count
  DList^.Count := DList^.Count - 1;

  // Possibly shrink the buffer if usage is very low
  if (DList^.Count > 0) and ((DList^.Count * DList^.ElementSize) < (DList^.DataSize div 2)) then
  begin
    oldData := DList^.Data;
    oldSize := DList^.DataSize;

    DList^.DataSize := DList^.DataSize div 2;
    if DList^.DataSize < (DList^.Count * DList^.ElementSize) then
      DList^.DataSize := (DList^.Count * DList^.ElementSize);

    DList^.Data := kalloc(DList^.DataSize);
    memset(uint32(DList^.Data), 0, DList^.DataSize);

    memcpy(uint32(oldData), uint32(DList^.Data), (DList^.Count * DList^.ElementSize));
    kfree(oldData);
  end;

  DL_Delete := true;
end;

{**
  @abstract Retrieves the element data at the specified index in the dynamic list.
  @param DList Pointer to the dynamic list.
  @param idx   Zero-based index of the desired element.
  @returns Pointer to the element data, or nil if index is out of range.
**}
function DL_Get(DList : PDList; idx : uint32) : Void;
begin
  if (idx >= DList^.Count) then
  begin
    DL_Get := nil;
    exit;
  end;

  DL_Get := pointer(uint32(DList^.Data) + (idx * DList^.ElementSize));
end;

{**
  @abstract Sets the element at the specified index by copying data from the provided pointer.
  @param DList Pointer to the dynamic list.
  @param idx   Zero-based index of the element to set.
  @param elm   Pointer to the source data.
  @returns True if the operation was successful, false otherwise.
**}
function DL_Set(DList : PDList; idx : uint32; elm : puint32) : boolean;
var
  targetPtr : pointer;
begin
  if (idx >= DList^.Count) then
  begin
    DL_Set := false;
    exit;
  end;

  // Copy the data from elm into the dynamic list
  targetPtr := pointer(uint32(DList^.Data) + (idx * DList^.ElementSize));
  memcpy(uint32(elm), uint32(targetPtr), DList^.ElementSize);

  DL_Set := true;
end;

{**
  @abstract Returns the number of elements currently in the dynamic list.
  @param DList Pointer to the dynamic list.
  @returns The element count.
**}
function DL_Size(DList : PDList) : uint32;
begin
  DL_Size := DList^.Count;
end;

{**
  @abstract Frees the entire dynamic list and its underlying buffer.
  @param DList Pointer to the dynamic list.
**}
procedure DL_Free(DList : PDList);
begin
  if DList = nil then exit;
  if DList^.Data <> nil then
    kfree(DList^.Data);
  kfree(void(DList));
end;

{**
  @abstract Searches for an element in the dynamic list.
  @param DList Pointer to the dynamic list.
  @param elm   Pointer to the element to find.
  @returns The zero-based index of the element if found; otherwise, returns -1.
  @discussion The search is based on pointer equality.
**}
function DL_IndexOf(DList : PDList; elm : puint32) : uint32;
var
  i     : uint32;
  temp  : puint32;
begin
  for i := 0 to DList^.Count - 1 do
  begin
    temp := puint32(uint32(DList^.Data) + (i * DList^.ElementSize));
    if (temp = elm) then
    begin
      DL_IndexOf := i;
      exit;
    end;
  end;
  DL_IndexOf := uint32(-1);
end;

{**
  @abstract Determines whether the dynamic list contains the specified element.
  @param DList Pointer to the dynamic list.
  @param elm   Pointer to the element to search for.
  @returns True if the element is present, false otherwise.
**}
function DL_Contains(DList : PDList; elm : puint32) : boolean;
begin
  DL_Contains := (DL_IndexOf(DList, elm) <> uint32(-1));
end;

{**
  @abstract Concatenates two dynamic lists.
  @param DList1 Pointer to the destination dynamic list.
  @param DList2 Pointer to the source dynamic list.
  @returns Pointer to the concatenated dynamic list (DList1), or nil if element sizes differ.
**}
function DL_Concat(DList1 : PDList; DList2 : PDList) : PDList;
var
  i   : uint32;
  ptr : pointer;
begin
  if DList1^.ElementSize <> DList2^.ElementSize then
  begin
    DL_Concat := nil;
    exit;
  end;

  for i := 0 to DList2^.Count - 1 do
  begin
    ptr := DL_Add(DList1);
    memcpy(uint32(DL_Get(DList2, i)), uint32(ptr), DList1^.ElementSize);
  end;

  DL_Concat := DList1;
end;

{**
  @abstract Clears the dynamic list by resetting the count to zero.
  @param DList Pointer to the dynamic list.
  @discussion The underlying buffer is retained for fast reuse.
**}
procedure DL_Clear(DList : PDList);
begin
  if (DList = nil) then exit;
  DList^.Count := 0;
  // To clear memory, uncomment the following line:
  // memset(uint32(DList^.Data), 0, DList^.DataSize);
end;

{**
  @abstract Inserts a new element at the specified index in the dynamic list.
  @param DList Pointer to the dynamic list.
  @param idx   Zero-based index where the element should be inserted.
  @returns Pointer to the newly allocated slot, or nil if idx is out of range.
  @discussion Subsequent elements are shifted right. The buffer is resized if needed.
**}
function DL_Insert(DList : PDList; idx : uint32) : Void;
var
  newElem   : pointer;
  oldData   : pointer;
  oldSize   : uint32;
  shiftSrc  : pointer;
  shiftDest : pointer;
  shiftSize : uint32;
begin
  DL_Insert := nil;
  if (DList = nil) then exit;
  if (idx > DList^.Count) then
    exit;  // cannot insert beyond the current count

  // Ensure there's space for one more element
  if ((DList^.Count + 1) * DList^.ElementSize) > DList^.DataSize then
  begin
    oldData := DList^.Data;
    oldSize := DList^.DataSize;

    DList^.DataSize := DList^.DataSize * 2;
    DList^.Data := kalloc(DList^.DataSize);
    memset(uint32(DList^.Data), 0, DList^.DataSize);

    memcpy(uint32(oldData), uint32(DList^.Data), oldSize);
    kfree(oldData);
  end;

  // Shift elements to the right if inserting in the middle
  if (idx < DList^.Count) then
  begin
    shiftSrc  := pointer(uint32(DList^.Data) + (idx * DList^.ElementSize));
    shiftDest := pointer(uint32(DList^.Data) + ((idx + 1) * DList^.ElementSize));
    shiftSize := (DList^.Count - idx) * DList^.ElementSize;
    // Shift overlapping regions; if memcpy doesn't handle overlap, use memmove.
    memcpy(uint32(shiftSrc), uint32(shiftDest), shiftSize);
  end;

  // Allocate the new element slot
  newElem := pointer(uint32(DList^.Data) + (idx * DList^.ElementSize));
  memset(uint32(newElem), 0, DList^.ElementSize);

  DList^.Count := DList^.Count + 1;
  DL_Insert := newElem;
end;

{**
  @abstract Returns the current capacity (number of elements) that the dynamic list can hold.
  @param DList Pointer to the dynamic list.
  @returns The capacity based on the allocated buffer size.
**}
function DL_Capacity(DList : PDList) : uint32;
begin
  if DList = nil then
    DL_Capacity := 0
  else
    DL_Capacity := (DList^.DataSize div DList^.ElementSize);
end;

{**
  @abstract Ensures the dynamic list has enough space for at least NewCapacity elements.
  @param DList       Pointer to the dynamic list.
  @param NewCapacity Desired capacity (in number of elements).
  @discussion Reallocates the buffer if necessary.
**}
procedure DL_Reserve(DList : PDList; NewCapacity : uint32);
var
  neededBytes : uint32;
  oldData     : pointer;
  oldSize     : uint32;
begin
  if (DList = nil) then exit;

  neededBytes := NewCapacity * DList^.ElementSize;
  if (neededBytes <= DList^.DataSize) then
    exit; // Already sufficient

  oldData := DList^.Data;
  oldSize := DList^.DataSize;

  DList^.DataSize := neededBytes;
  DList^.Data := kalloc(DList^.DataSize);

  memset(uint32(DList^.Data), 0, DList^.DataSize);
  memcpy(uint32(oldData), uint32(DList^.Data), oldSize);

  kfree(oldData);
end;

{**
  @abstract Shrinks the dynamic list's allocated memory to fit its current count.
  @param DList Pointer to the dynamic list.
  @discussion If the list is empty, the buffer is freed.
**}
procedure DL_ShrinkToFit(DList : PDList);
var
  exactBytes : uint32;
  oldData    : pointer;
begin
  if (DList = nil) then exit;
  exactBytes := DList^.Count * DList^.ElementSize;
  if (exactBytes = 0) then
  begin
    // For an empty list, free the buffer and reset values.
    kfree(DList^.Data);
    DList^.Data := nil;
    DList^.DataSize := 0;
    exit;
  end;

  if exactBytes >= DList^.DataSize then exit; // Already optimal

  oldData := DList^.Data;
  DList^.Data := kalloc(exactBytes);

  memcpy(uint32(oldData), uint32(DList^.Data), exactBytes);
  kfree(oldData);
  DList^.DataSize := exactBytes;
end;

procedure TestAllLists;
var
  i      : uint32;
  p      : pointer;
  ll     : PLinkedListBase;    // Managed linked list
  strList: PLinkedListBase;    // String linked list
  dlist  : PDList;             // Dynamic list
  intPtr : puint32;           // For dynamic list integer values
  testStr: pchar;
  testStr2: pchar;
begin
  { --- Test Managed Linked List --- }
  console.writeString('--- Testing Managed Linked List ---');
  ll := LL_New(sizeof(uint32));
  for i := 1 to 3 do
  begin
    p := LL_Add(ll);
    puint32(p)^ := i;  // Store the value (1, 2, 3)
  end;
  console.writeString('Managed Linked List Size: ');
  console.writeintln(LL_Size(ll));
  for i := 0 to LL_Size(ll) - 1 do
  begin
    p := LL_Get(ll, i);
    console.writeString('Element ');
    console.writeint(i);
    console.writeString(': ');
    console.writeintln(puint32(p)^);
  end;
  LL_Free(ll);

  { --- Test String Linked List --- }
  console.writeString('');
  console.writeString('--- Testing String Linked List ---');
  testStr := stringNew(5);
  PuInt8(testStr)^ := ord('H');
  PuInt8(testStr + 1)^ := ord('e');
  PuInt8(testStr + 2)^ := ord('l');
  PuInt8(testStr + 3)^ := ord('l');
  PuInt8(testStr + 4)^ := ord('o');

  testStr2 := stringNew(5);
  puint8(testStr2)^ := ord('W');
  puint8(testStr2 + 1)^ := ord('o');
  puint8(testStr2 + 2)^ := ord('r');
  puint8(testStr2 + 3)^ := ord('l');
  puint8(testStr2 + 4)^ := ord('d');


  strList := STRLL_New;
  STRLL_Add(strList, testStr);
  STRLL_Add(strList, testStr2);
  console.writeString('String Linked List Size: ');
  console.writeintln(STRLL_Size(strList));
  for i := 0 to STRLL_Size(strList) - 1 do
  begin
    console.writeString('String ');
    console.writeint(i);
    console.writeString(': ');
    console.writeString(STRLL_Get(strList, i));
    
  end;
  STRLL_Free(strList);

  { --- Test Dynamic List --- }
  console.writeString('');
  console.writeString('--- Testing Dynamic List ---');
  dlist := DL_New(sizeof(uint32));
  for i := 1 to 5 do
  begin
    intPtr := DL_Add(dlist);
    intPtr^ := i * 10;  // Store values: 10, 20, 30, 40, 50
  end;
  console.writeString('Dynamic List Size: ');
  console.writeintln(DL_Size(dlist));
  for i := 0 to DL_Size(dlist) - 1 do
  begin
    intPtr := DL_Get(dlist, i);
    console.writeString('Element ');
    console.writeint(i);
    console.writeString(': ');
    console.writeintln(intPtr^);
  end;

  { Insert a new element at index 2 }
  intPtr := DL_Insert(dlist, 2);
  if intPtr <> nil then
    intPtr^ := 999;  // Inserted value 999 at index 2
  console.writeString('After insertion at index 2, size: ');
  console.writeintln(DL_Size(dlist));
  for i := 0 to DL_Size(dlist) - 1 do
  begin
    intPtr := DL_Get(dlist, i);
    console.writeString('Element ');
    console.writeint(i);
    console.writeString(': ');
    console.writeintln(intPtr^);
  end;

  { Delete element at index 3 }
  if DL_Delete(dlist, 3) then
    console.writeString('Deleted element at index 3.');
  console.writeString('After deletion, size: ');
  console.writeintln(DL_Size(dlist));
  for i := 0 to DL_Size(dlist) - 1 do
  begin
    intPtr := DL_Get(dlist, i);
    console.writeString('Element ');
    console.writeint(i);
    console.writeString(': ');
    console.writeintln(intPtr^);
  end;
  DL_Free(dlist);
end;


end.
