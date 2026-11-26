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
    core.fmt.json - RFC 8259 compliant JSON parser, serializer, and accessor library.

    Provides a complete JSON implementation for parsing JSON text into an in-memory
    tree of TJSONValue nodes, serializing values back to JSON text, and navigating
    nested structures via dot/bracket path expressions.

    Numbers are stored as Double (64-bit IEEE 754). All six JSON value types are
    supported, plus a JSON_ERROR variant for parse error reporting. Unicode escape
    sequences (\uXXXX) are supported for codepoints U+0000-U+007F; higher codepoints
    are emitted as '?' since the OS is ASCII-only.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit core.fmt.json;

interface

uses
    memory.heap,
    core.strings,
    core.ds.lists,
    core.ds.hashmap;

type
    TJSONType = (
        JSON_NULL,
        JSON_BOOL,
        JSON_NUMBER,
        JSON_STRING,
        JSON_ARRAY,
        JSON_OBJECT,
        JSON_ERROR
    );

    PJSONValue = ^TJSONValue;
    TJSONValue = record
        Kind : TJSONType;
        case TJSONType of
            JSON_BOOL:   (boolVal   : boolean);
            JSON_NUMBER: (numberVal : Double);
            JSON_STRING: (stringVal : pchar);
            JSON_ARRAY:  (arrayVal  : PDList);
            JSON_OBJECT: (objectVal : PHashMap);
            JSON_ERROR:  (errPos    : uint32;
                          errMsg    : pchar);
    end;

{ --- Parsing --- }
function  parse(buf : pchar; len : uint32) : PJSONValue;

{ --- Direct accessors --- }
function  getType(val : PJSONValue) : TJSONType;
function  getBool(val : PJSONValue) : boolean;
function  getNumber(val : PJSONValue) : Double;
function  getString(val : PJSONValue) : pchar;
function  getArraySize(val : PJSONValue) : uint32;
function  getArrayItem(val : PJSONValue; idx : uint32) : PJSONValue;
function  getObjectItem(val : PJSONValue; key : pchar) : PJSONValue;

{ --- Path accessors --- }
function  getByPath(root : PJSONValue; path : pchar) : PJSONValue;
function  getStringByPath(root : PJSONValue; path : pchar; default : pchar) : pchar;
function  getNumberByPath(root : PJSONValue; path : pchar; default : Double) : Double;
function  getBoolByPath(root : PJSONValue; path : pchar; default : boolean) : boolean;
function  getObjectByPath(root : PJSONValue; path : pchar) : PJSONValue;
function  getArrayByPath(root : PJSONValue; path : pchar) : PJSONValue;

{ --- Builders --- }
function  newNull : PJSONValue;
function  newBool(b : boolean) : PJSONValue;
function  newNumber(n : Double) : PJSONValue;
function  newString(s : pchar) : PJSONValue;
function  newArray : PJSONValue;
function  newObject : PJSONValue;

{ --- Mutation --- }
procedure arrayAppend(arr : PJSONValue; item : PJSONValue);
procedure objectSet(obj : PJSONValue; key : pchar; item : PJSONValue);

{ --- Serialization --- }
function  stringify(val : PJSONValue) : pchar;

{ --- Cleanup --- }
procedure freeValue(val : PJSONValue);

{ --- Tests --- }
procedure UnitTest;

implementation

uses
    core.util,
    io.syslog,
    test.harness;

{ ============================================================================ }
{                            Forward Declarations                              }
{ ============================================================================ }

type
    PPJSONValue = ^PJSONValue;
    PJSONParser = ^TJSONParser;
    TJSONParser = record
        buf    : pchar;
        len    : uint32;
        pos    : uint32;
        hasErr : boolean;
        errPos : uint32;
        errMsg : pchar;
    end;

function  parseValue(var p : TJSONParser) : PJSONValue; forward;

{ ============================================================================ }
{                            Parser Helpers                                    }
{ ============================================================================ }

procedure setError(var p : TJSONParser; msg : pchar);
begin
    if p.hasErr then exit;
    p.hasErr:= true;
    p.errPos:= p.pos;
    p.errMsg:= stringCopy(msg);
end;

function makeError(var p : TJSONParser) : PJSONValue;
var
    result : PJSONValue;
begin
    result:= PJSONValue(kalloc(sizeof(TJSONValue)));
    result^.Kind:= JSON_ERROR;
    result^.errPos:= p.errPos;
    result^.errMsg:= p.errMsg;
    { Transfer ownership of errMsg to the result - clear from parser }
    p.errMsg:= nil;
    makeError:= result;
end;

procedure skipWS(var p : TJSONParser);
begin
    while (p.pos < p.len) do begin
        case p.buf[p.pos] of
            ' ', char(9), char(10), char(13): inc(p.pos);
        else
            break;
        end;
    end;
end;

function isDigit(c : char) : boolean;
begin
    isDigit:= (c >= '0') and (c <= '9');
end;

function hexCharVal(c : char) : uint32;
begin
    if (c >= '0') and (c <= '9') then
        hexCharVal:= byte(c) - 48
    else if (c >= 'a') and (c <= 'f') then
        hexCharVal:= byte(c) - 87
    else if (c >= 'A') and (c <= 'F') then
        hexCharVal:= byte(c) - 55
    else
        hexCharVal:= 0;
end;

function hexDigitChar(v : uint32) : char;
begin
    if v < 10 then
        hexDigitChar:= char(v + 48)
    else
        hexDigitChar:= char(v - 10 + 97);
end;

{ Compute 10^exp as a Double. }
function pow10(exp : sint32) : Double;
var
    result : Double;
    i      : sint32;
begin
    result:= 1.0;
    if exp >= 0 then begin
        for i:= 1 to exp do
            result:= result * 10.0;
    end else begin
        for i:= 1 to -exp do
            result:= result / 10.0;
    end;
    pow10:= result;
end;

{ ============================================================================ }
{                           Cleanup Helpers                                    }
{ ============================================================================ }

