unit md5;

interface

uses
    util,
    lmemorymanager,
    console,
    tracer;

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

implementation

procedure Invert(Source : PuInt8; Dest : PuInt32; Count : uInt32);
var
    S : PuInt8;
    T : PuInt32;
    I : uInt32;

begin
    S := Source;
    T := Dest;
    for I := 1 to (Count div 4) do begin
        T^ := S[0] or (S[1] shl 8) or (S[2] shl 16) or (S[3] shl 24);
        inc(S,4);
        inc(T);
    end; 
end;

procedure MD5Transform(context : PMD5Context; buffer : PuInt8);
    procedure R1(a : PuInt32; b,c,d,x : uInt32; s : uInt8; ac : uInt32);
    begin
        a^ := b + RolDWord(uInt32(a^ + ((b and c) or ((not b) and d)) + x + ac), s);
    end;
    procedure R2(a : PuInt32; b,c,d,x : uInt32; s : uInt8; ac : uInt32);
    begin
        a^ := b + RolDWord(uInt32(a^ + ((b and d) or (c and (not d))) + x + ac), s);
    end;
    procedure R3(a : PuInt32; b,c,d,x : uInt32; s : uInt8; ac : uInt32);
    begin
        a^ := b + RolDWord(uInt32(a^ + (b xor c xor d) + x + ac), s);
    end;
    procedure R4(a : PuInt32; b,c,d,x : uInt32; s : uInt8; ac : uInt32);
    begin
        a^ := b + RolDWord(uInt32(a^ + (c xor (b or (not d))) + x + ac), s);
    end;

var
    a, b, c, d : uInt32;
    Block : array[0..15] of uInt32;

begin
    Invert(Buffer, @Block, 64);
    a := context^.State[0];
    b := context^.State[1];
    c := context^.State[2];
    d := context^.State[3];

    // Round 1
    R1(PuInt32(@a),b,c,d,Block[0] , 7,$d76aa478); R1(PuInt32(@d),a,b,c,Block[1] ,12,$e8c7b756); R1(PuInt32(@c),d,a,b,Block[2] ,17,$242070db); R1(PuInt32(@b),c,d,a,Block[3] ,22,$c1bdceee);
    R1(PuInt32(@a),b,c,d,Block[4] , 7,$f57c0faf); R1(PuInt32(@d),a,b,c,Block[5] ,12,$4787c62a); R1(PuInt32(@c),d,a,b,Block[6] ,17,$a8304613); R1(PuInt32(@b),c,d,a,Block[7] ,22,$fd469501);
    R1(PuInt32(@a),b,c,d,Block[8] , 7,$698098d8); R1(PuInt32(@d),a,b,c,Block[9] ,12,$8b44f7af); R1(PuInt32(@c),d,a,b,Block[10],17,$ffff5bb1); R1(PuInt32(@b),c,d,a,Block[11],22,$895cd7be);
    R1(PuInt32(@a),b,c,d,Block[12], 7,$6b901122); R1(PuInt32(@d),a,b,c,Block[13],12,$fd987193); R1(PuInt32(@c),d,a,b,Block[14],17,$a679438e); R1(PuInt32(@b),c,d,a,Block[15],22,$49b40821);

    // Round 2
    R2(PuInt32(@a),b,c,d,Block[1] , 5,$f61e2562); R2(PuInt32(@d),a,b,c,Block[6] , 9,$c040b340); R2(PuInt32(@c),d,a,b,Block[11],14,$265e5a51); R2(PuInt32(@b),c,d,a,Block[0] ,20,$e9b6c7aa);
    R2(PuInt32(@a),b,c,d,Block[5] , 5,$d62f105d); R2(PuInt32(@d),a,b,c,Block[10], 9,$02441453); R2(PuInt32(@c),d,a,b,Block[15],14,$d8a1e681); R2(PuInt32(@b),c,d,a,Block[4] ,20,$e7d3fbc8);
    R2(PuInt32(@a),b,c,d,Block[9] , 5,$21e1cde6); R2(PuInt32(@d),a,b,c,Block[14], 9,$c33707d6); R2(PuInt32(@c),d,a,b,Block[3] ,14,$f4d50d87); R2(PuInt32(@b),c,d,a,Block[8] ,20,$455a14ed);
    R2(PuInt32(@a),b,c,d,Block[13], 5,$a9e3e905); R2(PuInt32(@d),a,b,c,Block[2] , 9,$fcefa3f8); R2(PuInt32(@c),d,a,b,Block[7] ,14,$676f02d9); R2(PuInt32(@b),c,d,a,Block[12],20,$8d2a4c8a);

    // Round 3
    R3(PuInt32(@a),b,c,d,Block[5] , 4,$fffa3942); R3(PuInt32(@d),a,b,c,Block[8] ,11,$8771f681); R3(PuInt32(@c),d,a,b,Block[11],16,$6d9d6122); R3(PuInt32(@b),c,d,a,Block[14],23,$fde5380c);
    R3(PuInt32(@a),b,c,d,Block[1] , 4,$a4beea44); R3(PuInt32(@d),a,b,c,Block[4] ,11,$4bdecfa9); R3(PuInt32(@c),d,a,b,Block[7] ,16,$f6bb4b60); R3(PuInt32(@b),c,d,a,Block[10],23,$bebfbc70);
    R3(PuInt32(@a),b,c,d,Block[13], 4,$289b7ec6); R3(PuInt32(@d),a,b,c,Block[0] ,11,$eaa127fa); R3(PuInt32(@c),d,a,b,Block[3] ,16,$d4ef3085); R3(PuInt32(@b),c,d,a,Block[6] ,23,$04881d05);
    R3(PuInt32(@a),b,c,d,Block[9] , 4,$d9d4d039); R3(PuInt32(@d),a,b,c,Block[12],11,$e6db99e5); R3(PuInt32(@c),d,a,b,Block[15],16,$1fa27cf8); R3(PuInt32(@b),c,d,a,Block[2] ,23,$c4ac5665);

    // Round 4
    R4(PuInt32(@a),b,c,d,Block[0] , 6,$f4292244); R4(PuInt32(@d),a,b,c,Block[7] ,10,$432aff97); R4(PuInt32(@c),d,a,b,Block[14],15,$ab9423a7); R4(PuInt32(@b),c,d,a,Block[5] ,21,$fc93a039);
    R4(PuInt32(@a),b,c,d,Block[12], 6,$655b59c3); R4(PuInt32(@d),a,b,c,Block[3] ,10,$8f0ccc92); R4(PuInt32(@c),d,a,b,Block[10],15,$ffeff47d); R4(PuInt32(@b),c,d,a,Block[1] ,21,$85845dd1);
    R4(PuInt32(@a),b,c,d,Block[8] , 6,$6fa87e4f); R4(PuInt32(@d),a,b,c,Block[15],10,$fe2ce6e0); R4(PuInt32(@c),d,a,b,Block[6] ,15,$a3014314); R4(PuInt32(@b),c,d,a,Block[13],21,$4e0811a1);
    R4(PuInt32(@a),b,c,d,Block[4] , 6,$f7537e82); R4(PuInt32(@d),a,b,c,Block[11],10,$bd3af235); R4(PuInt32(@c),d,a,b,Block[2] ,15,$2ad7d2bb); R4(PuInt32(@b),c,d,a,Block[9] ,21,$eb86d391);

    inc(context^.State[0],a);
    inc(context^.State[1],b);
    inc(context^.State[2],c);
    inc(context^.State[3],d);

    inc(context^.Length,64);
