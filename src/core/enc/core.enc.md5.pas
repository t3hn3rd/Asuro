//  Copyright 2021 Angus C & Kieron Morris
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
	Include->MD5 - MD5 checksum.
	
    @author(Angus C <angus@actm.uk>)
	@author(Kieron Morris <kjm@kieronmorris.me>)
}

unit core.enc.md5;

interface

uses
    core.util, arch.x86.util,
    memory.heap,
    debug.tracer;

const
    MD5DefineBufferSize = 1024;

type
    TMD5Context = record
        Align       :   uInt32;
        State       :   array[0..3] of uInt32;
        BufferCount :   uInt64;
        Buffer      :   array[0..63] of uInt8;
        Length      :   uInt64;
        Checksum    :   array[0..15] of uInt8;
    end;

    PMD5Context = ^TMD5Context;

    TMD5Digest = array[0..15] of uInt8;
    PMD5Digest = ^TMD5Digest;

procedure MD5Init(context : PMD5Context);
procedure MD5Update(context : PMD5Context; buffer : PuInt8; bufferLen : uInt32);

function MD5Final(context : PMD5Context) : PMD5Digest;
function MD5Buffer(buffer : PuInt8; bufferLen : uInt32) : PMD5Digest;

function MD5To32(Input : PuInt128) : uint32;

implementation

procedure Invert(Source : PuInt8; Dest : PuInt32; Count : uInt32);
var
    S : PuInt8;
    T : PuInt32;
    I : uInt32;

begin
    debug.tracer.push_trace('core.enc.md5.Invert');
    S := Source;
    T := Dest;
    for I := 1 to (Count div 4) do begin
        T^ := S[0] or (S[1] shl 8) or (S[2] shl 16) or (S[3] shl 24);
        inc(S,4);
        inc(T);
    end; 
end;

procedure MD5Transform(Context: PMD5Context; Buffer: Pointer);
type
    TBlock = array[0..15] of Cardinal;
    PBlock = ^TBlock;
var
    a, b, c, d: Cardinal;
    //Block: array[0..15] of Cardinal absolute Buffer;
    Block: PBlock absolute Buffer;