{ Callback for hashmap.forEach - frees each JSON value stored in the map. }
procedure freeObjectEntryCb(key: pchar; data: void; ud: void);
begin
    freeValue(PJSONValue(data));
end;

{ Walk the hashmap internal structure and free all nodes, keys, and the table.
  Values must already have been freed via forEach before calling this. }
procedure freeHashMapStructure(map : PHashMap);
var
    i    : uint32;
    item : PHashItem;
    next : PHashItem;
begin
    if map = nil then exit;
    for i:= 0 to map^.Size - 1 do begin
        item:= map^.Table[i];
        while item <> nil do begin
            next:= item^.Next;
            if item^.Key <> nil then kfree(void(item^.Key));
            kfree(void(item));
            item:= next;
        end;
    end;
    kfree(void(map^.Table));
    kfree(void(map));
end;

procedure freeValue(val : PJSONValue);
var
    i   : uint32;
begin
    if val = nil then exit;
    case val^.Kind of
        JSON_STRING: begin
            if val^.stringVal <> nil then
                kfree(void(val^.stringVal));
        end;
        JSON_ARRAY: begin
            if val^.arrayVal <> nil then begin
                i:= 0;
                while i < DL_Size(val^.arrayVal) do begin
                    freeValue(getArrayItem(val, i));
                    inc(i);
                end;
                DL_Free(val^.arrayVal);
            end;
        end;
        JSON_OBJECT: begin
            if val^.objectVal <> nil then begin
                { Free all values first }
                core.ds.hashmap.forEach(val^.objectVal, @freeObjectEntryCb, nil);
                { Free the hashmap structure (nodes, keys, table, record) }
                freeHashMapStructure(val^.objectVal);
            end;
        end;
        JSON_ERROR: begin
            if val^.errMsg <> nil then
                kfree(void(val^.errMsg));
        end;
    end;
    kfree(void(val));
end;

{ ============================================================================ }
{                              Parser                                          }
{ ============================================================================ }

function parseStringContent(var p : TJSONParser) : pchar;
var
    start, endPos, outPos : uint32;
    result : pchar;
    hex    : uint32;
    j      : uint32;
begin
    parseStringContent:= nil;

    if (p.pos >= p.len) or (p.buf[p.pos] <> '"') then begin
        setError(p, 'Expected opening quote');
        exit;
    end;
    inc(p.pos); { skip opening quote }

    { Find closing quote - skip over escaped characters }
    start:= p.pos;
    endPos:= p.pos;
    while endPos < p.len do begin
        if p.buf[endPos] = '"' then break;
        if p.buf[endPos] = '\' then inc(endPos); { skip the char after backslash }
        inc(endPos);
    end;
    if endPos >= p.len then begin
        setError(p, 'Unterminated string');
        exit;
    end;

    { Allocate worst-case size (escapes only shrink the output) }
    result:= stringNew(endPos - start);
    outPos:= 0;

    { Process characters with escape handling }
    while p.pos < endPos do begin
        if p.buf[p.pos] = '\' then begin
            inc(p.pos);
            if p.pos >= endPos then begin
                setError(p, 'Unterminated escape sequence');
                kfree(void(result));
                parseStringContent:= nil;
                exit;
            end;
            case p.buf[p.pos] of
                '"':  begin result[outPos]:= '"';      inc(outPos); end;
                '\':  begin result[outPos]:= '\';      inc(outPos); end;
                '/':  begin result[outPos]:= '/';      inc(outPos); end;
                'b':  begin result[outPos]:= char(8);  inc(outPos); end;
                'f':  begin result[outPos]:= char(12); inc(outPos); end;
                'n':  begin result[outPos]:= char(10); inc(outPos); end;
                'r':  begin result[outPos]:= char(13); inc(outPos); end;
                't':  begin result[outPos]:= char(9);  inc(outPos); end;
                'u':  begin
                    { Parse 4 hex digits }
                    if p.pos + 4 >= endPos then begin
                        setError(p, 'Incomplete \u escape');
                        kfree(void(result));
                        parseStringContent:= nil;
                        exit;
                    end;
                    hex:= 0;
                    for j:= 1 to 4 do begin
                        inc(p.pos);
                        hex:= (hex shl 4) or hexCharVal(p.buf[p.pos]);
                    end;
                    { Emit ASCII byte or replacement character }
                    if hex <= $7F then
                        result[outPos]:= char(hex)
                    else
                        result[outPos]:= '?';
                    inc(outPos);
                end;
            else
                setError(p, 'Invalid escape sequence');
                kfree(void(result));
                parseStringContent:= nil;
                exit;
            end;
        end else begin
            result[outPos]:= p.buf[p.pos];
            inc(outPos);
        end;
        inc(p.pos);
    end;

    inc(p.pos); { skip closing quote }
    parseStringContent:= result;
end;

function parseString(var p : TJSONParser) : PJSONValue;
var
    s      : pchar;
    result : PJSONValue;
begin
    parseString:= nil;
    s:= parseStringContent(p);
    if p.hasErr then exit;
    result:= PJSONValue(kalloc(sizeof(TJSONValue)));
    result^.Kind:= JSON_STRING;
    result^.stringVal:= s;
    parseString:= result;
end;

function parseNumber(var p : TJSONParser) : PJSONValue;
var
    result  : PJSONValue;
    d       : Double;
    neg     : boolean;
    fracDiv : Double;
    expVal  : sint32;
    expNeg  : boolean;
