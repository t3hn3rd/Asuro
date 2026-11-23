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

{ Raw RFC 1951 stream. Encoder emits fixed Huffman blocks. Decoder accepts stored, fixed and dynamic blocks. Disjoint caller-owned buffers. On failure written is zero. }
unit core.comp.deflate;

interface

function compress(src : puint8; size : uint32; dst : puint8; capacity : uint32;
                  var written : uint32) : boolean;
function decompress(src : puint8; size : uint32; dst : puint8; capacity : uint32;
                    var written : uint32) : boolean;
procedure UnitTest;

implementation

uses memory.heap, core.comp.match, io.syslog;

const
    lengthBase : array[0..28] of uint16 =
        (3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258);
    lengthExtra : array[0..28] of uint8 =
        (0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0);
    distBase : array[0..29] of uint16 =
        (1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,
         2049,3073,4097,6145,8193,12289,16385,24577);
    distExtra : array[0..29] of uint8 =
        (0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13);
    codeOrder : array[0..18] of uint8 = (16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15);

function compress(src : puint8; size : uint32; dst : puint8; capacity : uint32;
                  var written : uint32) : boolean;
var table : PMatchTable;
    bits, used, output, pos, span, length, distance, index : uint32;
    ok : boolean;

    procedure put(value, width : uint32);
    begin
        bits := bits or (value shl used);
        inc(used,width);
        while used >= 8 do begin
            if output = capacity then ok := false
            else begin
                dst[output] := uint8(bits);
                inc(output);
            end;
            bits := bits shr 8;
            dec(used,8);
        end;
    end;

    procedure huffman(code, width : uint32);
    var reversed, i : uint32;
    begin
        reversed := 0;
        for i := 1 to width do begin
            reversed := (reversed shl 1) or (code and 1);
            code := code shr 1;
        end;
        put(reversed,width);
    end;

    procedure symbol(value : uint32);
    begin
        if value < 144 then huffman(48+value,8)
        else if value < 256 then huffman(400+value-144,9)
        else if value < 280 then huffman(value-256,7)
        else huffman(192+value-280,8);
    end;

begin
    compress := false;
    written := 0;
    if ((src = nil) and (size <> 0)) or (dst = nil) then exit;
    table := PMatchTable(kalloc(sizeof(TMatchTable)));
    if table = nil then exit;
    used := 0;
    bits := 0;
    pos := 0;
    output := 0;
    ok := true;
    put(3,3);
    while (pos < size) and ok do begin
        span := size-pos;
        if span > 258 then span := 258;
        length := 0;
        if span >= 3 then length := findMatch(table,src,pos,span,32768,distance);
        if length < 3 then begin
            symbol(src[pos]);
            inc(pos);
        end else begin
            index := 28;
            while length < lengthBase[index] do dec(index);
            symbol(index+257);
            put(length-lengthBase[index],lengthExtra[index]);
            index := 29;
            while distance < distBase[index] do dec(index);
            huffman(index,5);
            put(distance-distBase[index],distExtra[index]);
            inc(pos,length);
        end;
    end;
    if ok then begin
        symbol(256);
        if used <> 0 then put(0,8-used);
    end;
    kfree(void(table));
    if ok then written := output;
    compress := ok;
end;

type
    TTree = record
        count : array[0..15] of uint16;
        symbols : array[0..287] of uint16;
    end;
    PWorkspace = ^TWorkspace;
    TWorkspace = record
        literals, distances, codes : TTree;
        lengths : array[0..319] of uint8;
    end;

{ Sort canonical codes by length and then symbol number. }
function buildTree(var tree : TTree; lengths : puint8; count : uint32;
                   allowSingle : boolean) : boolean;
var offsets : array[0..15] of uint16;
    i, width, space : uint32;
begin
    buildTree := false;
    for width := 0 to 15 do tree.count[width] := 0;
    for i := 0 to count-1 do inc(tree.count[lengths[i]]);
    space := 1;
    offsets[1] := 0;
    for width := 1 to 15 do begin
        space := space shl 1;
        if tree.count[width] > space then exit;
        dec(space,tree.count[width]);
        if width < 15 then offsets[width+1] := offsets[width]+tree.count[width];
    end;
    if (space <> 0) and not (allowSingle and (tree.count[1] = 1) and
       (tree.count[0] = count-1)) then exit;
    for i := 0 to count-1 do begin
        width := lengths[i];
        if width <> 0 then begin
            tree.symbols[offsets[width]] := i;
            inc(offsets[width]);
        end;
    end;
    buildTree := true;
end;

function decompress(src : puint8; size : uint32; dst : puint8; capacity : uint32;
                    var written : uint32) : boolean;
