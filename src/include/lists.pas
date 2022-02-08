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

{ 
	Include->Lists - Linked List Data Structures & Helpers.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit lists;

interface

uses
    console,
    lmemorymanager,
    util,
    tracer;

type
    { Managed Linked List }

    PLinkedList = ^TLinkedList;
    TLinkedList = record
        Previous : PLinkedList;
        Data     : void;
        Next     : PLinkedList;
    end;

    PLinkedListBase = ^TLinkedListBase;
    TLinkedListBase = record
        Count       : uint32;
        Head        : PLinkedList;
        ElementSize : uint32;
    end;

    { Dynamic List }

    PDList = ^TDList;
    TDList = record
        Count : uint32;
        Data : void;
        ElementSize : uint32;
        DataSize : uint32;

    end;
    
    { Dynamic List Iterator } 

{ String Linked List }

procedure  STRLL_Add(LinkedList : PLinkedListBase; str : pchar);
function   STRLL_Get(LinkedList : PLinkedListBase; idx : uint32) : pchar;
function   STRLL_New : PLinkedListBase;
function   STRLL_Size(LinkedList : PLinkedListBase) : uint32;
procedure  STRLL_Delete(LinkedList : PLinkedListBase; idx : uint32);
procedure  STRLL_Free(LinkedList : PLinkedListBase);
procedure  STRLL_Clear(LinkedList : PLinkedListBase);
function   STRLL_FromString(str : pchar; delimter : char) : PLinkedListBase;

{ Managed Linked List }

function  LL_New(ElementSize : uint32) : PLinkedListBase;
function  LL_Add(LinkedList : PLinkedListBase) : Void;
function  LL_Delete(LinkedList : PLinkedListBase; idx : uint32) : boolean;
function  LL_Size(LinkedList : PLinkedListBase) : uint32;
function  LL_Insert(LinkedList : PLinkedListBase; idx : uint32) : Void;
function  LL_Get(LinkedList : PLinkedListBase; idx : uint32) : Void;
procedure LL_Free(LinkedList : PLinkedListBase);
function  LL_FromString(str : pchar; delimter : char) : PLinkedListBase;

    
{ Dynamic List }

function  DL_New(ElementSize : uint32) : PDList;
function  DL_Add(DList : PDList) : Void;
function  DL_Delete(DList : PDList; idx : uint32) : boolean;
function  DL_Size(DList : PDList) : uint32;
function  DL_Set(DList : PDList; idx : uint32; elm : puint32) : boolean;
function  DL_Get(DList : PDList; idx : uint32) : Void;
procedure DL_Free(DList : PDList);
function  DL_IndexOf(DList : PDList; elm : puint32) : uint32;
function  DL_Contains(DList : PDList; elm : puint32) : boolean;
function DL_Concat(DList1 : PDList; DList2 : PDList) : PDList;


{ Dynamic List Iterator }


implementation

uses
    strings;

{ Managed Linked List }

function LL_New(ElementSize : uint32) : PLinkedListBase;
begin
    LL_New:= PLinkedListBase(kalloc(sizeof(TLinkedListBase)));
    LL_New^.ElementSize:= ElementSize;
    LL_New^.Count:= 0;
    LL_New^.Head:= nil;
end;

function LL_Add(LinkedList : PLinkedListBase) : Void;
var
    Element : PLinkedList;
    Base    : PLinkedList;
    Count   : uint32;

begin
    if LinkedList^.Head = nil then begin
        Element:= PLinkedList(kalloc(sizeof(TLinkedList)));
        Element^.Previous:= nil;
        Element^.Next:= nil;
        Element^.Data:= kalloc(LinkedList^.ElementSize);
        memset(uint32(Element^.Data), 0, LinkedList^.ElementSize);
        LinkedList^.Head:= Element;
        LinkedList^.Count:= LinkedList^.Count + 1;
        LL_Add:= Element^.Data;
    end else begin
        Base:= LinkedList^.Head;
        Count:= 1;
        While Base^.Next <> nil do begin
            Base:= Base^.Next;
            Count:= Count + 1;
        end;
        Element:= PLinkedList(kalloc(sizeof(TLinkedList)));
        Base^.Next:= Element;
        Element^.Previous:= Base;
        Element^.Next:= nil;
        Element^.Data:= kalloc(LinkedList^.ElementSize);
        memset(uint32(Element^.Data), 0, LinkedList^.ElementSize);
        LinkedList^.Count:= LinkedList^.Count + 1;
        LL_Add:= Element^.Data;
    end;
end;

function LL_Delete(LinkedList : PLinkedListBase; idx : uint32) : boolean;
var
    Prev, Next : PLinkedList;
    Base : PLinkedList;
    i : uint32;

begin
    Base:= LinkedList^.Head;
    i:= 0;
    while (i < idx) and (Base <> nil) do begin
        i:= i + 1;
        Base:= Base^.Next;
    end;    
    if Base = nil then begin
        LL_Delete:= false;
        exit;
    end;
    Prev:= Base^.Previous;
    Next:= Base^.Next;
    if Prev = nil then begin
        LinkedList^.Head:= Next;
    end else begin
        Prev^.Next:= Next;
    end;
    if Next <> nil then begin
        Next^.Previous:= Prev;
    end;
    LinkedList^.Count:= LinkedList^.Count - 1;
    kfree(void(Base^.Data));
    kfree(void(Base));
    LL_Delete:= True;
end;

function LL_Size(LinkedList : PLinkedListBase) : uint32;
begin
    LL_Size:= LinkedList^.Count;
end;

function LL_Insert(LinkedList : PLinkedListBase; idx : uint32) : void;
var
    i : uint32;
    Base : PLinkedList;
    Prev, Next : PLinkedList;
    Element    : PLinkedList;

begin
    LL_Insert:= nil;
    if idx > LinkedList^.Count then exit;
    Base:= LinkedList^.Head;
    i:=0;
    while (i < idx) and (Base <> nil) do begin
        i:= i + 1;
        Base:= Base^.Next;
    end;
    if i = 0 then begin
        Element:= PLinkedList(kalloc(sizeof(TLinkedList)));
        Element^.Data:= kalloc(LinkedList^.ElementSize);
        memset(uint32(Element^.Data), 0, LinkedList^.ElementSize);
        Element^.Next:= LinkedList^.Head;
        Element^.Previous:= nil;
        LinkedList^.Head:= Element;
        LinkedList^.Count:= LinkedList^.Count + 1;
        LL_Insert:= Element^.Data;
    end else begin
        if Base = nil then exit;
        Prev:= Base^.Previous;
        Next:= Base;
        Element:= PLinkedList(kalloc(sizeof(TLinkedList)));
        Element^.Data:= kalloc(LinkedList^.ElementSize);
        memset(uint32(Element^.Data), 0, LinkedList^.ElementSize);
        Element^.Previous:= Prev;
        Element^.Next:= Next;
        if Prev = nil then begin
            LinkedList^.Head:= Element;
        end else begin
            Prev^.Next:= Element;
        end;
        if Next <> nil then begin
            Next^.Previous:= Element;
        end;
        LinkedList^.Count:= LinkedList^.Count + 1;
        LL_Insert:= Element^.Data;
    end;
end;

function LL_Get(LinkedList : PLinkedListBase; idx : uint32) : void;
var
    i : uint32;
    Base : PLinkedList;

begin
    LL_Get:= nil;
    if idx >= LinkedList^.Count then exit;
    Base:= LinkedList^.Head;
    i:=0;
    while (i < idx) and (Base <> nil) do begin
        i:= i + 1;
        Base:= Base^.Next;
    end;
    if Base = nil then exit;
    LL_Get:= Base^.Data;
end;

procedure LL_Free(LinkedList : PLinkedListBase);
begin
    while LL_Size(LinkedList) > 0 do begin
        LL_Delete(LinkedList, 0);
    end;
    kfree(void(LinkedList));
end;

function LL_FromString(str : pchar; delimter : char) : PLinkedListBase;
var
    list       : PLinkedListBase;
    i          : uint32 = 0;  
    out_str    : pchar;
    elm        : puint32;
    head       : pchar;
    tail       : pchar;
    size       : uint32;
    null_delim : boolean;

begin
    list := LL_New(sizeof(uint32));
    LL_FromString:= list; 

    head:= str;
    tail:= head;

    null_delim:= false;
    while not null_delim do begin
        if (head^ = delimter) or (head^ = char(0)) then begin
            if head^ = char(0) then null_delim:= true;
            size:= uint32(head) - uint32(tail);
            if size > 0 then begin
                elm:= puint32(LL_Add(list));
                out_str:= stringNew(size + 1); //maybe
                memcpy(uint32(tail), uint32(out_str), size);
                elm^:= uint32(out_str);
            end;
            tail:= head+1;
        end;
        inc(head);
    end;
end;

{ String Linked List }

procedure STRLL_Add(LinkedList : PLinkedListBase; str : pchar);
var
    ptr : puint32;

begin
    ptr:= puint32(LL_Add(LinkedList));
    ptr^:= uint32(str);
end;

function STRLL_Get(LinkedList : PLinkedListBase; idx : uint32) : pchar;
var
    ptr : puint32;

begin
    ptr:= puint32(LL_Get(LinkedList, idx));
    STRLL_Get:= nil;
    if ptr <> nil then begin
        STRLL_Get:= pchar(ptr^);
    end;
end;

function STRLL_New : PLinkedListBase;
begin
    STRLL_New:= LL_New(sizeof(uint32));   
end;

function STRLL_Size(LinkedList : PLinkedListBase) : uint32;
begin
    STRLL_Size:= LL_Size(LinkedList);
end;

procedure STRLL_Delete(LinkedList : PLinkedListBase; idx : uint32);
var
    ptr : pchar;

begin
    tracer.push_trace('lists.STRLL_Delete (Don''t add static strings)');
    ptr:= STRLL_get(LinkedList, idx);
    kfree(void(ptr));
    LL_Delete(LinkedList, idx);
end;

procedure STRLL_Free(LinkedList : PLinkedListBase);
begin
    STRLL_Clear(LinkedList);
    LL_Free(LinkedList);
end;

procedure STRLL_Clear(LinkedList : PLinkedListBase);
begin
    while STRLL_Size(LinkedList) > 0 do STRLL_Delete(LinkedList, 0);
end;

function STRLL_FromString(str : pchar; delimter : char) : PLinkedListBase;
var
    list       : PLinkedListBase;
    i          : uint32 = 0;  
    out_str    : pchar;
    elm        : puint32;
    head       : pchar;
    tail       : pchar;
    size       : uint32;
    null_delim : boolean;

begin
    list := LL_New(sizeof(uint32));
    STRLL_FromString:= list; 

    head:= str;
    tail:= head;

    null_delim:= false;
    while not null_delim do begin
        if (head^ = delimter) or (head^ = char(0)) then begin
            if head^ = char(0) then null_delim:= true;
            size:= uint32(head) - uint32(tail);
            if size > 0 then begin
                elm:= puint32(LL_Add(list));
                out_str:= stringNew(size + 1); //maybe
                memcpy(uint32(tail), uint32(out_str), size);
                elm^:= uint32(out_str);
            end;
            tail:= head+1;
        end;
        inc(head);
    end;
end;

{ Dynamic List }

function  DL_New(ElementSize : uint32) : PDList;
var 
    DL : PDList;
begin

    DL := PDList(kalloc(sizeof(DL)));
    DL^.ElementSize:= ElementSize;
    DL^.count := 0;

    if ElementSize > 128 then begin
        DL^.data := kalloc(ElementSize * 4);
        Dl^.DataSize:= ElementSize * 4;

    end else if ElementSize > 64 then begin
        DL^.data := kalloc(ElementSize * 8);
        Dl^.DataSize:= ElementSize * 8;
        
    end else if ElementSize > 32 then begin
        DL^.data := kalloc(ElementSize * 16);
        Dl^.DataSize:= ElementSize * 16;

    end else if ElementSize > 16 then begin
      DL^.data := kalloc(ElementSize * 32);
      Dl^.DataSize:= ElementSize * 32;
    end else begin
      DL^.data := kalloc(ElementSize * 64);
      Dl^.DataSize:= ElementSize * 64;
    end;

    DL_New := DL;
end;

function  DL_Add(DList : PDList) : Void;
var 
    elm : puint32;
    tempList : puint32;
begin

    //check if we need to resize
    if (DList^.count + 1) * DList^.ElementSize > DList^.DataSize then begin
        push_trace('lists.DL_Add: Resizing');
        tempList := DList^.Data;
        DList^.Data := kalloc(DList^.DataSize * 2);
        
        memset(uint32(DList^.Data), 0, DList^.DataSize * 2);
        memcpy(uint32(tempList), uint32(DList^.Data), DList^.DataSize);

        DList^.DataSize:= DList^.DataSize * 2;

        kfree(void(tempList));
    end;

    push_trace('lists.DL_Add');


    elm := puint32(@puint8(DList^.Data)[(DList^.count * DList^.ElementSize)]);
    elm^ := 0;

    push_trace('lists.DL_Add: Adding');

    DList^.count := DList^.count + 1;

    DL_Add := elm;
end;

function  DL_Delete(DList : PDList; idx : uint32) : boolean;
var 
    elm : puint32;
    tempList : puint32;
begin
    if idx >= DList^.count then begin
        DL_Delete := false;
        exit;
    end;

    elm := puint32( puint8(DList^.Data) + (idx * DList^.ElementSize));
    memcpy(uint32( puint8(elm) + DList^.ElementSize), uInt32(elm), (DList^.count - idx) * DList^.ElementSize);

    DList^.count := DList^.count - 1;

    if (DList^.count * DList^.ElementSize) < DList^.DataSize DIV 2 then begin
        tempList := DList^.Data;
        DList^.DataSize:= DList^.DataSize DIV 2;

        DList^.Data := kalloc(DList^.DataSize);
        memcpy(uint32(tempList), uint32(DList^.Data), DList^.DataSize);

        kfree(void(tempList));
    end;

    DL_Delete := true;
end;

function  DL_Get(DList : PDList; idx : uint32) : Void;
var 
    elm : puint32;
begin
    if idx >= DList^.count then begin
        DL_Get := nil;
        exit;
    end;

    elm := puint32(DList^.Data + (idx * DList^.ElementSize));
    DL_Get := elm;
end;

function DL_Set(DList : PDList; idx : uint32; elm : puint32) : boolean;
var
    tempList : PuInt32;
    size : uint32;
begin
    if idx >= DList^.count then begin
        DL_Set := false;
        exit;
    end;

    //check if we need to resize
    if (idx + 1) * Dlist^.ElementSize > DList^.DataSize then begin
                console.writestring('resising thisthinghere');

        size := idx * DList^.ElementSize * 2;

        tempList := DList^.Data;
        DList^.Data := kalloc(size);
        memset(uint32(DList^.Data), 0, size);

        memcpy(uint32(tempList), uint32(DList^.Data), DList^.DataSize);

        DList^.DataSize := size;

        kfree(void(tempList));
    end;

    console.writeString('offset: ');
    console.writeintln(idx * DList^.ElementSize);
    memcpy(uint32(elm), uint32( PuInt8(DList^.Data) + (idx * DList^.ElementSize)), DList^.ElementSize);

    //check if count is smaller than idx and if so, increase count
    if DList^.count < idx then DList^.count := idx;

    DL_Set := true;
end;

function DL_Size(DList : PDList) : uint32;
begin
    DL_Size := DList^.count;
end;

procedure DL_Free(DList : PDList);
begin
    kfree(void(DList^.Data));
    kfree(void(DList));
end;

function DL_IndexOf(DList : PDList; elm : puint32) : uint32;
var 
    i : uint32;
    temp : puint32;
begin
    for i := 0 to DList^.count - 1 do begin
        temp := puint32( puint8(DList^.Data) + (i * DList^.ElementSize));
        if temp = elm then begin
            DL_IndexOf := i;
            exit;
        end;
    end;

    DL_IndexOf := -1;
end;

function DL_Contains(DList : PDList; elm : puint32) : boolean;
var 
    i : uint32;
begin
    i := DL_IndexOf(DList, elm);

    if i = -1 then begin
        DL_Contains := false;
        exit;
    end;

    DL_Contains := true;
end;

function DL_Concat(DList1 : PDList; DList2 : PDList) : PDList;
var 
    i : uint32;
    temp : puint32;
begin

    //check element size
    if DList1^.ElementSize <> DList2^.ElementSize then begin
        DL_Concat := nil;
        exit;
    end;

    //check if we need to resize
    while true do begin
          if (DList1^.count + DList2^.count) * DList1^.ElementSize > DList1^.DataSize then begin

            temp := DList1^.Data;
            DList1^.Data := kalloc(DList1^.DataSize * 2);
            
            memset(uint32(DList1^.Data), 0, DList1^.DataSize * 2);
            memcpy(uint32(temp), uint32(DList1^.Data), DList1^.DataSize);

            DList1^.DataSize:= DList1^.DataSize * 2;

            kfree(void(temp));
        end else Break;
    end;


    for i := 0 to DList2^.count - 1 do begin
        temp := DL_Add(DList1);
        memcpy(uint32(DL_Get(DList2, i)), uint32(temp), DList1^.ElementSize);
    end;

    DL_Concat := DList1;
end;

end.