begin
    parseNumber:= nil;
    neg:= false;

    { Optional leading minus }
    if (p.pos < p.len) and (p.buf[p.pos] = '-') then begin
        neg:= true;
        inc(p.pos);
        if (p.pos >= p.len) or (not isDigit(p.buf[p.pos])) then begin
            setError(p, 'Expected digit after minus');
            exit;
        end;
    end;

    { Integer part }
    d:= 0.0;
    if (p.pos < p.len) and (p.buf[p.pos] = '0') then begin
        inc(p.pos);
        { Leading zeros are not permitted per RFC 8259 }
        if (p.pos < p.len) and isDigit(p.buf[p.pos]) then begin
            setError(p, 'Leading zeros not allowed');
            exit;
        end;
    end else begin
        if (p.pos >= p.len) or (not isDigit(p.buf[p.pos])) then begin
            setError(p, 'Expected digit');
            exit;
        end;
        while (p.pos < p.len) and isDigit(p.buf[p.pos]) do begin
            d:= d * 10.0 + (byte(p.buf[p.pos]) - 48);
            inc(p.pos);
        end;
    end;

    { Optional fractional part }
    if (p.pos < p.len) and (p.buf[p.pos] = '.') then begin
        inc(p.pos);
        if (p.pos >= p.len) or (not isDigit(p.buf[p.pos])) then begin
            setError(p, 'Expected digit after decimal point');
            exit;
        end;
        fracDiv:= 10.0;
        while (p.pos < p.len) and isDigit(p.buf[p.pos]) do begin
            d:= d + (byte(p.buf[p.pos]) - 48) / fracDiv;
            fracDiv:= fracDiv * 10.0;
            inc(p.pos);
        end;
    end;

    { Optional exponent }
    if (p.pos < p.len) and ((p.buf[p.pos] = 'e') or (p.buf[p.pos] = 'E')) then begin
        inc(p.pos);
        expNeg:= false;
        if (p.pos < p.len) and ((p.buf[p.pos] = '+') or (p.buf[p.pos] = '-')) then begin
            expNeg:= (p.buf[p.pos] = '-');
            inc(p.pos);
        end;
        if (p.pos >= p.len) or (not isDigit(p.buf[p.pos])) then begin
            setError(p, 'Expected digit in exponent');
            exit;
        end;
        expVal:= 0;
        while (p.pos < p.len) and isDigit(p.buf[p.pos]) do begin
            expVal:= expVal * 10 + (byte(p.buf[p.pos]) - 48);
            inc(p.pos);
        end;
        if expNeg then expVal:= -expVal;
        d:= d * pow10(expVal);
    end;

    if neg then d:= -d;

    result:= PJSONValue(kalloc(sizeof(TJSONValue)));
    result^.Kind:= JSON_NUMBER;
    result^.numberVal:= d;
    parseNumber:= result;
end;

function parseLiteral(var p : TJSONParser) : PJSONValue;
var
    result : PJSONValue;
begin
    parseLiteral:= nil;

    if (p.pos + 4 <= p.len) and
       (p.buf[p.pos] = 't') and (p.buf[p.pos+1] = 'r') and
       (p.buf[p.pos+2] = 'u') and (p.buf[p.pos+3] = 'e') then begin
        result:= PJSONValue(kalloc(sizeof(TJSONValue)));
        result^.Kind:= JSON_BOOL;
        result^.boolVal:= true;
        inc(p.pos, 4);
        parseLiteral:= result;
    end
    else if (p.pos + 5 <= p.len) and
            (p.buf[p.pos] = 'f') and (p.buf[p.pos+1] = 'a') and
            (p.buf[p.pos+2] = 'l') and (p.buf[p.pos+3] = 's') and
            (p.buf[p.pos+4] = 'e') then begin
        result:= PJSONValue(kalloc(sizeof(TJSONValue)));
        result^.Kind:= JSON_BOOL;
        result^.boolVal:= false;
        inc(p.pos, 5);
        parseLiteral:= result;
    end
    else if (p.pos + 4 <= p.len) and
            (p.buf[p.pos] = 'n') and (p.buf[p.pos+1] = 'u') and
            (p.buf[p.pos+2] = 'l') and (p.buf[p.pos+3] = 'l') then begin
        result:= PJSONValue(kalloc(sizeof(TJSONValue)));
        result^.Kind:= JSON_NULL;
        inc(p.pos, 4);
        parseLiteral:= result;
    end
    else
        setError(p, 'Invalid literal');
end;

function appendChild(arr, item: PJSONValue): boolean;
var
    slot: PPJSONValue;
begin
    slot:= PPJSONValue(DL_Add(arr^.arrayVal));
    appendChild:= slot <> nil;
    if slot <> nil then slot^:= item;
end;

function parseArray(var p : TJSONParser) : PJSONValue;
var
    result : PJSONValue;
    item   : PJSONValue;
begin
    parseArray:= nil;
    inc(p.pos); { skip '[' }

    result:= newArray;
    if result = nil then begin
        setError(p, 'Cannot allocate JSON array');
        exit;
    end;

    skipWS(p);

    { Empty array }
    if (p.pos < p.len) and (p.buf[p.pos] = ']') then begin
        inc(p.pos);
        parseArray:= result;
        exit;
    end;

    while true do begin
        item:= parseValue(p);
        if p.hasErr then begin
            freeValue(result);
            exit;
        end;

        if not appendChild(result, item) then begin
            setError(p, 'Cannot grow JSON array');
            freeValue(item);
            freeValue(result);
            exit;
        end;

        skipWS(p);
        if p.pos >= p.len then begin
            setError(p, 'Unterminated array');
            freeValue(result);
            exit;
        end;

        if p.buf[p.pos] = ']' then begin
            inc(p.pos);
            break;
        end;

        if p.buf[p.pos] <> ',' then begin
            setError(p, 'Expected "," or "]" in array');
            freeValue(result);
            exit;
        end;
        inc(p.pos); { skip ',' }
    end;

    parseArray:= result;
end;

function parseObject(var p : TJSONParser) : PJSONValue;
var
    result : PJSONValue;
    key    : pchar;
    val    : PJSONValue;
