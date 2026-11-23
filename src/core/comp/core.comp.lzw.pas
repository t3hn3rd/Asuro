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

{ Raw byte-oriented LZW. Codes are packed least-significant bit first, grow
  from 9 to 12 bits, and use 256 for clear and 257 for end of information.
  Source and destination are disjoint caller-owned buffers. On failure the
  destination may contain a partial result and written is zero. }
unit core.comp.lzw;

interface

function compress(src : puint8; size : uint32; dst : puint8; capacity : uint32;
                  var written : uint32) : boolean;
function decompress(src : puint8; size : uint32; dst : puint8; capacity : uint32;
                    var written : uint32) : boolean;
procedure UnitTest;

implementation

uses memory.heap, io.syslog;

const
    ClearCode = 256;
    EndCode = 257;
    FirstCode = 258;
    CodeLimit = 4096;
    HashSlots = 8192;

type
    PCodeTable = ^TCodeTable;
    TCodeTable = array[0..HashSlots-1] of uint32;
    PDictionary = ^TDictionary;
    TDictionary = record
        offset : array[FirstCode..CodeLimit-1] of uint32;
        length : array[FirstCode..CodeLimit-1] of uint16;
    end;

function compress(src : puint8; size : uint32; dst : puint8; capacity : uint32;
                  var written : uint32) : boolean;
var table : PCodeTable;
    width, next, prefix, key, slot, bits, used, pos, i : uint32;

    function emit(code : uint32) : boolean;
    begin
        emit := false;
        bits := bits or (code shl used);
        inc(used, width);
        while used >= 8 do begin
            if pos = capacity then exit;
            dst[pos] := uint8(bits);
            inc(pos);
            bits := bits shr 8;
            dec(used, 8);
        end;
        emit := true;
    end;

    function encode : boolean;
    var j : uint32;
    begin
        encode := false;
        if not emit(ClearCode) then exit;
        if size <> 0 then begin
            prefix := src[0];
            i := 1;
            while i < size do begin
                key := (prefix shl 8) or src[i];
                slot := ((prefix * 31) xor src[i]) and (HashSlots-1);
                while table^[slot] <> 0 do begin
                    if table^[slot] shr 12 = key then break;
                    slot := (slot + 1) and (HashSlots-1);
                end;
                if table^[slot] <> 0 then
                    prefix := table^[slot] and (CodeLimit-1)
                else begin
                    if not emit(prefix) then exit;
                    prefix := src[i];
                    { Decoder learns this entry one emitted code later. }
                    if (next = uint32(1) shl width) and (width < 12) then inc(width);
                    if next < CodeLimit then begin
                        table^[slot] := (key shl 12) or next;
                        inc(next);
                    end else begin
                        if not emit(ClearCode) then exit;
                        for j := 0 to HashSlots-1 do table^[j] := 0;
                        width := 9;
                        next := FirstCode;
                    end;
                end;
                inc(i);
            end;
            if not emit(prefix) then exit;
            if (next = uint32(1) shl width) and (width < 12) then inc(width);
        end;
        if not emit(EndCode) then exit;
        if used <> 0 then begin
            if pos = capacity then exit;
            dst[pos] := uint8(bits);
            inc(pos);
        end;
        written := pos;
        encode := true;
    end;

begin
    compress := false;
    written := 0;
    if ((src = nil) and (size <> 0)) or (dst = nil) then exit;
    table := PCodeTable(kalloc(sizeof(TCodeTable)));
    if table = nil then exit;
    next := FirstCode;
    width := 9;
    bits := 0;
    used := 0;
    pos := 0;
    compress := encode;
    kfree(void(table));
end;

function decompress(src : puint8; size : uint32; dst : puint8; capacity : uint32;
                    var written : uint32) : boolean;
