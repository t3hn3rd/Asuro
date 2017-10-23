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

implementation

function stringToUpper(str : pchar) : pchar;
begin
    
end;

function stringToLower(str : pchar) : pchar;
begin
    
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
begin
    
end;

function stringContains(str : pchar; sub : pchar) : boolean;
begin
    
end;

end.