begin
    debug.tracer.push_trace('core.enc.md5.MD5Transform');
    //Invert(Buffer, @Block, 64);
    a := Context^.State[0];
    b := Context^.State[1];
    c := Context^.State[2];
    d := Context^.State[3];
    // Round 1
    a := b + roldword(dword(a + ((b and c) or ((not b) and d)) + Block^[0]  + $d76aa478),  7);
    d := a + roldword(dword(d + ((a and b) or ((not a) and c)) + Block^[1]  + $e8c7b756), 12);
    c := d + roldword(dword(c + ((d and a) or ((not d) and b)) + Block^[2]  + $242070db), 17);
    b := c + roldword(dword(b + ((c and d) or ((not c) and a)) + Block^[3]  + $c1bdceee), 22);
    a := b + roldword(dword(a + ((b and c) or ((not b) and d)) + Block^[4]  + $f57c0faf),  7);
    d := a + roldword(dword(d + ((a and b) or ((not a) and c)) + Block^[5]  + $4787c62a), 12);
    c := d + roldword(dword(c + ((d and a) or ((not d) and b)) + Block^[6]  + $a8304613), 17);
    b := c + roldword(dword(b + ((c and d) or ((not c) and a)) + Block^[7]  + $fd469501), 22);
    a := b + roldword(dword(a + ((b and c) or ((not b) and d)) + Block^[8]  + $698098d8),  7);
    d := a + roldword(dword(d + ((a and b) or ((not a) and c)) + Block^[9]  + $8b44f7af), 12);
    c := d + roldword(dword(c + ((d and a) or ((not d) and b)) + Block^[10] + $ffff5bb1), 17);
    b := c + roldword(dword(b + ((c and d) or ((not c) and a)) + Block^[11] + $895cd7be), 22);
    a := b + roldword(dword(a + ((b and c) or ((not b) and d)) + Block^[12] + $6b901122),  7);
    d := a + roldword(dword(d + ((a and b) or ((not a) and c)) + Block^[13] + $fd987193), 12);
    c := d + roldword(dword(c + ((d and a) or ((not d) and b)) + Block^[14] + $a679438e), 17);
    b := c + roldword(dword(b + ((c and d) or ((not c) and a)) + Block^[15] + $49b40821), 22);
    // Round 2
    a := b + roldword(dword(a + ((b and d) or (c and (not d))) + Block^[1]  + $f61e2562),  5);
    d := a + roldword(dword(d + ((a and c) or (b and (not c))) + Block^[6]  + $c040b340),  9);
    c := d + roldword(dword(c + ((d and b) or (a and (not b))) + Block^[11] + $265e5a51), 14);
    b := c + roldword(dword(b + ((c and a) or (d and (not a))) + Block^[0]  + $e9b6c7aa), 20);
    a := b + roldword(dword(a + ((b and d) or (c and (not d))) + Block^[5]  + $d62f105d),  5);
    d := a + roldword(dword(d + ((a and c) or (b and (not c))) + Block^[10] + $02441453),  9);
    c := d + roldword(dword(c + ((d and b) or (a and (not b))) + Block^[15] + $d8a1e681), 14);
    b := c + roldword(dword(b + ((c and a) or (d and (not a))) + Block^[4]  + $e7d3fbc8), 20);
    a := b + roldword(dword(a + ((b and d) or (c and (not d))) + Block^[9]  + $21e1cde6),  5);
    d := a + roldword(dword(d + ((a and c) or (b and (not c))) + Block^[14] + $c33707d6),  9);
    c := d + roldword(dword(c + ((d and b) or (a and (not b))) + Block^[3]  + $f4d50d87), 14);
    b := c + roldword(dword(b + ((c and a) or (d and (not a))) + Block^[8]  + $455a14ed), 20);
    a := b + roldword(dword(a + ((b and d) or (c and (not d))) + Block^[13] + $a9e3e905),  5);
    d := a + roldword(dword(d + ((a and c) or (b and (not c))) + Block^[2]  + $fcefa3f8),  9);
    c := d + roldword(dword(c + ((d and b) or (a and (not b))) + Block^[7]  + $676f02d9), 14);
    b := c + roldword(dword(b + ((c and a) or (d and (not a))) + Block^[12] + $8d2a4c8a), 20);
    // Round 3
    a := b + roldword(dword(a + (b xor c xor d) + Block^[5]  + $fffa3942),  4);
    d := a + roldword(dword(d + (a xor b xor c) + Block^[8]  + $8771f681), 11);
    c := d + roldword(dword(c + (d xor a xor b) + Block^[11] + $6d9d6122), 16);
    b := c + roldword(dword(b + (c xor d xor a) + Block^[14] + $fde5380c), 23);
    a := b + roldword(dword(a + (b xor c xor d) + Block^[1]  + $a4beea44),  4);
    d := a + roldword(dword(d + (a xor b xor c) + Block^[4]  + $4bdecfa9), 11);
    c := d + roldword(dword(c + (d xor a xor b) + Block^[7]  + $f6bb4b60), 16);
    b := c + roldword(dword(b + (c xor d xor a) + Block^[10] + $bebfbc70), 23);
    a := b + roldword(dword(a + (b xor c xor d) + Block^[13] + $289b7ec6),  4);
    d := a + roldword(dword(d + (a xor b xor c) + Block^[0]  + $eaa127fa), 11);
    c := d + roldword(dword(c + (d xor a xor b) + Block^[3]  + $d4ef3085), 16);
    b := c + roldword(dword(b + (c xor d xor a) + Block^[6]  + $04881d05), 23);
    a := b + roldword(dword(a + (b xor c xor d) + Block^[9]  + $d9d4d039),  4);
    d := a + roldword(dword(d + (a xor b xor c) + Block^[12] + $e6db99e5), 11);
    c := d + roldword(dword(c + (d xor a xor b) + Block^[15] + $1fa27cf8), 16);
    b := c + roldword(dword(b + (c xor d xor a) + Block^[2]  + $c4ac5665), 23);
    // Round 4
    a := b + roldword(dword(a + (c xor (b or (not d))) + Block^[0]  + $f4292244),  6);
    d := a + roldword(dword(d + (b xor (a or (not c))) + Block^[7]  + $432aff97), 10);
    c := d + roldword(dword(c + (a xor (d or (not b))) + Block^[14] + $ab9423a7), 15);
    b := c + roldword(dword(b + (d xor (c or (not a))) + Block^[5]  + $fc93a039), 21);
    a := b + roldword(dword(a + (c xor (b or (not d))) + Block^[12] + $655b59c3),  6);
    d := a + roldword(dword(d + (b xor (a or (not c))) + Block^[3]  + $8f0ccc92), 10);
    c := d + roldword(dword(c + (a xor (d or (not b))) + Block^[10] + $ffeff47d), 15);
    b := c + roldword(dword(b + (d xor (c or (not a))) + Block^[1]  + $85845dd1), 21);
    a := b + roldword(dword(a + (c xor (b or (not d))) + Block^[8]  + $6fa87e4f),  6);
    d := a + roldword(dword(d + (b xor (a or (not c))) + Block^[15] + $fe2ce6e0), 10);
    c := d + roldword(dword(c + (a xor (d or (not b))) + Block^[6]  + $a3014314), 15);
    b := c + roldword(dword(b + (d xor (c or (not a))) + Block^[13] + $4e0811a1), 21);
    a := b + roldword(dword(a + (c xor (b or (not d))) + Block^[4]  + $f7537e82),  6);
    d := a + roldword(dword(d + (b xor (a or (not c))) + Block^[11] + $bd3af235), 10);
    c := d + roldword(dword(c + (a xor (d or (not b))) + Block^[2]  + $2ad7d2bb), 15);
    b := c + roldword(dword(b + (d xor (c or (not a))) + Block^[9]  + $eb86d391), 21);
    inc(Context^.State[0],a);
    inc(Context^.State[1],b);
    inc(Context^.State[2],c);
    inc(Context^.State[3],d);
    inc(Context^.Length,64);
