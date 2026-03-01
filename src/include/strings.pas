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
	Include->Strings - String Manipulation.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
    @author(Aaron Hance <ah@aaronhance.me>)
}
unit strings;

interface

uses 
    util, 
    lmemorymanager,
    lists;

function stringToUpper(str : pchar) : pchar;
function stringToLower(str : pchar) : pchar;
function stringEquals(str1, str2 : pchar) : boolean;
function stringCopy(str : pchar) : pchar;
function stringNew(size : uint32) : pchar;
function stringSize(str : pchar) : uint32;
function stringConcat(str1, str2 : pchar) : pchar;
function stringTrim(str : pchar; length : uint32) : pchar;
function stringSub(str : pchar; start, size : uint32) : pchar;
function stringReplace(str, find, replace : pchar) : pchar;
function stringIndexOf(str, find : pchar) : sint32;
function stringContains(str : pchar; sub : pchar) : boolean;
function stringToInt(str : pchar) : uint32;
function hexStringToInt(str : pchar) : uint32;
function intToString(i : uint32) : pchar;
function boolToString(b : boolean; ext : boolean) : pchar;

implementation

function hexStringToInt(str : pchar) : uint32;
var
    result : uint32;
    i      : uint32;
    Shift  : uint32;

begin
    result:= 0;
    Shift:= (stringSize(str)-1) * 4;
    for i:=0 to stringSize(str)-1 do begin
        result:= result OR (HexCharToDecimal(str[i]) SHL Shift);
        Shift:= Shift - 4;
    end;
    hexStringToInt:= result;
end;

function stringToUpper(str : pchar) : pchar;
var
    result : pchar;
    i : uint32;

begin
    result:= stringCopy(str);
    for i:=0 to stringSize(result) do begin
        if (byte(result[i]) >= 97) and (byte(result[i]) <= 122) then result[i]:= char(byte(result[i]) - 32);
    end;
    stringToUpper:= result;
end;

function stringToLower(str : pchar) : pchar;
var
    result : pchar;
    i : uint32;

begin
    result:= stringCopy(str);
    for i:=0 to stringSize(result) do begin
        if (byte(result[i]) >= 65) and (byte(result[i]) <= 90) then result[i]:= char(byte(result[i]) + 32);
    end;
    stringToLower:= result;
end;

function stringEquals(str1, str2 : pchar) : boolean;
var
    i : uint32;

begin
    stringEquals:= true;
    if stringSize(str1) <> stringSize(str2) then begin
        stringEquals:= false;
        exit;
    end else begin
        for i:=0 to stringSize(str1)-1 do begin
            if str1[i] <> str2[i] then begin
                stringEquals:= false;
                exit;
            end;
        end; 
    end;   
end;

function stringCopy(str : pchar) : pchar;
var
    result : pchar;
    size   : uint32;

begin
    size:= stringSize(str);
    result:= stringNew(size);
    memcpy(uint32(str), uint32(result), size);
    stringCopy:= result;    
end;

function stringNew(size : uint32) : pchar;
var
    result : pchar;

begin
    result:= pchar(kalloc(size + 1));
    memset(uint32(result), 0, size + 1);
    stringNew:= result;
end;

function stringSize(str : pchar) : uint32;
var
    i : uint32;

begin
    i:=0;
    while byte(str[i]) <> 0 do begin
        inc(i);
    end; 
    stringSize:=i;
end;

function stringConcat(str1, str2 : pchar) : pchar;
var
    size : uint32;
    result : pchar;

begin
    result:= stringNew(stringSize(str1)+stringSize(str2));
    memcpy(uint32(str1), uint32(result), stringSize(str1));
    memcpy(uint32(str2), uint32(result+stringSize(str1)), stringSize(str2));
    stringConcat:= result;
end;

// Trim the string to the specified length.
function stringTrim(str : pchar; length : uInt32) : pchar;
var
    result : pchar;
begin
    result:= stringNew(length);
    memcpy(uint32(str), uint32(result), length);
    stringTrim:= result;
end;

// Return a substring of the string.
function stringSub(str : pchar; start, size : uint32) : pchar;
var
    result : pchar;
