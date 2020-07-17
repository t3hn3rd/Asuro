unit hashmap;

interface

uses
    md5, util, strings, lmemorymanager, console, tracer;

type
    DPHashItem = ^PHashItem;
    PHashItem = ^THashItem;
    THashItem = record
        Next : PHashItem;
        Key  : pchar;
        Hash : uint32;
        Data : void;
    end;
    PHashMap = ^THashMap;
    THashMap = record
        Size        : uint32;
        LoadFactor  : Single;
        Count       : uint32;
        Table       : DPHashItem;
    end;

function  new(size : uint32) : PHashMap;
procedure add(map : PHashMap; key : pchar; value : void);
function  get(map : PHashMap; key : pchar) : void;
procedure delete(map : PHashMap; key : pchar; freeItem : boolean);
procedure printMap(map : PHashMap);

implementation

function KeyHash(key : pchar) : uint32;
var
    KeyLength  : uint32;
    MD5_Hash   : PMD5Digest;
    Hash128    : puint128;
    Hash32     : uint32;

begin
    KeyLength:= StringSize(key);
    MD5_Hash:= MD5Buffer(puint8(key), KeyLength);
    Hash128:= puint128(MD5_Hash);
    Hash32:= MD5To32(Hash128);
    KeyHash:= Hash32;
    kfree(void(MD5_Hash));
end;

function hashIndex(size : uint32; hash : uint32) : uint32;
begin
    hashIndex:= hash mod size;
end;

function newItem : PHashItem;
begin
    newItem:= PHashItem(kalloc(sizeof(THashItem)));
    newItem^.Next:= nil;
    newItem^.Key:= nil;
    newItem^.Data:= nil; 
    newItem^.Hash:= 0;   
end;

procedure putItem(table : DPHashItem; item : PHashItem; idx : uint32);
var
    ExistingItem : PHashItem;
    c            : uint32;

begin
    tracer.push_trace('hashmap.putItem.1');
    ExistingItem:= table[idx];
    tracer.push_trace('hashmap.putItem.2');
    if ExistingItem = nil then begin
        tracer.push_trace('hashmap.putItem.3');
        table[idx]:= item;
    end else begin
        tracer.push_trace('hashmap.putItem.4');
        c:=0;
        while ExistingItem^.Next <> nil do begin
            tracer.push_trace('hashmap.putItem.5');
            ExistingItem:= ExistingItem^.Next;
        end;
        tracer.push_trace('hashmap.putItem.6');
        ExistingItem^.Next:= item;
        tracer.push_trace('hashmap.putItem.6');
    end;
end;

procedure checkAndRebase(map : PHashMap);
var
    size        : Single;
    loadFactor  : Single;
    max_load    : Single;
    NewTable    : DPHashItem;
    NewSize     : uint32;
    i           : uint32;
    Item        : PHashItem;
    Next        : PHashItem;

begin
    size:= map^.size;
    loadFactor:= map^.LoadFactor;
    max_load:= size * loadFactor;
    if map^.count > max_load then begin
        NewSize:= map^.Size * 2;
        NewTable:= DPHashItem(kalloc(sizeof(PHashItem) * NewSize));
        for i:=0 to NewSize-1 do begin
            NewTable[i]:= nil;
        end;
        If NewTable <> nil then begin
            for i:=0 to map^.size-1 do begin
                item:= map^.table[i];
                while item <> nil do begin
                    Next:= item^.Next;
                    item^.Next:= nil;
                    putItem(NewTable, item, hashIndex(NewSize, item^.hash));
                    item:= Next;
                end;
            end;
            kfree(void(map^.table));
            map^.table:= NewTable;
            map^.size:= NewSize;
        end;
    end;
end;

procedure add(map : PHashMap; key : pchar; value : void);
var
    Idx     : uint32;
    hash    : uint32;
    Item    : PHashItem;
    nItem   : PHashItem;

begin
    if (map <> nil) and (key <> nil) then begin
        hash:= KeyHash(key);
        Idx:= hashIndex(map^.size, hash);
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
        Item^.Hash:= hash;
        inc(map^.count);
        checkAndRebase(map);
    end;
end;

function get(map : PHashMap; key : pchar) : void;
var
    Idx  : uint32;
    hash : uint32;
    Item : PHashItem;

begin
    get:= nil;
    if (map <> nil) and (key <> nil) then begin
        hash:= KeyHash(key);
        Idx:= hashIndex(map^.size, hash);
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
    Map^.LoadFactor:= 0.75;
    Map^.Count:= 0;
    for i:=0 to size-1 do begin
        Map^.Table[i]:= nil;
    end;
    new:= Map;
end;

procedure delete(map : PHashMap; key : pchar; freeItem : boolean);
var
    Idx  : uint32;
    hash : uint32;
    Item : PHashItem;
    Prev : PHashItem;

begin
    Prev:= nil;
    if (map <> nil) and (key <> nil) then begin
        hash:= KeyHash(key);
        Idx:= hashIndex(map^.size, hash);
        Item:= map^.table[Idx];
        if Item <> nil then begin
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
                if freeItem then kfree(void(Item^.Data));
                kfree(void(Item));
                dec(map^.count);
            end;
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