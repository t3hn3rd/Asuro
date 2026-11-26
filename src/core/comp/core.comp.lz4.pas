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

{ Raw LZ4 block. Disjoint caller-owned buffers. On failure written is zero. }
unit core.comp.lz4;

interface

function compress(src : puint8; size : uint32; dst : puint8; capacity : uint32;
                  var written : uint32) : boolean;
function decompress(src : puint8; size : uint32; dst : puint8; capacity : uint32;
                    var written : uint32) : boolean;
procedure UnitTest;

implementation

uses
    memory.heap,
    core.comp.match,
    test.harness;

function compress(src : puint8; size : uint32; dst : puint8; capacity : uint32;
                  var written : uint32) : boolean;
var table : PMatchTable;
    pos, anchor, output, distance, length : uint32;

    function extension(count : uint32) : boolean;
    begin
        extension := false;
        if count >= 15 then begin
            dec(count,15);
            while count >= 255 do begin
                if output = capacity then exit;
                dst[output] := 255;
                inc(output);
                dec(count,255);
            end;
            if output = capacity then exit;
            dst[output] := count;
            inc(output);
        end;
        extension := true;
    end;

    function sequence(matchLength : uint32) : boolean;
    var literals, token, nibble : uint32;
    begin
        sequence := false;
        if output = capacity then exit;
        literals := pos - anchor;
        token := literals;
        if token > 15 then token := 15;
        nibble := 0;
        if matchLength <> 0 then nibble := matchLength - 4;
        if nibble > 15 then nibble := 15;
        dst[output] := (token shl 4) or nibble;
        inc(output);
        if not extension(literals) then exit;
        if literals > capacity - output then exit;
        while anchor < pos do begin
            dst[output] := src[anchor];
            inc(anchor);
            inc(output);
        end;
        if matchLength <> 0 then begin
            if capacity - output < 2 then exit;
            dst[output] := uint8(distance);
            dst[output+1] := distance shr 8;
            inc(output,2);
            if not extension(matchLength - 4) then exit;
        end;
        sequence := true;
    end;

begin
    written := 0;
    compress := false;
    if ((src = nil) and (size <> 0)) or (dst = nil) then exit;
    table := PMatchTable(kalloc(sizeof(TMatchTable)));
    if table = nil then exit;
    pos := 0;
    anchor := 0;
    output := 0;
    while size - pos >= 12 do begin
        length := findMatch(table,src,pos,size-pos-5,65535,distance);
        if length >= 4 then begin
            if not sequence(length) then begin
                kfree(void(table));
                exit;
            end;
            inc(pos,length);
            anchor := pos;
        end else inc(pos);
    end;
    pos := size;
    compress := sequence(0);
    if compress then written := output;
    kfree(void(table));
end;

function decompress(src : puint8; size : uint32; dst : puint8; capacity : uint32;
                    var written : uint32) : boolean;
var pos, output, token, length, distance : uint32;

    function readLength(nibble : uint32) : boolean;
    var extra : uint32;
    begin
        readLength := false;
        length := nibble;
        if nibble = 15 then repeat
            if pos = size then exit;
            extra := src[pos];
            inc(pos);
            if length > $FFFFFFFF - extra then exit;
            inc(length,extra);
        until extra < 255;
        readLength := true;
    end;

begin
    written := 0;
    decompress := false;
    if (src = nil) or ((dst = nil) and (capacity <> 0)) then exit;
    pos := 0;
    output := 0;
    while pos < size do begin
        token := src[pos];
        inc(pos);
        if not readLength(token shr 4) then exit;
        if (length > size-pos) or (length > capacity-output) then exit;
        while length <> 0 do begin
            dst[output] := src[pos];
            inc(pos);
            inc(output);
            dec(length);
        end;
        if pos = size then begin
            written := output;
            decompress := true;
            exit;
        end;
        if size-pos < 2 then exit;
        distance := src[pos] or (uint32(src[pos+1]) shl 8);
        inc(pos,2);
        if (distance = 0) or (distance > output) then exit;
        if not readLength(token and 15) then exit;
        if (capacity-output < 4) or (length > capacity-output-4) then exit;
        inc(length,4);
        while length <> 0 do begin
            dst[output] := dst[output-distance];
            inc(output);
            dec(length);
        end;
    end;
end;

procedure UnitTest;
const known : array[0..9] of uint8 = ($16,65,1,0,$50,65,65,65,65,65);
var
    context : TTestContext;
    plain : array[0..15] of uint8;
    encoded : array[0..31] of uint8;
    n, i : uint32;
    ok : boolean;
begin
    test.harness.Start(@context, 'core.comp.lz4');
    ok := decompress(@known,sizeof(known),@plain,sizeof(plain),n) and (n = 16);
    for i := 0 to 15 do begin
        ok := ok and (plain[i] = 65);
        plain[i] := 65;
    end;
    test.harness.Assert(@context, ok, 'decode known block');

    ok := compress(@plain,16,@encoded,sizeof(encoded),n) and (n = sizeof(known));
    for i := 0 to 9 do
        ok := ok and (encoded[i] = known[i]);
    test.harness.Assert(@context, ok, 'encode known block');
    test.harness.Assert(@context, not decompress(@known,9,@plain,16,n), 'reject truncated block');
    test.harness.Assert(@context, not decompress(@known,10,@plain,15,n), 'reject insufficient output capacity');
    test.harness.Finish(@context);
end;

end.