end;

procedure MD5Init(context : PMD5Context);
begin
    debug.tracer.push_trace('core.enc.md5.MD5Init');
    memset(uInt32(context), 0, SizeOf(TMD5Context));
    context^.Align          := 64;
    context^.State[0]       := $67452301;
    context^.State[1]       := $efcdab89;
    context^.State[2]       := $98badcfe;
    context^.State[3]       := $10325476;
    context^.Length         := 0;
    context^.BufferCount    := 0;  
end;

procedure MD5Update(context : PMD5Context; buffer : PuInt8; bufferLen : uInt32);
var
    Align   : uInt32;
    Src     : PuInt8;
    Num     : uInt32;
    i       : uint32;

begin  
    debug.tracer.push_trace('core.enc.md5.MD5Update');
    if bufferLen = 0 then Exit;
    Align   := context^.Align;
    Src     := buffer;
    Num     := 0;
    if context^.BufferCount > 0 then begin    
        Num := Align - context^.BufferCount;   
        if Num > bufferLen then num := bufferLen;
        memcpy(uInt32(Src), uInt32(@context^.Buffer[Context^.BufferCount]), Num); 
        context^.BufferCount := context^.BufferCount + Num;       
        Src := PuInt8(uInt32(Src) + uint32(Num));      
        if context^.BufferCount = Align then begin         
            MD5Transform(context, @context^.buffer[0]);         
            context^.BufferCount := 0;
        end;     
    end;
    Num := bufferLen - Num;
    While Num >= Align do begin
        MD5Transform(context, Src);
        Src := PuInt8(uInt32(Src) + Align);
        Num := Num - Align;
    end;
    if Num > 0 then begin     
        context^.BufferCount := Num;   
        memcpy(uInt32(Src), uInt32(@context^.Buffer[0]), Num);
    end; 
end;

function MD5Final(context : PMD5Context) : PMD5Digest;
const
    MD5_Padding : array[0..15] of uInt32 = ($80,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
var
    Length : uInt64;
    Pads   : uInt32;
    Digest : PMD5Digest;
    i      : uint32;

begin
    debug.tracer.push_trace('core.enc.md5.MD5Final');
    Length := 8 * (context^.Length + context^.BufferCount);
    if context^.BufferCount >= 56 then
        Pads := 120 - context^.BufferCount
    else
        Pads := 56 - context^.BufferCount;
    MD5Update(context, PuInt8(@MD5_Padding[0]), Pads);
    MD5Update(context, PuInt8(@Length), 8); 
    Digest := PMD5Digest(kalloc(SizeOf(TMD5Digest)));  
    memset(uInt32(Digest), 0, SizeOf(TMD5Digest)); 
    Invert(PuInt8(@context^.State), PuInt32(Digest), 16); 
    memset(uInt32(context), 0, SizeOf(TMD5Context)); 
    MD5Final := Digest; 
end;

function MD5Buffer(buffer : PuInt8; bufferLen : uInt32) : PMD5Digest;
var
    context : PMD5Context;
begin
    debug.tracer.push_trace('core.enc.md5.MD5Buffer');
    context := PMD5Context(kalloc(SizeOf(TMD5Context)));
    MD5Init(context);
    MD5Update(context, buffer, bufferLen);
    MD5Buffer := MD5Final(context);
    kfree(void(context));
end;

function MD5To32(Input : PuInt128) : uint32;
var
    MD5To64 : uint64;
    i       : uint8;

begin
    MD5To32:= Input^.DWords[0] xor Input^.DWords[1] xor Input^.DWords[2] xor Input^.DWords[3];
end;

end.