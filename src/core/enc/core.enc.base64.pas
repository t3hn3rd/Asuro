//  Copyright 2021 Angus C
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
	Include->Base64 - Base64 encode and decode.
	
    @author(Angus C <angus@actm.uk>)
}

unit core.enc.base64;

interface

uses
    memory.heap,
    core.strings,
    debug.tracer,
    core.util, arch.x86.util;

const
    base64_enc_map : array[0..63] of char = ('A','B','C','D','E',
                     'F','G','H','I','J','K','L','M','N','O','P',
                     'Q','R','S','T','U','V','W','X','Y','Z','a',
                     'b','c','d','e','f','g','h','i','j','k','l',
                     'm','n','o','p','q','r','s','t','u','v','w',
                     'x','y','z','0','1','2','3','4','5','6','7',
                     '8','9','+','/');

function b64_encode(src : PuInt8; len : uInt32; out_len : PuInt32) : PuInt8;
function b64_decode(src : PuInt8; len : uInt32; out_len : PuInt32) : PuInt8;

function b64_encode_str(src : PChar) : PChar;
function b64_decode_str(src : PChar) : PChar;

implementation

function b64_encode(src : PuInt8; len : uInt32; out_len : PuInt32) : PuInt8;
var
    olen      : uInt32;
    line_len  : uInt32;
    b64end    : PuInt8;
    b64in     : PuInt8;
    b64pos    : PuInt8;
    output    : PuInt8;

begin
    olen := len * 4 div 3 + 4; // 3-byte blocks to 4-byte
    olen := olen + (olen div 72); // line feeds
    olen := olen + 1; // nul termination

    output := nil;
    if olen < len then begin
        // integer overflow
    end else begin
        output := PuInt8(kalloc(olen));
        b64end := PuInt8(uInt32(src) + uInt32(len));
        b64in  := src;
        b64pos := output;
        line_len := 0;
        while (uInt32(b64end) - uInt32(b64in)) >= 3 do begin
            b64pos^ := uInt8(base64_enc_map[b64in[0] shr 2]);
            inc(b64pos);
            b64pos^ := uInt8(base64_enc_map[((b64in[0] and $03) shl 4) or (b64in[1] shr 4)]);
            inc(b64pos);
            b64pos^ := uInt8(base64_enc_map[((b64in[1] and $0F) shl 2) or (b64in[2] shr 6)]);
            inc(b64pos);
            b64pos^ := uInt8(base64_enc_map[b64in[2] and $3F]);
            inc(b64pos);
            inc(b64in, 3);
            inc(line_len, 4);
            if line_len >= 72 then begin
                b64pos^ := $0A;
                inc(b64pos);
            end;
        end;
        
        if (uInt32(b64end) - uInt32(b64in)) > 0 then begin
            b64pos^ := uInt8(base64_enc_map[b64in[0] shr 2]);
            inc(b64pos);
            if (uInt32(b64end) - uInt32(b64in)) = 1 then begin
                b64pos^ := uInt8(base64_enc_map[((b64in[0] and $03) shl 4)]);
                inc(b64pos);
                b64pos^ := $3D;
                inc(b64pos);
            end else begin
                b64pos^ := uInt8(base64_enc_map[((b64in[0] and $03) shl 4) or (b64in[1] shr 4)]);
                inc(b64pos);
                b64pos^ := uInt8(base64_enc_map[((b64in[1] and $0F) shl 2)]);
                inc(b64pos);
            end;
            b64pos^ := $3D;
            inc(b64pos);
            inc(line_len, 4);
        end;

        if line_len > 0 then begin
            b64pos^ := $0A;
            inc(b64pos);
        end;
        b64pos^ := $0;
        if out_len <> nil then begin
            out_len^ := uInt32(b64pos) - uInt32(output);
        end;
    end;
    b64_encode := output;
end;

function b64_decode(src : PuInt8; len : uInt32; out_len : PuInt32) : PuInt8;
var
    b64tmp  : uInt8;
    b64pos  : PuInt8;
    output  : PuInt8;
    i       : uInt32;
    count   : uInt32;
    olen    : uInt32;
    pad     : uInt32;
    dtable  : array[0..255] of uInt8;
    block   : array[0..3] of uInt8;

begin
    pad := 0;
    memset(uInt32(@dtable[0]), $80, 256);

    for i := 0 to (sizeof(base64_enc_map) - 2) do begin
        dtable[uInt8(base64_enc_map[i])] := uInt8(i);
    end;
    dtable[uInt8('=')] := 0;
    count := 0;
    for i := 0 to (len - 1) do begin
        if dtable[uInt8(src[i])] <> $80 then begin
            inc(count)
        end;
    end;
    if count = 0 or count mod 4 then begin
        // something went wrong
    end else begin
        olen := count div 4 * 3;
        b64pos := PuInt8(kalloc(olen));
        output := b64pos;
        if output = nil then begin
            // something went wrong
        end else begin
            count := 0;
            for i := 0 to (len - 1) do begin
                b64tmp := uInt8(dtable[src[i]]);
                if b64tmp = $80 then begin
                    continue;
                end;
                if src[i] = uInt8('=') then begin
                    inc(pad);
                end;
                block[count] := b64tmp;
                inc(count);
                if count = 4 then begin
                    b64pos^ := uInt8((block[0] shl 2) or (block[1] shr 4));
                    inc(b64pos);
                    b64pos^ := uInt8((block[1] shl 4) or (block[2] shr 2));
                    inc(b64pos);
                    b64pos^ := uInt8((block[2] shl 6) or block[3]);
                    inc(b64pos);
                    count := 0;
                    if pad > 0 then begin
                        if pad = 1 then begin
                            dec(b64pos);
                        end else if pad = 2 then begin
                            dec(b64pos, 2);
                        end else begin
                            kfree(void(output));
                            b64_decode := nil;
                            exit;
                        end;
                        break;
                    end;
                end;
            end;
        end;
        if out_len <> nil then begin
            out_len^ := uInt32(b64pos) - uInt32(output);
        end;
    end;
    b64_decode := output;
end;

function b64_encode_str(src : PChar) : PChar;
var
    src_len : uInt32;
begin
    src_len := stringSize(src);
    debug.tracer.push_trace('base64_prog.base64.begin.encode');
    b64_encode_str := PChar(b64_encode(PuInt8(src), src_len, nil));
    debug.tracer.push_trace('base64_prog.base64.return.encode');
end;

function b64_decode_str(src : PChar) : PChar;
var
    src_len : uInt32;
begin
    src_len := stringSize(src);
    debug.tracer.push_trace('base64_prog.base64.begin.decode');
    b64_decode_str := PChar(b64_decode(PuInt8(src), src_len, nil));
    debug.tracer.push_trace('base64_prog.base64.return.decode');
end;

end.