begin
    result:= stringNew(size);
    memcpy(uint32(str)+start, uint32(result), size);
    stringSub:= result;
end;

// Replace first instance of a string with another.
function stringReplace(str, find, replace : pchar) : pchar;
var
    result : pchar;
    i, j, k : uint32;
    found : boolean;
begin

    // Find the first instance of the find string.
    i:= 0;
    found:= false;
    while (i < stringSize(str)) and (not found) do begin
        if stringEquals(str+i, find) then begin
            found:= true;
        end else begin
            inc(i);
        end;
    end;

    // If we found the find string, replace it.
    if found then begin
        result:= stringNew(stringSize(str) - stringSize(find) + stringSize(replace));
        j:= 0;
        k:= 0;
        while i < stringSize(str) do begin
            if stringEquals(str+i, find) then begin
                memcpy(uint32(replace), uint32(result+j), stringSize(replace));
                j:= j + stringSize(replace);
                inc(i, stringSize(find));
            end else begin
                result[j]:= str[i];
                inc(j);
                inc(i);
            end;
        end;
        stringReplace:= result;
    end else begin
        stringReplace:= stringCopy(str);
    end;

    // Return the result.
    stringReplace:= result;

end;


// Find the index of the first instance of a string.
function stringIndexOf(str, find : pchar) : sint32;
var 
    i : uint32;
    found : boolean;
begin
    i:= 0;
    found:= false;
    while (i < stringSize(str)) and (not found) do begin
        if stringEquals(str+i, find) then begin
            found:= true;
        end else begin
            inc(i);
        end;
    end;
    if found then begin
        stringIndexOf:= i;
    end else begin
        stringIndexOf:= -1;
    end;
end;

function stringContains(str : pchar; sub : pchar) : boolean;
var
    strEnd, subEnd, i, j, count : uint32;

begin
    stringContains:= false;
    if stringEquals(str,sub) then begin
        stringContains:= true;
        exit;
    end;
    strEnd:= stringSize(str)-1;
    subEnd:= stringSize(sub)-1;
    if strEnd < subEnd then exit;
    for i:=0 to strEnd do begin
        if str[i] = sub[0] then begin 
            count:= 0;
            for j:=0 to subEnd do begin
                if (i+j) > strEnd then 
                    exit;
                if str[i+j] = sub[j] then begin
                    inc(count)
                end else begin
                    count:= 0;
                    break;
                end;
            end;
            if count > 0 then begin
                stringContains:= true;
                exit;
            end;
        end;
    end;
end;

function stringToInt(str : pchar) : uint32;
var
    i : uint32;
    x : uint32;
    v : uint32;
    r : uint32;

begin
    stringToInt:= 0;
    x:= 1;
    r:= 0;
    for i:=stringSize(str)-1 downto 0 do begin
        v:= byte(str[i]) - 48;
        if (v >= 0) and (v <= 9) then begin
            r:= r + (v * x);
        end;
        x:= x * 10;
    end;
    stringToInt:= r;
end;

function intToString(i : uint32) : pchar;
var
    buf    : array[0..11] of char;
    len    : uint32;
    tmp    : uint32;
    result : pchar;
    j      : uint32;
begin
    if i = 0 then begin
        result := stringNew(1);
        result[0] := '0';
        result[1] := #0;
        intToString := result;
        exit;
    end;
    len := 0;
    tmp := i;
    while tmp > 0 do begin
        buf[len] := char(byte('0') + (tmp mod 10));
        tmp := tmp div 10;
        inc(len);
    end;
    result := stringNew(len);
    for j := 0 to len - 1 do begin
        result[j] := buf[len - 1 - j];
    end;
    result[len] := #0;
    intToString := result;
end;

function boolToString(b : boolean; ext : boolean) : pchar;
var
    t : pchar;
    f : pchar;

begin
    if ext then begin
        t:= stringCopy('true');
        f:= stringCopy('false');
    end else begin
        t:= stringCopy('1');
        f:= stringCopy('0');
    end;
    if b then begin
        kfree(void(f));
        boolToString:= t;
    end else begin
        kfree(void(t));
        boolToString:= f;
    end;
end;

end.