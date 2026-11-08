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
    arch.platform.diagnostics;

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
procedure UnitTest;
procedure printMap(map : PHashMap);
procedure forEach(map : PHashMap; cb : THashForEachCb; ud : void);

implementation

function KeyHash(key : pchar) : uint32;
begin
    KeyHash := Hash_FNV1a32(void(key), StringSize(key));
end;

function hashIndex(size : uint32; hash : uint32) : uint32;
begin
    hashIndex:= hash mod size;
end;

procedure putItem(table : DPHashItem; item : PHashItem; idx : uint32);
begin
    item^.Next := table[idx];
    table[idx] := item;
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
        if map^.Size > High(uint32) div 2 then exit;
        NewSize := map^.Size * 2;
        if SizeUInt(NewSize) > High(SizeUInt) div sizeof(PHashItem) then exit;
        NewTable:= DPHashItem(kalloc(SizeUInt(NewSize) * sizeof(PHashItem)));
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
    idx, hash: uint32;
    item: PHashItem;
begin
    if (map = nil) or (key = nil) then exit;

    hash := KeyHash(key);
    idx := hashIndex(map^.Size, hash);
    item := map^.Table[idx];
    while item <> nil do begin
        if (item^.Hash = hash) and StringEquals(item^.Key, key) then begin
            item^.Data := value;
            exit;
        end;
        item := item^.Next;
    end;

    item := PHashItem(kalloc(sizeof(THashItem)));
    if item = nil then exit;
    item^.Key := stringCopy(key);
    if item^.Key = nil then begin
        kfree(void(item));
        exit;
    end;
    item^.Data := value;
    item^.Hash := hash;
    putItem(map^.Table, item, idx);
    inc(map^.Count);
    checkAndRebase(map);
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
    map: PHashMap;
begin
    newEx := nil;
    if (size = 0) or (SizeUInt(size) > High(SizeUInt) div sizeof(PHashItem)) then exit;
    if not (loadFactor > 0) then exit;

    map := PHashMap(kalloc(sizeof(THashMap)));
    if map = nil then exit;
    map^.Table := DPHashItem(kalloc(SizeUInt(size) * sizeof(PHashItem)));
    if map^.Table = nil then begin
        kfree(void(map));
        exit;
    end;
    map^.Size := size;
    map^.LoadFactor := loadFactor;
    newEx := map;
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
    i: uint32;
    item: PHashItem;
begin
    if (map = nil) or (map^.Size = 0) then exit;

    for i := 0 to map^.Size - 1 do begin
        item := map^.Table[i];
        while item <> nil do begin
            log('HASHMAP', item^.Key);
            item := item^.Next;
        end;
    end;
end;

procedure UnitTest;
var
    map: PHashMap;
    value: void;
    key: pchar;
    i, passed, failed: uint32;
    beforeFree: SizeUInt;

    procedure Assert(condition: boolean; name: pchar);
    begin
        if condition then
            inc(passed)
        else begin
            inc(failed);
            log('HASHMAP', name);
        end;
    end;
begin
    passed := 0;
    failed := 0;
    beforeFree := lmm_total_free;
    value := kalloc(sizeof(PtrUInt));
    map := newEx(1, 100);
    add(map, 'a', value);
    add(map, 'b', value);
    add(map, 'c', value);
    Assert((map^.Count = 3) and (get(map, 'a') = value) and
        (get(map, 'c') = value), 'FAIL: native hash collision chain');
    add(map, 'b', nil);
    Assert((map^.Count = 3) and (get(map, 'b') = nil), 'FAIL: hash replacement count');
    delete(map, 'b', false);
    Assert((map^.Count = 2) and (get(map, 'a') = value) and
        (get(map, 'c') = value), 'FAIL: hash collision middle deletion');
    delete(map, 'c', false);
    delete(map, 'a', false);
    Assert(map^.Count = 0, 'FAIL: hash collision head and tail deletion');
    kfree(void(map^.Table));
    kfree(void(map));

    map := new;
    for i := 0 to 39 do begin
        key := intToString(i);
        add(map, key, value);
        kfree(void(key));
    end;
    Assert((map^.Count = 40) and (map^.Size > HASHMAP_DEFAULT_SIZE),
        'FAIL: hash growth');
    for i := 0 to 39 do begin
        key := intToString(i);
        Assert(get(map, key) = value, 'FAIL: hash rebase preserves high pointers');
        delete(map, key, false);
        kfree(void(key));
    end;
    kfree(void(map^.Table));
    kfree(void(map));
    kfree(value);
    Assert(newEx(0, 0.75) = nil, 'FAIL: zero-sized hash table rejected');
    Assert(lmm_total_free = beforeFree, 'FAIL: hash allocation accounting');
    testSummary('HASHMAP', 'HASHMAP_TESTS_PASSED', 'HASHMAP_TESTS_FAILED', passed, failed);
end;

end.