var dict : PDictionary;

    function decode : boolean;
    var bits, used, pos, input, width, next, code, start, length,
        previousStart, previousLength, i : uint32;
    begin
        decode := false;
        bits := 0;
        used := 0;
        pos := 0;
        input := 0;
        width := 9;
        next := FirstCode;
        previousStart := 0;
        previousLength := 0;
        repeat
            while used < width do begin
                if input = size then exit;
                bits := bits or (uint32(src[input]) shl used);
                inc(input);
                inc(used, 8);
            end;
            code := bits and ((uint32(1) shl width) - 1);
            bits := bits shr width;
            dec(used, width);
            if code = EndCode then begin
                written := pos;
                decode := true;
                exit;
            end;
            if code = ClearCode then begin
                next := FirstCode;
                width := 9;
                previousLength := 0;
            end else begin
                start := pos;
                if code < ClearCode then begin
                    if pos = capacity then exit;
                    dst[pos] := uint8(code);
                    inc(pos);
                end else begin
                    if code < next then begin
                        i := dict^.offset[code];
                        length := dict^.length[code];
                    end else begin
                        if (code <> next) or (previousLength = 0) then exit;
                        i := previousStart;
                        length := previousLength + 1;
                    end;
                    if length > capacity - pos then exit;
                    { Forward copy also handles previous phrase + its first byte. }
                    while length <> 0 do begin
                        dst[pos] := dst[i];
                        inc(i);
                        inc(pos);
                        dec(length);
                    end;
                end;
                if (previousLength <> 0) and (next < CodeLimit) then begin
                    dict^.offset[next] := previousStart;
                    dict^.length[next] := previousLength + 1;
                    inc(next);
                    if (next = uint32(1) shl width) and (width < 12) then inc(width);
                end;
                previousStart := start;
                previousLength := pos - start;
            end;
        until false;
    end;

begin
    decompress := false;
    written := 0;
    if (src = nil) or ((dst = nil) and (capacity <> 0)) then exit;
    dict := PDictionary(kalloc(sizeof(TDictionary)));
    if dict = nil then exit;
    decompress := decode;
    kfree(void(dict));
end;

procedure UnitTest;
const
    { Clear, literal A, dictionary entry AA, end (four 9-bit codes). }
    encoded : array[0..4] of uint8 = ($00,$83,$08,$0C,$08);
var plain : array[0..2] of uint8;
    packedBytes : array[0..4] of uint8;
    n, i, failures, seed, decodedSize : uint32;
    sample, stream : puint8;
    ok : boolean;

    procedure Assert(ok : boolean; name : pchar);
    begin
        if not ok then begin
            inc(failures);
            io.syslog.logln('LZW FAIL', name);
        end;
    end;

begin
    failures := 0;
    Assert(decompress(@encoded,5,@plain,3,n) and (n = 3), 'decode known stream');
    Assert((plain[0] = 65) and (plain[1] = 65) and (plain[2] = 65), 'expand next code');
    Assert(compress(@plain,3,@packedBytes,5,n) and (n = 5), 'encode known stream');
    for i := 0 to 4 do Assert(packedBytes[i] = encoded[i], 'packed byte');
    Assert(not decompress(@encoded,4,@plain,3,n), 'truncated end code');
    Assert(not decompress(@encoded,5,@plain,2,n), 'output capacity');
    Assert(not compress(@plain,3,@packedBytes,4,n), 'compressed capacity');
    Assert(compress(nil,0,@packedBytes,5,n), 'empty input');
    Assert(decompress(@packedBytes,n,nil,0,i) and (i = 0), 'empty output');
    { Five KiB of deterministic input crosses every width and fills the table. }
    sample := puint8(kalloc(5120));
    stream := puint8(kalloc(8192));
    if (sample <> nil) and (stream <> nil) then begin
        seed := 1;
        for i := 0 to 5119 do begin
            seed := seed * 1664525 + 1013904223;
            sample[i] := seed shr 24;
        end;
        ok := compress(sample,5120,stream,8192,n);
        Assert(ok, 'encode through dictionary reset');
        if ok then begin
            ok := decompress(stream,n,sample,5120,decodedSize);
            Assert(ok and (decodedSize = 5120), 'decode through dictionary reset');
            seed := 1;
            for i := 0 to 5119 do begin
                seed := seed * 1664525 + 1013904223;
                if sample[i] <> seed shr 24 then ok := false;
            end;
            Assert(ok, 'dictionary reset round trip');
        end;
    end else Assert(false, 'test buffers');
    if sample <> nil then kfree(void(sample));
    if stream <> nil then kfree(void(stream));
    io.syslog.log('LZW', 'Failures: ');
    io.syslog.writeintln(failures);
end;

end.
