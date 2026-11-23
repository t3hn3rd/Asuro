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

unit core.comp.match;

interface

type
    PMatchTable = ^TMatchTable;
    TMatchTable = array[0..4095] of uint32;

{ Table starts zeroed. Caller supplies at least three available bytes. }
function findMatch(table : PMatchTable; src : puint8; pos, available, window : uint32;
                   var distance : uint32) : uint32;

implementation

function findMatch(table : PMatchTable; src : puint8; pos, available, window : uint32;
                   var distance : uint32) : uint32;
var key, slot, previous, length : uint32;
begin
    findMatch := 0;
    key := uint32(src[pos]) or (uint32(src[pos+1]) shl 8) or (uint32(src[pos+2]) shl 16);
    slot := uint32(key * uint32($9E3779B1)) shr 20;
    previous := table^[slot];
    table^[slot] := pos + 1;
    if previous = 0 then exit;
    dec(previous);
    distance := pos - previous;
    if distance > window then exit;
    length := 0;
    while length < available do begin
        if src[previous+length] <> src[pos+length] then break;
        inc(length);
    end;
    findMatch := length;
end;

end.