var work : PWorkspace;
    pos, output, bits, used : uint32;
    ok : boolean;

    function take(width : uint32) : uint32;
    begin
        take := 0;
        while used < width do begin
            if pos = size then begin
                ok := false;
                exit;
            end;
            bits := bits or (uint32(src[pos]) shl used);
            inc(pos);
            inc(used,8);
        end;
        take := bits and ((uint32(1) shl width)-1);
        bits := bits shr width;
        dec(used,width);
    end;

    function readSymbol(var tree : TTree) : uint32;
    var width, code, first, index : uint32;
    begin
        readSymbol := 0;
        code := 0;
        first := 0;
        index := 0;
        for width := 1 to 15 do begin
            code := (code shl 1) or take(1);
            if not ok then exit;
            if code < first + tree.count[width] then begin
                readSymbol := tree.symbols[index+code-first];
                exit;
            end;
            inc(index,tree.count[width]);
            first := (first+tree.count[width]) shl 1;
        end;
        ok := false;
    end;

    function prepareTrees(kind : uint32) : boolean;
    var literals, distances, codes, i, value, copies : uint32;
    begin
        prepareTrees := false;
        if kind = 1 then begin
            literals := 288;
            distances := 32;
            for i := 0 to 143 do work^.lengths[i] := 8;
            for i := 144 to 255 do work^.lengths[i] := 9;
            for i := 256 to 279 do work^.lengths[i] := 7;
            for i := 280 to 287 do work^.lengths[i] := 8;
            for i := 288 to 319 do work^.lengths[i] := 5;
        end else begin
            literals := take(5)+257;
            distances := take(5)+1;
            codes := take(4)+4;
            if literals > 286 then exit;
            for i := 0 to 18 do work^.lengths[i] := 0;
            for i := 0 to codes-1 do work^.lengths[codeOrder[i]] := take(3);
            if not ok then exit;
            if not buildTree(work^.codes,@work^.lengths,19,false) then exit;
            i := 0;
            while i < literals+distances do begin
                value := readSymbol(work^.codes);
                copies := 1;
                case value of
                    16: begin
                        if i = 0 then exit;
                        value := work^.lengths[i-1];
                        copies := take(2)+3;
                    end;
                    17: begin
                        value := 0;
                        copies := take(3)+3;
                    end;
                    18: begin
                        value := 0;
                        copies := take(7)+11;
                    end;
                end;
                if not ok or (copies > literals+distances-i) then exit;
                while copies <> 0 do begin
                    work^.lengths[i] := value;
                    inc(i);
                    dec(copies);
                end;
            end;
        end;
        if work^.lengths[256] = 0 then exit;
        if not buildTree(work^.literals,@work^.lengths,literals,true) then exit;
        { An all-literal dynamic block can have an empty distance alphabet. }
        if (distances = 1) and (work^.lengths[literals] = 0) then begin
            for i := 0 to 15 do work^.distances.count[i] := 0;
            prepareTrees := true;
        end else prepareTrees := buildTree(work^.distances,@work^.lengths[literals],distances,true);
    end;

    function decode : boolean;
    var last, kind, sym, length, distance, complement : uint32;
    begin
        decode := false;
        repeat
            last := take(1);
            kind := take(2);
            if not ok or (kind = 3) then exit;
            if kind = 0 then begin
                bits := 0;
                used := 0;
                length := take(16);
                complement := take(16);
                if not ok or ((length xor complement) <> 65535) then exit;
                if (length > size-pos) or (length > capacity-output) then exit;
                while length <> 0 do begin
                    dst[output] := src[pos];
                    inc(pos);
                    inc(output);
                    dec(length);
                end;
            end else begin
                if not prepareTrees(kind) then exit;
                repeat
                    sym := readSymbol(work^.literals);
                    if not ok then exit;
                    if sym < 256 then begin
                        if output = capacity then exit;
                        dst[output] := sym;
                        inc(output);
                    end else if sym <> 256 then begin
                        if sym > 285 then exit;
                        length := lengthBase[sym-257]+take(lengthExtra[sym-257]);
                        distance := readSymbol(work^.distances);
                        if distance > 29 then exit;
                        distance := distBase[distance]+take(distExtra[distance]);
                        if not ok or (distance > output) or (length > capacity-output) then exit;
                        while length <> 0 do begin
                            dst[output] := dst[output-distance];
                            inc(output);
                            dec(length);
                        end;
                    end;
                until sym = 256;
            end;
        until last = 1;
        written := output;
        decode := true;
    end;

begin
    decompress := false;
    written := 0;
    if (src = nil) or ((dst = nil) and (capacity <> 0)) then exit;
    work := PWorkspace(kalloc(sizeof(TWorkspace)));
    if work = nil then exit;
    pos := 0;
    output := 0;
    bits := 0;
    used := 0;
    ok := true;
    decompress := decode;
    kfree(void(work));
end;

procedure UnitTest;
const
    dynamicBlock : array[0..19] of uint8 = ($05,$C1,$81,$00,$00,$00,$00,$00,$10,$FF,$D5,$00,$00,$00,$00,$00,$00,$00,$00,$08);
    fixedBlock : array[0..3] of uint8 = ($73,$44,$03,$00);
    stored : array[0..7] of uint8 = (1,3,0,$FC,$FF,65,66,67);
var plain : array[0..63] of uint8;
    packedBytes : array[0..15] of uint8;
    i, n : uint32;
    ok : boolean;
begin
    ok := decompress(@dynamicBlock,sizeof(dynamicBlock),@plain,64,n) and (n = 64);
    for i := 0 to 63 do if plain[i] <> 0 then ok := false;
    ok := ok and decompress(@stored,sizeof(stored),@plain,3,n) and (n = 3);
    ok := ok and (plain[0] = 65) and (plain[1] = 66) and (plain[2] = 67);
    ok := ok and decompress(@fixedBlock,sizeof(fixedBlock),@plain,16,n) and (n = 16);
    for i := 0 to 15 do if plain[i] <> 65 then ok := false;
    ok := ok and compress(@plain,16,@packedBytes,16,n) and (n = sizeof(fixedBlock));
    for i := 0 to sizeof(fixedBlock)-1 do if packedBytes[i] <> fixedBlock[i] then ok := false;
    ok := ok and not decompress(@dynamicBlock,sizeof(dynamicBlock)-1,@plain,64,n);
    ok := ok and not decompress(@fixedBlock,sizeof(fixedBlock),@plain,15,n);
    if ok then io.syslog.logln('DEFLATE','Passed') else io.syslog.logln('DEFLATE','FAILED');
end;

end.
