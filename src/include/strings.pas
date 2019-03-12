{ 
	Include->Strings - String Manipulation.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit strings;

interface

uses 
    util, 
    lmemorymanager;

function stringToUpper(str : pchar) : pchar;
function stringToLower(str : pchar) : pchar;
function stringEquals(str1, str2 : pchar) : boolean;
function stringCopy(str : pchar) : pchar;
function stringNew(size : uint32) : pchar;
function stringSize(str : pchar) : uint32;
function stringConcat(str1, str2 : pchar) : pchar;
function stringContains(str : pchar; sub : pchar) : boolean;
function stringToInt(str : pchar) : uint32;
function hexStringToInt(str : pchar) : uint32;
function intToString(i : uint32) : pchar;
function boolToString(b : boolean; ext : boolean) : pchar;

implementation

uses
    console;

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

function stringContains(str : pchar; sub : pchar) : boolean;
begin
    stringContains:= false;    
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
begin
    intToString:= ' ';
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