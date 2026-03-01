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
function stringMatchAt(str : pchar; pos : uint32; find : pchar) : boolean;
procedure UnitTest;

implementation

uses
    syslog;

function hexStringToInt(str : pchar) : uint32;
var
    result : uint32;
    i      : uint32;
    Shift  : uint32;
    len    : uint32;

begin
    result:= 0;
    len:= stringSize(str);
    if len = 0 then begin
        hexStringToInt:= 0;
        exit;
    end;
    Shift:= (len-1) * 4;
    for i:=0 to len-1 do begin
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
    if stringSize(result) > 0 then
        for i:=0 to stringSize(result)-1 do begin
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
    if stringSize(result) > 0 then
        for i:=0 to stringSize(result)-1 do begin
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
    end;
    if stringSize(str1) = 0 then exit;
    for i:=0 to stringSize(str1)-1 do begin
        if str1[i] <> str2[i] then begin
            stringEquals:= false;
            exit;
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
    newSize : uint32;

begin
    newSize:= size + 1;
    result:= pchar(kalloc(newSize));
    memset(uint32(result), 0, newSize);
    stringNew:= result;
end;

function stringSize(str : pchar) : uint32;
var
    i : uint32;

begin
    i:=0;
    if(str = nil) then begin
        stringSize:= 0;
        exit;
    end;
    while byte(str[i]) <> 0 do begin
        inc(i);
    end; 
    stringSize:=i;
end;

function stringConcat(str1, str2 : pchar) : pchar;
var
    size1, size2 : uint32;
    result : pchar;

begin
    size1:= stringSize(str1);
    size2:= stringSize(str2);
    result:= stringNew(size1 + size2);
    memcpy(uint32(str1), uint32(result), size1);
    memcpy(uint32(str2), uint32(result + size1), size2);
    stringConcat:= result;
end;

// Trim the string to the specified length.
function stringTrim(str : pchar; length : uInt32) : pchar;
var
    result : pchar;
    strLen : uint32;
begin
    strLen:= stringSize(str);
    if length > strLen then length:= strLen;
    result:= stringNew(length);
    memcpy(uint32(str), uint32(result), length);
    stringTrim:= result;
end;

// Return a substring of the string.
function stringSub(str : pchar; start, size : uint32) : pchar;
var
    result : pchar;
    strLen : uint32;
begin
    strLen:= stringSize(str);
    if start >= strLen then begin
        stringSub:= stringNew(0);
        exit;
    end;
    if start + size > strLen then size:= strLen - start;
    result:= stringNew(size);
    memcpy(uint32(str)+start, uint32(result), size);
    stringSub:= result;
end;

// Compare find against str starting at position pos, without requiring full string equality.
function stringMatchAt(str : pchar; pos : uint32; find : pchar) : boolean;
var
    i, findLen, strLen : uint32;
begin
    stringMatchAt:= false;
    findLen:= stringSize(find);
    strLen:= stringSize(str);
    if findLen = 0 then begin
        stringMatchAt:= true;
        exit;
    end;
    if pos + findLen > strLen then exit;
    for i:= 0 to findLen - 1 do begin
        if str[pos + i] <> find[i] then exit;
    end;
    stringMatchAt:= true;
end;

// Replace first instance of a string with another.
function stringReplace(str, find, replace : pchar) : pchar;
var
    result : pchar;
    strLen, findLen, replLen, pos, suffixLen : uint32;
    found : boolean;
begin
    strLen:= stringSize(str);
    findLen:= stringSize(find);
    replLen:= stringSize(replace);

    // Find the first instance of the find string.
    pos:= 0;
    found:= false;
    while (pos + findLen <= strLen) and (not found) do begin
        if stringMatchAt(str, pos, find) then begin
            found:= true;
        end else begin
            inc(pos);
        end;
    end;

    // If we found the find string, replace it.
    if found then begin
        result:= stringNew(strLen - findLen + replLen);
        // Copy prefix before match
        if pos > 0 then
            memcpy(uint32(str), uint32(result), pos);
        // Copy replacement
        if replLen > 0 then
            memcpy(uint32(replace), uint32(result + pos), replLen);
        // Copy suffix after match
        suffixLen:= strLen - pos - findLen;
        if suffixLen > 0 then
            memcpy(uint32(str) + pos + findLen, uint32(result) + pos + replLen, suffixLen);
        stringReplace:= result;
    end else begin
        stringReplace:= stringCopy(str);
    end;
end;


// Find the index of the first instance of a string.
function stringIndexOf(str, find : pchar) : sint32;
var 
    i, strLen, findLen : uint32;
