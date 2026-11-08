// Copyright 2026 Aaron Hance
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

{ Dynamic-list implementation shared with the legacy core.ds.lists API.
  Original interface: Kieron Morris. Capacity remains bounded to uint32 bytes;
  addresses are native-width. Operations require caller-owned synchronization. }
unit core.ds.dynamic;

interface
type
    PDList = ^TDList;
    TDList = record
        Count: uint32;
        Data: void;
        ElementSize, DataSize: uint32;
    end;

function DL_New(ElementSize : uint32) : PDList;
function DL_Add(DList : PDList) : Void;
function DL_Delete(DList : PDList; idx : uint32) : boolean;
function DL_Get(DList : PDList; idx : uint32) : Void;
function DL_Set(DList : PDList; idx : uint32; elm : puint32) : boolean;
function DL_Size(DList : PDList) : uint32;
procedure DL_Free(DList : PDList);
function DL_IndexOf(DList : PDList; elm : puint32) : uint32;
function DL_Contains(DList : PDList; elm : puint32) : boolean;
function DL_Concat(DList1 : PDList; DList2 : PDList) : PDList;
procedure DL_Clear(DList : PDList);
function DL_Insert(DList : PDList; idx : uint32) : Void;
function DL_Capacity(DList : PDList) : uint32;
procedure DL_Reserve(DList : PDList; NewCapacity : uint32);
procedure DL_ShrinkToFit(DList : PDList);

implementation
uses memory.heap, memory.raw;

function resize(list: PDList; bytes: uint32): boolean;
var
    data: void;
begin
    resize := false;
    if bytes < list^.Count * list^.ElementSize then exit;
    if bytes = list^.DataSize then begin
        resize := true;
        exit;
    end;
    data := nil;
    if bytes <> 0 then begin
        data := kalloc(bytes);
        if data = nil then exit;
        memory.raw.move(pointer(list^.Data), pointer(data), list^.Count * list^.ElementSize);
    end;
    kfree(list^.Data);
    list^.Data := data;
    list^.DataSize := bytes;
    resize := true;
end;

function ensure(list: PDList; count: uint32): boolean;
var
    bytes, capacity: uint32;
begin
    ensure := false;
    if (list = nil) or (list^.ElementSize = 0) then exit;
    if count > High(uint32) div list^.ElementSize then exit;
    bytes := count * list^.ElementSize;
    if bytes <= list^.DataSize then begin
        ensure := true;
        exit;
    end;
    capacity := list^.DataSize;
    if capacity <= High(uint32) div 2 then capacity := capacity * 2;
    if capacity < bytes then capacity := bytes;
    ensure := resize(list, capacity);
end;

function DL_New(ElementSize: uint32): PDList;
var
    list: PDList;
    count: uint32;
begin
    DL_New := nil;
    if (ElementSize = 0) or (ElementSize > High(uint32) div 4) then exit;
    list := PDList(kalloc(sizeof(TDList)));
    if list = nil then exit;
    list^.ElementSize := ElementSize;
    if ElementSize > 128 then count := 4 else
    if ElementSize > 64 then count := 8 else
    if ElementSize > 32 then count := 16 else
    if ElementSize > 16 then count := 32 else count := 64;
    if not ensure(list, count) then begin
        kfree(void(list));
        exit;
    end;
    DL_New := list;
end;

function DL_Insert(DList: PDList; idx: uint32): void;
var
    address: PtrUInt;
begin
    DL_Insert := nil;
    if DList = nil then exit;
    if (idx > DList^.Count) or (DList^.Count = High(uint32)) then exit;
    if not ensure(DList, DList^.Count + 1) then exit;
    address := PtrUInt(DList^.Data) + SizeUInt(idx) * DList^.ElementSize;
    memory.raw.move(pointer(address), pointer(address + DList^.ElementSize),
        (DList^.Count - idx) * DList^.ElementSize);
    memory.raw.fill(pointer(address), 0, DList^.ElementSize);
    inc(DList^.Count);
    DL_Insert := void(address);
