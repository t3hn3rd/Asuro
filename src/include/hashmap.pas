unit hashmap;

interface

uses
    md5, util, strings, lmemorymanager, console;

type
    DPHashItem = ^PHashItem;
    PHashItem = ^THashItem;
    THashItem = record
        Next : PHashItem;
        Key  : pchar;
        Data : void;
    end;
    PHashMap = ^THashMap;
    THashMap = record
        Size    : uint32;
        Table   : DPHashItem;
    end;

function  new(size : uint32) : PHashMap;
procedure add(map : PHashMap; key : pchar; value : void);
function  get(map : PHashMap; key : pchar) : void;
procedure delete(map : PHashMap; key : pchar);
procedure deleteAndFree(map : PHashMap; key : pchar);
procedure printMap(map : PHashMap);

implementation

function hashIndex(size : uint32; key : pchar) : uint32;
var
    KeyLength  : uint32;
    Hash       : PMD5Digest;
    Hash128    : puint128;
    Hash32     : uint32;

begin
    KeyLength:= StringSize(key);
    Hash:= MD5Buffer(puint8(key), KeyLength);
    Hash128:= puint128(Hash);
    Hash32:= MD5To32(Hash128);
    hashIndex:= Hash32 mod size;
    kfree(void(Hash));
end;

function newItem : PHashItem;
begin
    newItem:= PHashItem(kalloc(sizeof(THashItem)));
    newItem^.Next:= nil;
    newItem^.Key:= nil;
    newItem^.Data:= nil;    
end;

procedure add(map : PHashMap; key : pchar; value : void);
var
    Idx     : uint32;
    Item    : PHashItem;
    nItem   : PHashItem;

begin
    if (map <> nil) and (key <> nil) then begin
        Idx:= hashIndex(map^.size, key);
        if map^.Table[Idx] = nil then begin
            Item:= newItem;
            Item^.Next:= nil;
            map^.Table[Idx]:= Item;
        end else begin
            //Collision
            Item:= map^.Table[Idx];
            while not StringEquals(Item^.key, key) do begin
                if Item^.Next <> nil then begin
                    Item:= Item^.Next;
                end else begin
                    nItem:= newItem();
                    Item^.Next:= nItem;
                    Item:= nItem;
                    Item^.Next:= nil;
                    break;
                end;
            end;
        end;
        if Item^.Key = nil then Item^.Key:= stringCopy(key);
        Item^.Data:= value;
    end;
end;

function get(map : PHashMap; key : pchar) : void;
var
    Idx  : uint32;
    Item : PHashItem;

begin
    get:= nil;
    if (map <> nil) and (key <> nil) then begin
        Idx:= hashIndex(map^.size, key);
        Item:= map^.table[Idx];
        if Item = nil then exit;
        while not StringEquals(Item^.key, key) do begin
            Item:= Item^.Next;
            if Item = nil then break;
        end;
        if Item <> nil then get:= Item^.Data;
    end;
end;

function new(size : uint32) : PHashMap;
var
    Map : PHashMap;
    i   : uint32;

begin
    Map:= PHashMap(kalloc(sizeof(THashMap)));
    Map^.size:= size;
    Map^.Table:= DPHashItem(Kalloc(sizeof(PHashItem) * Size));
    for i:=0 to size-1 do begin
        Map^.Table[i]:= nil;
    end;
    new:= Map;
end;

procedure deleteAndFree(map : PHashMap; key : pchar);
var
    Idx  : uint32;
    Item : PHashItem;
    Prev : PHashItem;

begin
    Prev:= nil;
    if (map <> nil) and (key <> nil) then begin
        Idx:= hashIndex(map^.size, key);
        Item:= map^.table[Idx];
        while not StringEquals(Item^.key, key) do begin
            Prev:= Item;
            Item:= Item^.Next;
            if Item = nil then break;
        end;
        if Item <> nil then begin
            If Prev <> nil then Prev^.Next:= Item^.Next;
            If Prev = nil then begin
                if Item^.Next <> nil then
                    map^.table[Idx]:= Item^.Next
                else
                    map^.table[Idx]:= nil;
            end;
            kfree(void(Item^.Key));
            kfree(void(Item^.Data));
            kfree(void(Item));
        end;
    end;
end;

procedure delete(map : PHashMap; key : pchar);
var
    Idx  : uint32;
    Item : PHashItem;
    Prev : PHashItem;

begin
    Prev:= nil;
    if (map <> nil) and (key <> nil) then begin
        Idx:= hashIndex(map^.size, key);
        Item:= map^.table[Idx];
        while not StringEquals(Item^.key, key) do begin
            Prev:= Item;
            Item:= Item^.Next;
            if Item = nil then break;
        end;
        if Item <> nil then begin
            If Prev <> nil then Prev^.Next:= Item^.Next;
            If Prev = nil then begin
                if Item^.Next <> nil then 
                    map^.table[Idx]:= Item^.Next
                else
                    map^.table[Idx]:= nil;
            end;
            kfree(void(Item^.Key));
            kfree(void(Item));
        end;
    end;
end;

procedure printMap(map : PHashMap);
var
    i,c : uint32;
    item : PHashItem;

begin
    for i:=0 to map^.Size-1 do begin
        if map^.table[i] <> nil then begin
            writestring('Map[');
            writeint(i);
            writestring(']->(0)="');
            writestring(map^.table[i]^.key);
            writestring('"');
            item:= map^.table[i]^.next;
            c:=1;
            while item <> nil do begin
                writestring('->(');
                writeint(c);
                writestring(')="');
                writestring(item^.key);
                writestring('"');
                inc(c);
                item:= item^.next;
            end;
            writestringln(' ');
        end;
    end;
end;

end.