begin
    parseObject:= nil;
    inc(p.pos); // skip opening brace

    result:= PJSONValue(kalloc(sizeof(TJSONValue)));
    result^.Kind:= JSON_OBJECT;
    result^.objectVal:= core.ds.hashmap.new;

    skipWS(p);

    // Empty object
    if (p.pos < p.len) and (p.buf[p.pos] = #125) then begin
        inc(p.pos);
        parseObject:= result;
        exit;
    end;

    while true do begin
        skipWS(p);

        { Key must be a string }
        if (p.pos >= p.len) or (p.buf[p.pos] <> '"') then begin
            setError(p, 'Expected string key in object');
            freeValue(result);
            exit;
        end;

        key:= parseStringContent(p);
        if p.hasErr then begin
            freeValue(result);
            exit;
        end;

        skipWS(p);

        { Expect colon }
        if (p.pos >= p.len) or (p.buf[p.pos] <> ':') then begin
            setError(p, 'Expected ":" after object key');
            kfree(void(key));
            freeValue(result);
            exit;
        end;
        inc(p.pos); { skip ':' }

        { Value }
        val:= parseValue(p);
        if p.hasErr then begin
            kfree(void(key));
            freeValue(result);
            exit;
        end;

        { Store in hashmap - hashmap.add copies the key }
        core.ds.hashmap.add(result^.objectVal, key, void(val));
        kfree(void(key));

        skipWS(p);

        if p.pos >= p.len then begin
            setError(p, 'Unterminated object');
            freeValue(result);
            exit;
        end;

        if p.buf[p.pos] = #125 then begin
            inc(p.pos);
            break;
        end;

        if p.buf[p.pos] <> ',' then begin
            setError(p, 'Expected comma or closing brace in object');
            freeValue(result);
            exit;
        end;
        inc(p.pos); { skip ',' }
    end;

    parseObject:= result;
end;

function parseValue(var p : TJSONParser) : PJSONValue;
begin
    parseValue:= nil;
    if p.hasErr then exit;

    skipWS(p);

    if p.pos >= p.len then begin
        setError(p, 'Unexpected end of input');
        exit;
    end;

    case p.buf[p.pos] of
        '"':           parseValue:= parseString(p);
        #123:          parseValue:= parseObject(p);
        '[':           parseValue:= parseArray(p);
        't', 'f', 'n': parseValue:= parseLiteral(p);
        '-':           parseValue:= parseNumber(p);
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
                       parseValue:= parseNumber(p);
    else
        setError(p, 'Unexpected character');
    end;
end;

{ ============================================================================ }
{                          Top-Level Parse                                     }
{ ============================================================================ }

function parse(buf : pchar; len : uint32) : PJSONValue;
var
    p      : TJSONParser;
    result : PJSONValue;
begin
    p.buf:= buf;
    p.len:= len;
    p.pos:= 0;
    p.hasErr:= false;
    p.errPos:= 0;
    p.errMsg:= nil;

    result:= parseValue(p);

    if p.hasErr then begin
        { Clean up any partial result }
        if result <> nil then freeValue(result);
        parse:= makeError(p);
        exit;
    end;

    { Ensure no trailing non-whitespace content }
    skipWS(p);
    if p.pos < p.len then begin
        setError(p, 'Unexpected content after value');
        if result <> nil then freeValue(result);
        parse:= makeError(p);
        exit;
    end;

    parse:= result;
end;

{ ============================================================================ }
{                          Direct Accessors                                    }
{ ============================================================================ }

function getType(val : PJSONValue) : TJSONType;
begin
    if val = nil then
        getType:= JSON_NULL
    else
        getType:= val^.Kind;
end;

function getBool(val : PJSONValue) : boolean;
begin
    getBool:= false;
    if (val <> nil) and (val^.Kind = JSON_BOOL) then
        getBool:= val^.boolVal;
end;

function getNumber(val : PJSONValue) : Double;
begin
    getNumber:= 0.0;
    if (val <> nil) and (val^.Kind = JSON_NUMBER) then
        getNumber:= val^.numberVal;
end;

function getString(val : PJSONValue) : pchar;
begin
    getString:= nil;
    if (val <> nil) and (val^.Kind = JSON_STRING) then
        getString:= val^.stringVal;
end;

function getArraySize(val : PJSONValue) : uint32;
begin
    getArraySize:= 0;
    if (val <> nil) and (val^.Kind = JSON_ARRAY) and (val^.arrayVal <> nil) then
        getArraySize:= DL_Size(val^.arrayVal);
end;

function getArrayItem(val : PJSONValue; idx : uint32) : PJSONValue;
var
    slot : PPJSONValue;
begin
    getArrayItem:= nil;
    if (val <> nil) and (val^.Kind = JSON_ARRAY) and (val^.arrayVal <> nil) then begin
        slot:= PPJSONValue(DL_Get(val^.arrayVal, idx));
        if slot <> nil then getArrayItem:= slot^;
    end;
end;

function getObjectItem(val : PJSONValue; key : pchar) : PJSONValue;
begin
    getObjectItem:= nil;
    if (val <> nil) and (val^.Kind = JSON_OBJECT) and (val^.objectVal <> nil) then
        getObjectItem:= PJSONValue(core.ds.hashmap.get(val^.objectVal, key));
end;

{ ============================================================================ }
{                          Path Accessors                                      }
{ ============================================================================ }

function getByPath(root : PJSONValue; path : pchar) : PJSONValue;
var
    current  : PJSONValue;
    pathLen  : uint32;
    pos      : uint32;
    segStart : uint32;
    segLen   : uint32;
    key      : pchar;
    idx      : uint32;
begin
    getByPath:= nil;
    if (root = nil) or (path = nil) then exit;

    current:= root;
    pathLen:= stringSize(path);
    pos:= 0;

    while (pos < pathLen) and (current <> nil) do begin
        { Skip dot separator (not at the start) }
        if (pos > 0) and (path[pos] = '.') then inc(pos);

        if (pos < pathLen) and (path[pos] = '[') then begin
            { Array index: [N] }
            inc(pos); { skip '[' }
            idx:= 0;
            while (pos < pathLen) and (path[pos] <> ']') do begin
                idx:= idx * 10 + (byte(path[pos]) - 48);
                inc(pos);
            end;
            if pos < pathLen then inc(pos); { skip ']' }

            current:= getArrayItem(current, idx);
        end else begin
            { Object key: segment until '.', '[', or end }
            segStart:= pos;
            while (pos < pathLen) and (path[pos] <> '.') and (path[pos] <> '[') do
                inc(pos);
            segLen:= pos - segStart;

            if (segLen = 0) or (current^.Kind <> JSON_OBJECT) then begin
                getByPath:= nil;
                exit;
            end;

            key:= stringSub(path, segStart, segLen);
            current:= PJSONValue(core.ds.hashmap.get(current^.objectVal, key));
            kfree(void(key));
        end;
    end;

    getByPath:= current;
end;

function getStringByPath(root : PJSONValue; path : pchar; default : pchar) : pchar;
var
    val : PJSONValue;
begin
    val:= getByPath(root, path);
    if (val <> nil) and (val^.Kind = JSON_STRING) then
        getStringByPath:= val^.stringVal
    else
        getStringByPath:= default;
end;

function getNumberByPath(root : PJSONValue; path : pchar; default : Double) : Double;
var
    val : PJSONValue;
begin
    val:= getByPath(root, path);
    if (val <> nil) and (val^.Kind = JSON_NUMBER) then
        getNumberByPath:= val^.numberVal
    else
        getNumberByPath:= default;
end;

function getBoolByPath(root : PJSONValue; path : pchar; default : boolean) : boolean;
var
    val : PJSONValue;
begin
    val:= getByPath(root, path);
    if (val <> nil) and (val^.Kind = JSON_BOOL) then
        getBoolByPath:= val^.boolVal
    else
        getBoolByPath:= default;
end;

function getObjectByPath(root : PJSONValue; path : pchar) : PJSONValue;
var
    val : PJSONValue;
begin
    val:= getByPath(root, path);
    if (val <> nil) and (val^.Kind = JSON_OBJECT) then
        getObjectByPath:= val
    else
        getObjectByPath:= nil;
end;

function getArrayByPath(root : PJSONValue; path : pchar) : PJSONValue;
var
    val : PJSONValue;
begin
    val:= getByPath(root, path);
    if (val <> nil) and (val^.Kind = JSON_ARRAY) then
        getArrayByPath:= val
    else
        getArrayByPath:= nil;
end;

{ ============================================================================ }
{                              Builders                                        }
{ ============================================================================ }

function newNull : PJSONValue;
var
    result : PJSONValue;
begin
    result:= PJSONValue(kalloc(sizeof(TJSONValue)));
    result^.Kind:= JSON_NULL;
    newNull:= result;
end;

function newBool(b : boolean) : PJSONValue;
var
    result : PJSONValue;
begin
    result:= PJSONValue(kalloc(sizeof(TJSONValue)));
    result^.Kind:= JSON_BOOL;
    result^.boolVal:= b;
    newBool:= result;
end;

function newNumber(n : Double) : PJSONValue;
var
    result : PJSONValue;
begin
    result:= PJSONValue(kalloc(sizeof(TJSONValue)));
    result^.Kind:= JSON_NUMBER;
    result^.numberVal:= n;
    newNumber:= result;
end;

function newString(s : pchar) : PJSONValue;
var
    result : PJSONValue;
begin
    result:= PJSONValue(kalloc(sizeof(TJSONValue)));
    result^.Kind:= JSON_STRING;
    result^.stringVal:= stringCopy(s);
    newString:= result;
end;

function newArray : PJSONValue;
var
    result : PJSONValue;
begin
    result:= PJSONValue(kalloc(sizeof(TJSONValue)));
    result^.Kind:= JSON_ARRAY;
    result^.arrayVal:= DL_New(sizeof(PJSONValue));
    if result^.arrayVal = nil then begin
        kfree(void(result));
        newArray:= nil;
        exit;
    end;
    newArray:= result;
end;

function newObject : PJSONValue;
var
    result : PJSONValue;
begin
    result:= PJSONValue(kalloc(sizeof(TJSONValue)));
    result^.Kind:= JSON_OBJECT;
    result^.objectVal:= core.ds.hashmap.new;
    newObject:= result;
end;

{ ============================================================================ }
{                              Mutation                                        }
{ ============================================================================ }

procedure arrayAppend(arr : PJSONValue; item : PJSONValue);
begin
    if (arr = nil) or (arr^.Kind <> JSON_ARRAY) or (arr^.arrayVal = nil) then exit;
    if not appendChild(arr, item) then freeValue(item);
end;

procedure objectSet(obj : PJSONValue; key : pchar; item : PJSONValue);
begin
    if (obj = nil) or (obj^.Kind <> JSON_OBJECT) or (obj^.objectVal = nil) then exit;
    core.ds.hashmap.add(obj^.objectVal, key, void(item));
end;

{ ============================================================================ }
{                           Serialization                                      }
{ ============================================================================ }

{ Escape a string and wrap it in double quotes for JSON output. }
function escapeAndQuote(s : pchar) : pchar;
var
    i, len, outLen : uint32;
    result : pchar;
    pos    : uint32;
    ch     : char;
begin
    if s = nil then begin
        escapeAndQuote:= stringCopy('""');
        exit;
    end;

    len:= stringSize(s);

    { First pass: compute output length }
    outLen:= 2; { opening and closing quotes }
    for i:= 0 to len - 1 do begin
        ch:= s[i];
        if (ch = '"') or (ch = '\') then
            inc(outLen, 2)
        else if (ch = char(8)) or (ch = char(9)) or (ch = char(10)) or
                (ch = char(12)) or (ch = char(13)) then
            inc(outLen, 2)
        else if byte(ch) < 32 then
            inc(outLen, 6) { \uXXXX }
        else
            inc(outLen);
    end;

    result:= stringNew(outLen);
    result[0]:= '"';
    pos:= 1;

    { Second pass: write escaped content }
    for i:= 0 to len - 1 do begin
        ch:= s[i];
        if ch = '"' then begin
            result[pos]:= '\'; result[pos+1]:= '"'; inc(pos, 2);
        end
        else if ch = '\' then begin
            result[pos]:= '\'; result[pos+1]:= '\'; inc(pos, 2);
        end
        else if ch = char(8) then begin
            result[pos]:= '\'; result[pos+1]:= 'b'; inc(pos, 2);
        end
        else if ch = char(9) then begin
            result[pos]:= '\'; result[pos+1]:= 't'; inc(pos, 2);
        end
        else if ch = char(10) then begin
            result[pos]:= '\'; result[pos+1]:= 'n'; inc(pos, 2);
        end
        else if ch = char(12) then begin
            result[pos]:= '\'; result[pos+1]:= 'f'; inc(pos, 2);
        end
        else if ch = char(13) then begin
            result[pos]:= '\'; result[pos+1]:= 'r'; inc(pos, 2);
        end
        else if byte(ch) < 32 then begin
            result[pos]:= '\'; result[pos+1]:= 'u';
            result[pos+2]:= '0'; result[pos+3]:= '0';
            result[pos+4]:= hexDigitChar(byte(ch) shr 4);
            result[pos+5]:= hexDigitChar(byte(ch) and $F);
            inc(pos, 6);
        end
        else begin
            result[pos]:= ch;
            inc(pos);
        end;
    end;

    result[pos]:= '"';
    escapeAndQuote:= result;
end;

type
    PStringifyState = ^TStringifyState;
    TStringifyState = record
        result : pchar;
        first  : boolean;
    end;

{ forEach callback for serializing object entries. }
procedure stringifyObjectEntryCb(key: pchar; data: void; ud: void);
var
    state   : PStringifyState;
    valStr  : pchar;
    keyStr  : pchar;
    tmp     : pchar;
begin
    state:= PStringifyState(ud);

    if not state^.first then begin
        tmp:= stringConcat(state^.result, ',');
        kfree(void(state^.result));
        state^.result:= tmp;
    end;
    state^.first:= false;

    { Key }
    keyStr:= escapeAndQuote(key);
    tmp:= stringConcat(state^.result, keyStr);
    kfree(void(state^.result));
    kfree(void(keyStr));
    state^.result:= tmp;

    { Colon }
    tmp:= stringConcat(state^.result, ':');
    kfree(void(state^.result));
    state^.result:= tmp;

    { Value }
    valStr:= stringify(PJSONValue(data));
    tmp:= stringConcat(state^.result, valStr);
    kfree(void(state^.result));
    kfree(void(valStr));
    state^.result:= tmp;
end;

function stringify(val : PJSONValue) : pchar;
var
    result : pchar;
    tmp    : pchar;
    valStr : pchar;
    i      : uint32;
    state  : TStringifyState;
begin
    if val = nil then begin
        stringify:= stringCopy('null');
        exit;
    end;

    case val^.Kind of
        JSON_NULL:
            stringify:= stringCopy('null');

        JSON_BOOL: begin
            if val^.boolVal then
                stringify:= stringCopy('true')
            else
                stringify:= stringCopy('false');
        end;

        JSON_NUMBER:
            stringify:= doubleToStr(val^.numberVal);

        JSON_STRING:
            stringify:= escapeAndQuote(val^.stringVal);

        JSON_ARRAY: begin
            result:= stringCopy('[');
            if val^.arrayVal <> nil then begin
                i:= 0;
                while i < DL_Size(val^.arrayVal) do begin
                    if i > 0 then begin
                        tmp:= stringConcat(result, ',');
                        kfree(void(result));
                        result:= tmp;
                    end;
                    valStr:= stringify(getArrayItem(val, i));
                    tmp:= stringConcat(result, valStr);
                    kfree(void(result));
                    kfree(void(valStr));
                    result:= tmp;
                    inc(i);
                end;
            end;
            tmp:= stringConcat(result, ']');
            kfree(void(result));
            stringify:= tmp;
        end;

        JSON_OBJECT: begin
            state.result:= stringCopy(#123);
            state.first:= true;
            if val^.objectVal <> nil then
                core.ds.hashmap.forEach(val^.objectVal, @stringifyObjectEntryCb, @state);
            tmp:= stringConcat(state.result, #125);
            kfree(void(state.result));
            stringify:= tmp;
        end;

        JSON_ERROR:
            stringify:= stringCopy('null');
    else
        stringify:= stringCopy('null');
    end;
end;

{ ============================================================================ }
{                              Unit Tests                                      }
{ ============================================================================ }

procedure UnitTest;
var
    context : TTestContext;
    v, v2  : PJSONValue;
    s      : pchar;
    passed : uint32;
    failed : uint32;

begin
    passed:= 0;
    failed:= 0;
    test.harness.Start(@context, 'core.fmt.json');

    { === Literals === }
    v:= parse('null', 4);
    test.harness.Assert(@context, v^.Kind = JSON_NULL, 'parse null');
    freeValue(v);

    v:= parse('true', 4);
    test.harness.Assert(@context, v^.Kind = JSON_BOOL, 'parse true kind');
    test.harness.Assert(@context, getBool(v) = true, 'parse true value');
    freeValue(v);

    v:= parse('false', 5);
    test.harness.Assert(@context, v^.Kind = JSON_BOOL, 'parse false kind');
    test.harness.Assert(@context, getBool(v) = false, 'parse false value');
    freeValue(v);

    { === Numbers === }
    v:= parse('0', 1);
    test.harness.Assert(@context, v^.Kind = JSON_NUMBER, 'parse 0 kind');
    test.harness.Assert(@context, getNumber(v) = 0.0, 'parse 0 value');
    freeValue(v);

    v:= parse('42', 2);
    test.harness.Assert(@context, getNumber(v) = 42.0, 'parse 42');
    freeValue(v);

    v:= parse('-7', 2);
    test.harness.Assert(@context, getNumber(v) = -7.0, 'parse -7');
    freeValue(v);

    v:= parse('3.14', 4);
    test.harness.Assert(@context, v^.Kind = JSON_NUMBER, 'parse 3.14 kind');
    { Check approximate equality for floating point }
    test.harness.Assert(@context, (getNumber(v) > 3.139) and (getNumber(v) < 3.141), 'parse 3.14 value');
    freeValue(v);

    v:= parse('1e3', 3);
    test.harness.Assert(@context, getNumber(v) = 1000.0, 'parse 1e3');
    freeValue(v);

    v:= parse('2.5e2', 5);
    test.harness.Assert(@context, getNumber(v) = 250.0, 'parse 2.5e2');
    freeValue(v);

    v:= parse('1E-2', 4);
    test.harness.Assert(@context, (getNumber(v) > 0.009) and (getNumber(v) < 0.011), 'parse 1E-2');
    freeValue(v);

    { Leading zeros must be rejected }
    v:= parse('01', 2);
    test.harness.Assert(@context, v^.Kind = JSON_ERROR, 'reject leading zero');
    freeValue(v);

    { === Strings === }
    v:= parse('""', 2);
    test.harness.Assert(@context, v^.Kind = JSON_STRING, 'parse empty string kind');
    test.harness.Assert(@context, stringSize(getString(v)) = 0, 'parse empty string size');
    freeValue(v);

    v:= parse('"hello"', 7);
    test.harness.Assert(@context, stringEquals(getString(v), 'hello'), 'parse simple string');
    freeValue(v);

    v:= parse('"a\nb"', 6);
    test.harness.Assert(@context, getString(v)[1] = char(10), 'parse \n escape');
    freeValue(v);

    v:= parse('"a\tb"', 6);
    test.harness.Assert(@context, getString(v)[1] = char(9), 'parse \t escape');
    freeValue(v);

    v:= parse('"a\\b"', 6);
    test.harness.Assert(@context, getString(v)[1] = '\', 'parse \\ escape');
    freeValue(v);

    v:= parse('"a\"b"', 6);
    test.harness.Assert(@context, getString(v)[1] = '"', 'parse \" escape');
    freeValue(v);

    v:= parse('"\u0041"', 8);
    test.harness.Assert(@context, getString(v)[0] = 'A', 'parse \u0041 = A');
    freeValue(v);

    v:= parse('"\u00e9"', 8);
    test.harness.Assert(@context, getString(v)[0] = '?', 'parse \u00e9 = ? (non-ASCII)');
    freeValue(v);

    { === Arrays === }
    v:= parse('[]', 2);
    test.harness.Assert(@context, v^.Kind = JSON_ARRAY, 'parse empty array kind');
    test.harness.Assert(@context, getArraySize(v) = 0, 'parse empty array size');
    s:= stringify(v);
    test.harness.Assert(@context, stringEquals(s, '[]'), 'stringify empty array');
    kfree(void(s));
    freeValue(v);

    v:= parse('[1, 2, 3]', 9);
    test.harness.Assert(@context, getArraySize(v) = 3, 'parse array size 3');
    test.harness.Assert(@context, getNumber(getArrayItem(v, 0)) = 1.0, 'array[0]=1');
    test.harness.Assert(@context, getNumber(getArrayItem(v, 1)) = 2.0, 'array[1]=2');
    test.harness.Assert(@context, getNumber(getArrayItem(v, 2)) = 3.0, 'array[2]=3');
    freeValue(v);

    v:= parse('[true, "hi", null]', 18);
    test.harness.Assert(@context, getArraySize(v) = 3, 'mixed array size');
    test.harness.Assert(@context, getBool(getArrayItem(v, 0)) = true, 'mixed array[0]=true');
    test.harness.Assert(@context, stringEquals(getString(getArrayItem(v, 1)), 'hi'), 'mixed array[1]="hi"');
    test.harness.Assert(@context, getType(getArrayItem(v, 2)) = JSON_NULL, 'mixed array[2]=null');
    freeValue(v);

    { Nested arrays }
    v:= parse('[[1, 2], [3]]', 13);
    test.harness.Assert(@context, getArraySize(v) = 2, 'nested array outer size');
    test.harness.Assert(@context, getArraySize(getArrayItem(v, 0)) = 2, 'nested array[0] size');
    test.harness.Assert(@context, getNumber(getArrayItem(getArrayItem(v, 0), 1)) = 2.0, 'nested array[0][1]=2');
    freeValue(v);

    // === Objects ===
    v:= parse(#123#125, 2);
    test.harness.Assert(@context, v^.Kind = JSON_OBJECT, 'parse empty object kind');
    freeValue(v);

    v:= parse(#123'"a": 1, "b": 2'#125, 16);
    test.harness.Assert(@context, v^.Kind = JSON_OBJECT, 'parse object kind');
    test.harness.Assert(@context, getNumber(getObjectItem(v, 'a')) = 1.0, 'object["a"]=1');
    test.harness.Assert(@context, getNumber(getObjectItem(v, 'b')) = 2.0, 'object["b"]=2');
    test.harness.Assert(@context, getObjectItem(v, 'c') = nil, 'object["c"]=nil');
    freeValue(v);

    // Nested objects
    v:= parse(#123'"x": '#123'"y": 42'#125#125, 16);
    test.harness.Assert(@context, getNumber(getObjectItem(getObjectItem(v, 'x'), 'y')) = 42.0, 'nested obj x.y=42');
    freeValue(v);

    // === Path accessors ===
    v:= parse(#123'"a": '#123'"b": '#123'"c": 99'#125#125#125, 23);
    test.harness.Assert(@context, getNumberByPath(v, 'a.b.c', 0.0) = 99.0, 'path a.b.c=99');
    test.harness.Assert(@context, getByPath(v, 'a.b.z') = nil, 'path a.b.z=nil');
    test.harness.Assert(@context, getNumberByPath(v, 'a.b.z', -1.0) = -1.0, 'path default -1');
    freeValue(v);

    v:= parse(#123'"items": [10, 20, 30]'#125, 23);
    test.harness.Assert(@context, getNumberByPath(v, 'items[0]', 0.0) = 10.0, 'path items[0]=10');
    test.harness.Assert(@context, getNumberByPath(v, 'items[2]', 0.0) = 30.0, 'path items[2]=30');
    freeValue(v);

    v:= parse(#123'"a": ['#123'"b": "yes"'#125']'#125, 21);
    test.harness.Assert(@context, stringEquals(getStringByPath(v, 'a[0].b', ''), 'yes'), 'path a[0].b=yes');
    freeValue(v);

    v:= parse(#123'"debug": true'#125, 15);
    test.harness.Assert(@context, getBoolByPath(v, 'debug', false) = true, 'path bool true');
    test.harness.Assert(@context, getBoolByPath(v, 'missing', false) = false, 'path bool default');
    freeValue(v);

    // === Error handling ===
    v:= parse('', 0);
    test.harness.Assert(@context, v^.Kind = JSON_ERROR, 'error empty input');
    freeValue(v);

    v:= parse(#123, 1);
    test.harness.Assert(@context, v^.Kind = JSON_ERROR, 'error unterminated object');
    freeValue(v);

    v:= parse('[', 1);
    test.harness.Assert(@context, v^.Kind = JSON_ERROR, 'error unterminated array');
    freeValue(v);

    v:= parse('"hello', 6);
    test.harness.Assert(@context, v^.Kind = JSON_ERROR, 'error unterminated string');
    freeValue(v);

    v:= parse(#123'"a" 1'#125, 7);
    test.harness.Assert(@context, v^.Kind = JSON_ERROR, 'error missing colon');
    freeValue(v);

    v:= parse('tru', 3);
    test.harness.Assert(@context, v^.Kind = JSON_ERROR, 'error truncated literal');
    freeValue(v);

    v:= parse('1 2', 3);
    test.harness.Assert(@context, v^.Kind = JSON_ERROR, 'error trailing content');
    freeValue(v);

    { === Builders === }
    v:= newNull;
    test.harness.Assert(@context, v^.Kind = JSON_NULL, 'builder null');
    freeValue(v);

    v:= newBool(true);
    test.harness.Assert(@context, getBool(v) = true, 'builder bool true');
    freeValue(v);

    v:= newNumber(3.14);
    test.harness.Assert(@context, (getNumber(v) > 3.139) and (getNumber(v) < 3.141), 'builder number');
    freeValue(v);

    v:= newString('test');
    test.harness.Assert(@context, stringEquals(getString(v), 'test'), 'builder string');
    freeValue(v);

    v:= newArray;
    v2:= newNumber(1.0);
    arrayAppend(v, v2);
    test.harness.Assert(@context, getArrayItem(v, 0) = v2, 'array preserves child pointer');
    arrayAppend(v, newNumber(2.0));
    test.harness.Assert(@context, getArraySize(v) = 2, 'builder array size');
    test.harness.Assert(@context, getNumber(getArrayItem(v, 0)) = 1.0, 'builder array[0]');
    test.harness.Assert(@context, getNumber(getArrayItem(v, 1)) = 2.0, 'builder array[1]');
    freeValue(v);

    v:= newObject;
    objectSet(v, 'key', newString('val'));
    test.harness.Assert(@context, stringEquals(getString(getObjectItem(v, 'key')), 'val'), 'builder obj set/get');
    freeValue(v);

    { === Stringify === }
    v:= newNull;
    s:= stringify(v);
    freeValue(v);
    test.harness.Assert(@context, stringEquals(s, 'null'), 'stringify null');
    kfree(void(s));

    v:= newBool(true);
    s:= stringify(v);
    test.harness.Assert(@context, stringEquals(s, 'true'), 'stringify true');
    kfree(void(s));
    freeValue(v);

    v:= newNumber(42.0);
    s:= stringify(v);
    test.harness.Assert(@context, stringEquals(s, '42'), 'stringify 42');
    kfree(void(s));
    freeValue(v);

    v:= newString('hello');
    s:= stringify(v);
    test.harness.Assert(@context, stringEquals(s, '"hello"'), 'stringify string');
    kfree(void(s));
    freeValue(v);

    { Stringify with escape characters }
    v:= newString('a"b');
    s:= stringify(v);
    test.harness.Assert(@context, stringContains(s, '\"'), 'stringify escape quote');
    kfree(void(s));
    freeValue(v);

    { Stringify array }
    v:= newArray;
    arrayAppend(v, newNumber(1.0));
    arrayAppend(v, newNumber(2.0));
    s:= stringify(v);
    test.harness.Assert(@context, stringEquals(s, '[1,2]'), 'stringify array');
    kfree(void(s));
    freeValue(v);

    // Stringify object
    v:= newObject;
    objectSet(v, 'k', newNumber(1.0));
    s:= stringify(v);
    test.harness.Assert(@context, stringContains(s, '"k"'), 'stringify obj has key');
    test.harness.Assert(@context, stringContains(s, ':1'), 'stringify obj has value');
    kfree(void(s));
    freeValue(v);

    // === Round-trip: parse -> stringify -> parse ===
    v:= parse('[1, true, "hi", null]', 21);
    s:= stringify(v);
    v2:= parse(s, stringSize(s));
    test.harness.Assert(@context, v2^.Kind = JSON_ARRAY, 'roundtrip array kind');
    test.harness.Assert(@context, getArraySize(v2) = 4, 'roundtrip array size');
    test.harness.Assert(@context, getNumber(getArrayItem(v2, 0)) = 1.0, 'roundtrip array[0]');
    test.harness.Assert(@context, getBool(getArrayItem(v2, 1)) = true, 'roundtrip array[1]');
    test.harness.Assert(@context, stringEquals(getString(getArrayItem(v2, 2)), 'hi'), 'roundtrip array[2]');
    test.harness.Assert(@context, getType(getArrayItem(v2, 3)) = JSON_NULL, 'roundtrip array[3]');
    freeValue(v);
    freeValue(v2);
    kfree(void(s));

    // === freeValue smoke test on deeply nested structure ===
    v:= newObject;
    objectSet(v, 'arr', newArray);
    arrayAppend(getObjectItem(v, 'arr'), newObject);
    objectSet(getArrayItem(getObjectItem(v, 'arr'), 0), 'deep', newString('value'));
    test.harness.Assert(@context, stringEquals(getStringByPath(v, 'arr[0].deep', ''), 'value'), 'deep nested path');
    freeValue(v);

    // Print summary
    test.harness.finish(@context);
end;

end.