begin
    strLen:= stringSize(str);
    findLen:= stringSize(find);
    if findLen = 0 then begin
        stringIndexOf:= 0;
        exit;
    end;
    if findLen > strLen then begin
        stringIndexOf:= -1;
        exit;
    end;
    for i:= 0 to strLen - findLen do begin
        if stringMatchAt(str, i, find) then begin
            stringIndexOf:= i;
            exit;
        end;
    end;
    stringIndexOf:= -1;
end;

function stringContains(str : pchar; sub : pchar) : boolean;
begin
    stringContains:= (stringIndexOf(str, sub) >= 0);
end;

function stringToInt(str : pchar) : uint32;
var
    i : uint32;
    x : uint32;
    v : uint32;
    r : uint32;

begin
    stringToInt:= 0;
    if stringSize(str) = 0 then exit;
    x:= 1;
    r:= 0;
    for i:=stringSize(str)-1 downto 0 do begin
        v:= byte(str[i]) - 48;
        if v <= 9 then begin
            r:= r + (v * x);
        end;
        x:= x * 10;
    end;
    stringToInt:= r;
end;

function intToString(i : uint32) : pchar;
var
    result : pchar;
    tmp    : uint32;
    len    : uint32;
    pos    : uint32;

begin
    if i = 0 then begin
        result:= stringNew(1);
        result[0]:= '0';
        intToString:= result;
        exit;
    end;
    // Count digits
    len:= 0;
    tmp:= i;
    while tmp > 0 do begin
        inc(len);
        tmp:= tmp div 10;
    end;
    // Build string from right to left
    result:= stringNew(len);
    pos:= len;
    tmp:= i;
    while tmp > 0 do begin
        dec(pos);
        result[pos]:= char((tmp mod 10) + 48);
        tmp:= tmp div 10;
    end;
    intToString:= result;
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

procedure UnitTest;
var
    s, s2, s3 : pchar;
    passed, failed : uint32;

    procedure Assert(condition : boolean; testName : pchar);
    var
        msg : pchar;
    begin
        if condition then begin
            inc(passed);
        end else begin
            inc(failed);
            msg:= stringConcat('FAIL: ', testName);
            syslog.logln('STRINGS', msg);
            kfree(void(msg));
        end;
    end;

    procedure PrintSummary;
    var
        pStr, fStr, msg, tmp : pchar;
    begin
        pStr:= intToString(passed);
        fStr:= intToString(failed);
        msg:= stringConcat(pStr, ' passed, ');
        tmp:= stringConcat(msg, fStr);
        kfree(void(msg));
        msg:= stringConcat(tmp, ' failed.');
        kfree(void(tmp));
        syslog.logln('STRINGS', msg);
        kfree(void(msg));
        kfree(void(pStr));
        kfree(void(fStr));
    end;

