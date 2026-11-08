//
//  core.ds.lists.pas
//
//  Copyright 2021 Kieron Morris
//  Copyright 2026 Aaron Hance
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
unit core.ds.lists;

interface

uses
    core.ds.types, core.ds.dynamic,
    memory.heap,
    arch.platform.diagnostics,
    core.util;

type
  {**
    @abstract Pointer to a managed linked list node.
  **}
  PLinkedList = core.ds.types.PLinkedList;
  TLinkedList = core.ds.types.TLinkedList;
  PLinkedListBase = core.ds.types.PLinkedListBase;
  TLinkedListBase = core.ds.types.TLinkedListBase;

  {**
    @abstract Pointer to a dynamic list.
  **}
  PDList = core.ds.dynamic.PDList;
  TDList = core.ds.dynamic.TDList;

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
    core.strings;

type
    PStringSlot = ^pchar;

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
  if LL_New = nil then exit;
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
begin
    LL_Add := nil;
    if LinkedList <> nil then
        LL_Add := LL_Insert(LinkedList, LinkedList^.Count);
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
    i: uint32;
    next, prev, element: PLinkedList;
begin
    LL_Insert := nil;
    if LinkedList = nil then exit;
    if (idx > LinkedList^.Count) or (LinkedList^.Count = High(uint32)) then exit;

    prev := nil;
    next := LinkedList^.Head;
    for i := 1 to idx do begin
        prev := next;
        next := next^.Next;
    end;

    element := PLinkedList(kalloc(sizeof(TLinkedList)));
    if element = nil then exit;
    element^.Data := kalloc(LinkedList^.ElementSize);
    if element^.Data = nil then begin
        kfree(void(element));
        exit;
    end;
    element^.Previous := prev;
    element^.Next := next;
    if prev = nil then
        LinkedList^.Head := element
    else
        prev^.Next := element;
    if next <> nil then
        next^.Previous := element;
    inc(LinkedList^.Count);
    LL_Insert := element^.Data;
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
begin
    LL_FromString := STRLL_FromString(str, delimter);
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
  ptr : PStringSlot;
begin
  ptr := PStringSlot(LL_Add(LinkedList));
  if ptr <> nil then ptr^ := str;
end;

{**
  @abstract Retrieves a string from the string linked list at the specified index.
  @param LinkedList Pointer to the linked list.
  @param idx        Zero-based index.
  @returns Pointer to the string, or nil if index is out of range.
**}
function STRLL_Get(LinkedList : PLinkedListBase; idx : uint32) : pchar;
var
  ptr : PStringSlot;
begin
  ptr := PStringSlot(LL_Get(LinkedList, idx));
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
  STRLL_New := LL_New(sizeof(pchar));
end;

