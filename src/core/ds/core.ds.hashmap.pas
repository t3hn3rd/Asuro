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
	Include->Hashmap - Basic Hashmap Implementation.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
    @author(Aaron Hance <ah@aaronhance.me>)
}
unit core.ds.hashmap;

interface

uses
    memory.heap,
    core.enc.fnv1a,
    core.strings,
    io.syslog,
    debug.tracer,
    core.util, arch.x86.util;

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

const
    HASHMAP_DEFAULT_SIZE = 16;
    HASHMAP_DEFAULT_LOADFACTOR = 0.75;

type
    THashForEachCb = procedure(key: pchar; data: void; ud: void);

function  new : PHashMap;
function  newEx(size : uint32; loadFactor : Single) : PHashMap;
procedure add(map : PHashMap; key : pchar; value : void);
function  get(map : PHashMap; key : pchar) : void;
procedure delete(map : PHashMap; key : pchar; freeItem : boolean);
procedure printMap(map : PHashMap);
procedure forEach(map : PHashMap; cb : THashForEachCb; ud : void);

implementation

function KeyHash(key : pchar) : uint32;
begin
    KeyHash := Hash_FNV1a32(void(uint32(key)), StringSize(key));
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
    ExistingItem:= table[idx];
    if ExistingItem = nil then begin
        table[idx]:= item;
    end else begin
        c:=0;
        while ExistingItem^.Next <> nil do begin
            ExistingItem:= ExistingItem^.Next;
        end;
        ExistingItem^.Next:= item;
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

function newEx(size : uint32; loadFactor : Single) : PHashMap;
var
    Map : PHashMap;
    i   : uint32;

begin
    Map:= PHashMap(kalloc(sizeof(THashMap)));
    Map^.size:= size;
    Map^.Table:= DPHashItem(Kalloc(sizeof(PHashItem) * Size));
    Map^.LoadFactor:= loadFactor;
    Map^.Count:= 0;
    for i:=0 to size-1 do begin
        Map^.Table[i]:= nil;
    end;
    newEx:= Map;
end;

function new : PHashMap;
begin
    new:= newEx(HASHMAP_DEFAULT_SIZE, HASHMAP_DEFAULT_LOADFACTOR);
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

procedure forEach(map : PHashMap; cb : THashForEachCb; ud : void);
var
    i    : uint32;
    item : PHashItem;
begin
    if (map = nil) or (map^.Size = 0) or (map^.Table = nil) then exit;
    if cb = nil then exit;
    for i := 0 to map^.Size - 1 do begin
        item := map^.Table[i];
        while item <> nil do begin
            if item^.Key <> nil then
                cb(item^.Key, item^.Data, ud);
            item := item^.Next;
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
            io.syslog.writestring('Map[');
            io.syslog.writeint(i);
            io.syslog.writestring(']->(0)="');
            io.syslog.writestring(map^.table[i]^.key);
            io.syslog.writestring('"');
            item:= map^.table[i]^.next;
            c:=1;
            while item <> nil do begin
                io.syslog.writestring('->(');
                io.syslog.writeint(c);
                io.syslog.writestring(')="');
                io.syslog.writestring(item^.key);
                io.syslog.writestring('"');
                inc(c);
                item:= item^.next;
            end;
            io.syslog.writestringln(' ');
        end;
    end;
end;

end.