begin
    passed:= 0;
    failed:= 0;
    syslog.logln('STRINGS', 'Unit tests starting...');

    { === stringSize === }
    Assert(stringSize('HELLO') = 5, 'stringSize(HELLO)=5');
    Assert(stringSize('') = 0, 'stringSize(empty)=0');
    Assert(stringSize('A') = 1, 'stringSize(A)=1');
    Assert(stringSize(nil) = 0, 'stringSize(nil)=0');

    { === stringNew === }
    s:= stringNew(0);
    Assert(stringSize(s) = 0, 'stringNew(0) is empty');
    kfree(void(s));
    s:= stringNew(5);
    Assert(stringSize(s) = 0, 'stringNew(5) is zeroed');
    kfree(void(s));

    { === stringCopy === }
    s:= stringCopy('TEST');
    Assert(stringEquals(s, 'TEST'), 'stringCopy basic');
    Assert(stringSize(s) = 4, 'stringCopy size');
    kfree(void(s));
    s:= stringCopy('');
    Assert(stringSize(s) = 0, 'stringCopy empty');
    kfree(void(s));

    { === stringEquals === }
    Assert(stringEquals('ABC', 'ABC') = true, 'stringEquals same');
    Assert(stringEquals('ABC', 'ABD') = false, 'stringEquals diff char');
    Assert(stringEquals('ABC', 'AB') = false, 'stringEquals diff len');
    Assert(stringEquals('', '') = true, 'stringEquals both empty');
    Assert(stringEquals('A', '') = false, 'stringEquals one empty');
    Assert(stringEquals('', 'A') = false, 'stringEquals other empty');

    { === stringToUpper === }
    s:= stringToUpper('hello');
    Assert(stringEquals(s, 'HELLO'), 'stringToUpper basic');
    kfree(void(s));
    s:= stringToUpper('Hello123');
    Assert(stringEquals(s, 'HELLO123'), 'stringToUpper mixed');
    kfree(void(s));
    s:= stringToUpper('');
    Assert(stringSize(s) = 0, 'stringToUpper empty');
    kfree(void(s));
    s:= stringToUpper('ALREADY');
    Assert(stringEquals(s, 'ALREADY'), 'stringToUpper already upper');
    kfree(void(s));

    { === stringToLower === }
    s:= stringToLower('HELLO');
    Assert(stringEquals(s, 'hello'), 'stringToLower basic');
    kfree(void(s));
    s:= stringToLower('Hello123');
    Assert(stringEquals(s, 'hello123'), 'stringToLower mixed');
    kfree(void(s));
    s:= stringToLower('');
    Assert(stringSize(s) = 0, 'stringToLower empty');
    kfree(void(s));

    { === stringConcat === }
    s:= stringConcat('AB', 'CD');
    Assert(stringEquals(s, 'ABCD'), 'stringConcat basic');
    Assert(stringSize(s) = 4, 'stringConcat size');
    kfree(void(s));
    s:= stringConcat('', 'CD');
    Assert(stringEquals(s, 'CD'), 'stringConcat empty left');
    kfree(void(s));
    s:= stringConcat('AB', '');
    Assert(stringEquals(s, 'AB'), 'stringConcat empty right');
    kfree(void(s));
    s:= stringConcat('', '');
    Assert(stringSize(s) = 0, 'stringConcat both empty');
    kfree(void(s));

    { === stringTrim === }
    s:= stringTrim('HELLO', 3);
    Assert(stringEquals(s, 'HEL'), 'stringTrim basic');
    kfree(void(s));
    s:= stringTrim('HELLO', 5);
    Assert(stringEquals(s, 'HELLO'), 'stringTrim exact');
    kfree(void(s));
    s:= stringTrim('HELLO', 10);
    Assert(stringEquals(s, 'HELLO'), 'stringTrim over-length clamped');
    kfree(void(s));
    s:= stringTrim('HELLO', 0);
    Assert(stringSize(s) = 0, 'stringTrim zero');
    kfree(void(s));
    s:= stringTrim('', 5);
    Assert(stringSize(s) = 0, 'stringTrim empty str');
    kfree(void(s));

    { === stringSub === }
    s:= stringSub('HELLO', 1, 3);
    Assert(stringEquals(s, 'ELL'), 'stringSub basic');
    kfree(void(s));
    s:= stringSub('HELLO', 0, 5);
    Assert(stringEquals(s, 'HELLO'), 'stringSub full');
    kfree(void(s));
    s:= stringSub('HELLO', 4, 1);
    Assert(stringEquals(s, 'O'), 'stringSub last char');
    kfree(void(s));
    s:= stringSub('HELLO', 3, 10);
    Assert(stringEquals(s, 'LO'), 'stringSub over-length clamped');
    kfree(void(s));
    s:= stringSub('HELLO', 10, 2);
    Assert(stringSize(s) = 0, 'stringSub start past end');
    kfree(void(s));
    s:= stringSub('', 0, 5);
    Assert(stringSize(s) = 0, 'stringSub empty str');
    kfree(void(s));

    { === stringIndexOf === }
    Assert(stringIndexOf('HELLO WORLD', 'WORLD') = 6, 'stringIndexOf found');
    Assert(stringIndexOf('HELLO WORLD', 'HELLO') = 0, 'stringIndexOf at start');
    Assert(stringIndexOf('HELLO WORLD', 'D') = 10, 'stringIndexOf at end');
    Assert(stringIndexOf('HELLO WORLD', 'XYZ') = -1, 'stringIndexOf not found');
    Assert(stringIndexOf('HELLO', 'HELLO WORLD') = -1, 'stringIndexOf find longer than str');
    Assert(stringIndexOf('HELLO', '') = 0, 'stringIndexOf empty find');
    Assert(stringIndexOf('', 'A') = -1, 'stringIndexOf empty str');
    Assert(stringIndexOf('', '') = 0, 'stringIndexOf both empty');
    Assert(stringIndexOf('AABAA', 'AB') = 1, 'stringIndexOf mid-string');
    Assert(stringIndexOf('AAAA', 'AA') = 0, 'stringIndexOf overlapping');

    { === stringContains === }
    Assert(stringContains('HELLO WORLD', 'WORLD') = true, 'stringContains found');
    Assert(stringContains('HELLO WORLD', 'XYZ') = false, 'stringContains not found');
    Assert(stringContains('HELLO', 'HELLO') = true, 'stringContains exact match');
    Assert(stringContains('HELLO', '') = true, 'stringContains empty sub');
    Assert(stringContains('', '') = true, 'stringContains both empty');
    Assert(stringContains('', 'A') = false, 'stringContains empty str');
    Assert(stringContains('AB', 'ABC') = false, 'stringContains sub longer');

    { === stringReplace === }
    s:= stringReplace('HELLO WORLD', 'WORLD', 'EARTH');
    Assert(stringEquals(s, 'HELLO EARTH'), 'stringReplace basic');
    kfree(void(s));
    s:= stringReplace('HELLO WORLD', 'HELLO', 'HI');
    Assert(stringEquals(s, 'HI WORLD'), 'stringReplace at start');
    kfree(void(s));
    s:= stringReplace('HELLO WORLD', 'D', '!');
    Assert(stringEquals(s, 'HELLO WORL!'), 'stringReplace at end');
    kfree(void(s));
    s:= stringReplace('HELLO', 'XYZ', 'ABC');
    Assert(stringEquals(s, 'HELLO'), 'stringReplace not found');
    kfree(void(s));
    s:= stringReplace('AABAA', 'A', 'X');
    Assert(stringEquals(s, 'XABAA'), 'stringReplace first only');
    kfree(void(s));
    s:= stringReplace('HELLO', 'HELLO', '');
    Assert(stringSize(s) = 0, 'stringReplace to empty');
    kfree(void(s));
    s:= stringReplace('HELLO', 'L', 'LL');
    Assert(stringEquals(s, 'HELLLO'), 'stringReplace grow');
    kfree(void(s));
    s:= stringReplace('HELLO', 'LL', 'L');
    Assert(stringEquals(s, 'HELO'), 'stringReplace shrink');
    kfree(void(s));
    s:= stringReplace('', 'A', 'B');
    Assert(stringSize(s) = 0, 'stringReplace empty str');
    kfree(void(s));

    { === stringToInt === }
    Assert(stringToInt('0') = 0, 'stringToInt zero');
    Assert(stringToInt('123') = 123, 'stringToInt basic');
    Assert(stringToInt('999') = 999, 'stringToInt 999');
    Assert(stringToInt('1') = 1, 'stringToInt single digit');
    Assert(stringToInt('4294967295') = 4294967295, 'stringToInt max uint32');

    { === intToString === }
    s:= intToString(0);
    Assert(stringEquals(s, '0'), 'intToString zero');
    kfree(void(s));
    s:= intToString(1);
    Assert(stringEquals(s, '1'), 'intToString one');
    kfree(void(s));
    s:= intToString(123);
    Assert(stringEquals(s, '123'), 'intToString 123');
    kfree(void(s));
    s:= intToString(999);
    Assert(stringEquals(s, '999'), 'intToString 999');
    kfree(void(s));
    s:= intToString(10);
    Assert(stringEquals(s, '10'), 'intToString 10');
    kfree(void(s));
    s:= intToString(100);
    Assert(stringEquals(s, '100'), 'intToString 100');
    kfree(void(s));

    { === intToString / stringToInt roundtrip === }
    s:= intToString(42);
    Assert(stringToInt(s) = 42, 'roundtrip 42');
    kfree(void(s));
    s:= intToString(0);
    Assert(stringToInt(s) = 0, 'roundtrip 0');
    kfree(void(s));

    { === hexStringToInt === }
    Assert(hexStringToInt('FF') = 255, 'hexStringToInt FF');
    Assert(hexStringToInt('0') = 0, 'hexStringToInt 0');
    Assert(hexStringToInt('10') = 16, 'hexStringToInt 10');
    Assert(hexStringToInt('DEADBEEF') = $DEADBEEF, 'hexStringToInt DEADBEEF');
    Assert(hexStringToInt('') = 0, 'hexStringToInt empty');

    { === boolToString === }
    s:= boolToString(true, true);
    Assert(stringEquals(s, 'true'), 'boolToString true ext');
    kfree(void(s));
    s:= boolToString(false, true);
    Assert(stringEquals(s, 'false'), 'boolToString false ext');
    kfree(void(s));
    s:= boolToString(true, false);
    Assert(stringEquals(s, '1'), 'boolToString true short');
    kfree(void(s));
    s:= boolToString(false, false);
    Assert(stringEquals(s, '0'), 'boolToString false short');
    kfree(void(s));

    { === stringMatchAt === }
    Assert(stringMatchAt('HELLO', 0, 'HE') = true, 'stringMatchAt start');
    Assert(stringMatchAt('HELLO', 3, 'LO') = true, 'stringMatchAt mid');
    Assert(stringMatchAt('HELLO', 4, 'OX') = false, 'stringMatchAt past end');
    Assert(stringMatchAt('HELLO', 0, '') = true, 'stringMatchAt empty find');
    Assert(stringMatchAt('HELLO', 5, '') = true, 'stringMatchAt empty at end');
    Assert(stringMatchAt('', 0, 'A') = false, 'stringMatchAt empty str');
    Assert(stringMatchAt('', 0, '') = true, 'stringMatchAt both empty');

    { Print summary }
    PrintSummary;
end;

end.