{**
  @abstract Returns the count of core.strings in the string linked list.
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
  arch.platform.diagnostics.push_trace('core.ds.lists.STRLL_Delete (Don''t add static core.strings)');
  ptr := STRLL_Get(LinkedList, idx);
  if ptr <> nil then
    kfree(void(ptr));
  LL_Delete(LinkedList, idx);
  pop_trace;
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
    list: PLinkedListBase;
    head, tail, text: pchar;
    size: SizeUInt;
    slot: PStringSlot;
begin
    STRLL_FromString := nil;
    if str = nil then exit;
    list := STRLL_New;
    if list = nil then exit;

    head := str;
    tail := str;
    repeat
        if (head^ = delimter) or (head^ = #0) then begin
            size := PtrUInt(head) - PtrUInt(tail);
            if size > 0 then begin
                if size >= High(uint32) then begin
                    STRLL_Free(list);
                    exit;
                end;
                text := stringNew(uint32(size));
                if text = nil then begin
                    STRLL_Free(list);
                    exit;
                end;
                slot := PStringSlot(LL_Add(list));
                if slot = nil then begin
                    kfree(void(text));
                    STRLL_Free(list);
                    exit;
                end;
                memcpy(PtrUInt(tail), PtrUInt(text), size);
                slot^ := text;
            end;
            tail := head + 1;
        end;
        if head^ = #0 then break;
        inc(head);
    until false;
    STRLL_FromString := list;
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
begin
    DL_New := core.ds.dynamic.DL_New(ElementSize);
end;

function DL_Add(DList : PDList) : Void;
begin
    DL_Add := core.ds.dynamic.DL_Add(DList);
end;

function DL_Delete(DList : PDList; idx : uint32) : boolean;
begin
    DL_Delete := core.ds.dynamic.DL_Delete(DList, idx);
end;

function DL_Get(DList : PDList; idx : uint32) : Void;
begin
    DL_Get := core.ds.dynamic.DL_Get(DList, idx);
end;

function DL_Set(DList : PDList; idx : uint32; elm : puint32) : boolean;
begin
    DL_Set := core.ds.dynamic.DL_Set(DList, idx, elm);
end;

function DL_Size(DList : PDList) : uint32;
begin
    DL_Size := core.ds.dynamic.DL_Size(DList);
end;

procedure DL_Free(DList : PDList);
begin
    core.ds.dynamic.DL_Free(DList);
end;

function DL_IndexOf(DList : PDList; elm : puint32) : uint32;
begin
    DL_IndexOf := core.ds.dynamic.DL_IndexOf(DList, elm);
end;

function DL_Contains(DList : PDList; elm : puint32) : boolean;
begin
    DL_Contains := core.ds.dynamic.DL_Contains(DList, elm);
end;

function DL_Concat(DList1 : PDList; DList2 : PDList) : PDList;
begin
    DL_Concat := core.ds.dynamic.DL_Concat(DList1, DList2);
end;

procedure DL_Clear(DList : PDList);
begin
    core.ds.dynamic.DL_Clear(DList);
end;

function DL_Insert(DList : PDList; idx : uint32) : Void;
begin
    DL_Insert := core.ds.dynamic.DL_Insert(DList, idx);
end;

function DL_Capacity(DList : PDList) : uint32;
begin
    DL_Capacity := core.ds.dynamic.DL_Capacity(DList);
end;

procedure DL_Reserve(DList : PDList; NewCapacity : uint32);
begin
    core.ds.dynamic.DL_Reserve(DList, NewCapacity);
end;

procedure DL_ShrinkToFit(DList : PDList);
begin
    core.ds.dynamic.DL_ShrinkToFit(DList);
end;

procedure TestAllLists;
var
    list: PLinkedListBase;
    slot: puint32;
    source: pchar;
    beforeFree: SizeUInt;
    passed, failed: uint32;

    procedure Assert(condition: boolean; name: pchar);
    begin
        if condition then
            inc(passed)
        else begin
            inc(failed);
            log('LISTS', name);
        end;
    end;
begin
    passed := 0;
    failed := 0;
    beforeFree := lmm_total_free;
    list := LL_New(sizeof(uint32));
    slot := puint32(LL_Add(list));
    slot^ := 10;
    slot := puint32(LL_Insert(list, 0));
    slot^ := 5;
    slot := puint32(LL_Insert(list, 2));
    slot^ := 20;
    Assert((LL_Size(list) = 3) and (puint32(LL_Get(list, 0))^ = 5) and
        (puint32(LL_Get(list, 2))^ = 20), 'FAIL: list head and tail insertion');
    Assert(LL_Delete(list, 1) and (puint32(LL_Get(list, 1))^ = 20),
        'FAIL: list middle deletion');
    Assert((LL_Get(list, 2) = nil) and (LL_Insert(list, 3) = nil),
        'FAIL: list bounds');
    LL_Free(list);

    source := stringCopy('/alpha//beta/');
    list := STRLL_FromString(source, '/');
    kfree(void(source));
    Assert((STRLL_Size(list) = 2) and StringEquals(STRLL_Get(list, 0), 'alpha') and
        StringEquals(STRLL_Get(list, 1), 'beta'), 'FAIL: native string list split');
    STRLL_Delete(list, 0);
    Assert(StringEquals(STRLL_Get(list, 0), 'beta'), 'FAIL: string list delete');
    STRLL_Free(list);
    list := LL_FromString('one:two', ':');
    Assert(StringEquals(STRLL_Get(list, 1), 'two'), 'FAIL: shared string splitter');
    STRLL_Free(list);
    list := STRLL_FromString('', '/');
    Assert(STRLL_Size(list) = 0, 'FAIL: empty string list');
    STRLL_Free(list);
    Assert(lmm_total_free = beforeFree, 'FAIL: list allocation accounting');
    testSummary('LISTS', 'LISTS_TESTS_PASSED', 'LISTS_TESTS_FAILED', passed, failed);
end;

end.
