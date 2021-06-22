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

end.