end;

procedure MD5Init(context : PMD5Context);
begin
    tracer.push_trace('MD5.MD5Init');
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
begin
    tracer.push_trace('MD5.MD5Update');
    if bufferLen = 0 then Exit;

    Align   := context^.Align;
    Src     := buffer;
    Num     := 0;

    if context^.BufferCount > 0 then begin
        Num := Align - context^.BufferCount;
        if Num > bufferLen then
            num := bufferLen;
        memcpy(uInt32(Src), uInt32(@context^.Buffer[0]), Num);
        context^.BufferCount := context^.BufferCount + Num;
        Src := PuInt8(uInt32(Src) + Num);
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
begin
    tracer.push_trace('MD5.MD5Final');
    Length := 8 * (context^.Length + context^.BufferCount);
    if context^.BufferCount >= 56 then
        Pads := 120 - context^.BufferCount
    else
        Pads := 56 - context^.BufferCount;
    MD5Update(context, PuInt8(@MD5_Padding[0]), Pads);

    MD5Update(context, PuInt8(@Length), 8);
    
    Digest := PMD5Digest(kalloc(SizeOf(TMD5Digest)));
    memset(uInt32(Digest), 0, SizeOf(TMD5Digest));
    Invert(PuInt8(@context^.State[0]), PuInt32(@Digest[0]), 16);

    memset(uInt32(context), 0, SizeOf(TMD5Context));
    MD5Final := Digest;
end;

function MD5Buffer(buffer : PuInt8; bufferLen : uInt32) : PMD5Digest;
var
    context : PMD5Context;
begin
    tracer.push_trace('MD5.MD5Buffer');
    context := PMD5Context(kalloc(SizeOf(TMD5Context)));
    memset(uInt32(context), 0, SizeOf(TMD5Context));
    outputln('md5', 'Init');
    console.redrawwindows;
    MD5Init(@context);
    outputln('md5', 'Init Done');
    console.redrawwindows;
    outputln('md5', 'Update');
    console.redrawwindows;
    MD5Update(@context, buffer, bufferLen);
    outputln('md5', 'Update Done');
    console.redrawwindows;
    outputln('md5', 'Final');
    console.redrawwindows;
    MD5Buffer := MD5Final(@context);
    outputln('md5', 'Final Done');
    console.redrawwindows;
end;

end.