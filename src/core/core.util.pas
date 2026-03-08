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
    core.util - Portable data manipulation utilities.

    Byte/word manipulation, endian swaps, memset/memcpy, BCD conversion,
    hex parsing, and other helpers that have no x86 assembly dependency.

    @author(Kieron Morris <kjm@kieronmorris.me>)
    @author(Aaron Hance <ah@aaronhance.me>)
}
unit core.util;

interface

function hi(b : uint8) : uint8;
function lo(b : uint8) : uint8;
function switchendian(b : uint8) : uint8;
function switchendian16(b : uint16) : uint16;
function switchendian32(b : uint32) : uint32;
function getWord(i : uint32; hi : boolean) : uint16;
function getByte(i : uint32; index : uint8) : uint8;

procedure memset(location : uint32; value : uint8; size : uint32);
procedure memcpy(source : uint32; dest : uint32; size : uint32);

function BCDToUint8(bcd : uint8) : uint8;
function HexCharToDecimal(hex : char) : uint8;

function abs(x : sint32) : uint32;

implementation

function abs(x : sint32) : uint32;
var
    y : uint32;

begin
    y:= x SHR 31;
    abs:= (x XOR y) - y;
end;

function switchendian16(b : uint16) : uint16;
begin
    switchendian16:= ((b AND $FF00) SHR 8) OR ((b AND $00FF) SHL 8);
end;

function switchendian32(b : uint32) : uint32;
begin
    switchendian32:= ((b AND $FF000000) SHR 24) OR 
                     ((b AND $00FF0000) SHR 8) OR 
                     ((b AND $0000FF00) SHL 8) OR 
                     ((b AND $000000FF) SHL 24);
end;

function HexCharToDecimal(hex : char) : uint8;
begin
    case hex of
        '0':HexCharToDecimal:=0;
        '1':HexCharToDecimal:=1;
        '2':HexCharToDecimal:=2;
        '3':HexCharToDecimal:=3;
        '4':HexCharToDecimal:=4;
        '5':HexCharToDecimal:=5;
        '6':HexCharToDecimal:=6;
        '7':HexCharToDecimal:=7;
        '8':HexCharToDecimal:=8;
        '9':HexCharToDecimal:=9;
        'a':HexCharToDecimal:=10;
        'A':HexCharToDecimal:=10;
        'b':HexCharToDecimal:=11;
        'B':HexCharToDecimal:=11;
        'c':HexCharToDecimal:=12;
        'C':HexCharToDecimal:=12;
        'd':HexCharToDecimal:=13;
        'D':HexCharToDecimal:=13;
        'e':HexCharToDecimal:=14;
        'E':HexCharToDecimal:=14;
        'f':HexCharToDecimal:=15;
        'F':HexCharToDecimal:=15;
        else HexCharToDecimal:= 0;
    end;
end;

function hi(b : uint8) : uint8; [public, alias: 'util_hi'];
begin
     hi:= (b AND $F0) SHR 4;
end;

function lo(b : uint8) : uint8; [public, alias: 'util_lo'];
begin
     lo:= b AND $0F;
end;

function switchendian(b : uint8) : uint8; [public, alias: 'util_switchendian'];
begin
     switchendian:= (lo(b) SHL 4) OR hi(b);
end;

procedure memset(location : uint32; value : uint8; size : uint32);
var
    loc : puint8;
    i   : uint32;

begin
    if size = 0 then exit;
    for i:=0 to size-1 do begin
        loc:= puint8(location + i);
        loc^:= value;
    end;
end;

procedure memcpy(source : uint32; dest : uint32; size : uint32);
var
    src, dst : puint8;
    i : uint32;

begin
    if size = 0 then exit;
    for i:=0 to size-1 do begin
        src:= puint8(source + i);
        dst:= puint8(dest + i);
        dst^:= src^;
    end;
end;

function getWord(i : uint32; hi : boolean) : uint16;
begin
    if hi then begin
        getWord:= (i AND $FFFF0000) SHR 16;
    end else begin
        getWord:= (i AND $0000FFFF);
    end;    
end;

function getByte(i : uint32; index : uint8) : uint8;
var
    mask : uint32;

begin
    mask:= ($FF SHL (8*index));
    getByte:= (i AND mask) SHR (8*index);
end;

function BCDToUint8(bcd : uint8) : uint8;
begin
    BCDToUint8:= ((bcd SHR 4) * 10) + (bcd AND $0F);
end;

end.