end;

function DL_Add(DList: PDList): void;
begin
    DL_Add := nil;
    if DList <> nil then DL_Add := DL_Insert(DList, DList^.Count);
end;

function DL_Delete(DList: PDList; idx: uint32): boolean;
var
    address: PtrUInt;
begin
    DL_Delete := false;
    if DList = nil then exit;
    if idx >= DList^.Count then exit;
    address := PtrUInt(DList^.Data) + SizeUInt(idx) * DList^.ElementSize;
    memory.raw.move(pointer(address + DList^.ElementSize), pointer(address),
        (DList^.Count - idx - 1) * DList^.ElementSize);
    dec(DList^.Count);
    { Retain capacity; deletion in the scheduler must not allocate or thrash.
      Explicit DL_ShrinkToFit remains available at a suitable safe point. }
    DL_Delete := true;
end;

function DL_Get(DList: PDList; idx: uint32): void;
begin
    DL_Get := nil;
    if DList = nil then exit;
    if idx < DList^.Count then
        DL_Get := void(PtrUInt(DList^.Data) + SizeUInt(idx) * DList^.ElementSize);
end;

function DL_Set(DList: PDList; idx: uint32; elm: PUInt32): boolean;
var
    target: void;
begin
    target := DL_Get(DList, idx);
    DL_Set := (target <> nil) and (elm <> nil);
    if DL_Set then memory.raw.move(pointer(elm), pointer(target), DList^.ElementSize);
end;

function DL_Size(DList: PDList): uint32;
begin
    DL_Size := 0;
    if DList <> nil then DL_Size := DList^.Count;
end;

procedure DL_Free(DList: PDList);
begin
    if DList = nil then exit;
    kfree(DList^.Data);
    kfree(void(DList));
end;

function DL_IndexOf(DList: PDList; elm: PUInt32): uint32;
var
    offset: PtrUInt;
begin
    DL_IndexOf := High(uint32);
    if (DList = nil) or (elm = nil) then exit;
    if PtrUInt(elm) < PtrUInt(DList^.Data) then exit;
    offset := PtrUInt(elm) - PtrUInt(DList^.Data);
    if (offset < SizeUInt(DList^.Count) * DList^.ElementSize) and
       (offset mod DList^.ElementSize = 0) then DL_IndexOf := offset div DList^.ElementSize;
end;

function DL_Contains(DList: PDList; elm: PUInt32): boolean;
begin
    DL_Contains := DL_IndexOf(DList, elm) <> High(uint32);
end;

function DL_Concat(DList1, DList2: PDList): PDList;
var
    count, oldCount: uint32;
begin
    DL_Concat := nil;
    if (DList1 = nil) or (DList2 = nil) then exit;
    if DList1^.ElementSize <> DList2^.ElementSize then exit;
    count := DList2^.Count;
    oldCount := DList1^.Count;
    if count > High(uint32) - oldCount then exit;
    if not ensure(DList1, oldCount + count) then exit;
    memory.raw.move(pointer(DList2^.Data),
        pointer(PtrUInt(DList1^.Data) + SizeUInt(oldCount) * DList1^.ElementSize),
        count * DList1^.ElementSize);
    DList1^.Count := oldCount + count;
    DL_Concat := DList1;
end;

procedure DL_Clear(DList: PDList);
begin
    if DList <> nil then DList^.Count := 0;
end;

function DL_Capacity(DList: PDList): uint32;
begin
    DL_Capacity := 0;
    if DList <> nil then DL_Capacity := DList^.DataSize div DList^.ElementSize;
end;

procedure DL_Reserve(DList: PDList; NewCapacity: uint32);
begin
    ensure(DList, NewCapacity);
end;

procedure DL_ShrinkToFit(DList: PDList);
begin
    if DList <> nil then resize(DList, DList^.Count * DList^.ElementSize);
end;
end.
