unit lists;

interface

uses
    console,
    lmemorymanager,
    util;

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

{ Managed Linked List }
function LL_New(ElementSize : uint32) : PLinkedListBase;
function LL_Add(LinkedList : PLinkedListBase) : Void;
function LL_Delete(LinkedList : PLinkedListBase; idx : uint32) : boolean;
function LL_Size(LinkedList : PLinkedListBase) : uint32;
function LL_Insert(LinkedList : PLinkedListBase; idx : uint32) : Void;
function LL_Get(LinkedList : PLinkedListBase; idx : uint32) : Void;
procedure LL_Free(LinkedList : PLinkedListBase);
procedure LL_TEST();

implementation

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
    if idx >= LinkedList^.Count then exit;
    Base:= LinkedList^.Head;
    i:=0;
    while (i < idx) and (Base <> nil) do begin
        i:= i + 1;
        Base:= Base^.Next;
    end;
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

procedure LL_Test();
var
    i : uint32;
    LList : PLinkedListBase;
    Elem : Void;
    Str : PChar;

begin
     console.writestringln('Add 3 Elements: ');
     LList:= LL_New(10);
     Elem:= LL_Add(LList);
     Str:= PChar(Elem);
     Str[0]:= 'H';
     Str[1]:= 'E';
     Str[2]:= 'L';
     Str[3]:= 'L';
     Str[4]:= 'O';
     Elem:= LL_Add(LList);
     Str:= PChar(Elem);
     Str[0]:= 'W';
     Str[1]:= 'O';
     Str[2]:= 'R';
     Str[3]:= 'L';
     Str[4]:= 'D';
     Elem:= LL_Add(LList);
     Str:= PChar(Elem);
     Str[0]:= 'T';
     Str[1]:= 'E';
     Str[2]:= 'S';
     Str[3]:= 'T';

     for i:=0 to LL_Size(LList)-1 do begin
        console.writestringln(PChar(LL_Get(LList, i)));
     end;

     console.writestringln(' ');
     console.writestringln('Remove Element 1:');
     LL_Delete(LList, 1);

     for i:=0 to LL_Size(LList)-1 do begin
        console.writestringln(PChar(LL_Get(LList, i)));
     end;

     LL_Free(LList);
end;

end.