unit core.enc.sha1;

interface

type
    TSHA1Digest = array[0..19] of byte;
    PSHA1Digest = ^TSHA1Digest;

    TSHA1Context = record
        State : array[0..4] of cardinal;
        Buffer: array[0..63] of uint8;
        BufCnt: uint32;
        Length: QWord;
    end;
    PSHA1Context = ^TSHA1Context;

{ Core }
procedure SHA1Init(ctx : PSHA1Context);
procedure SHA1Update(ctx : PSHA1Context; buffer : puint8; bufferLen : uint32 );
procedure SHA1Final(ctx : PSHA1Context; digest : PSHA1Digest);

implementation

uses
    core.util, arch.x86.util;

procedure Invert(Source, Dest: puint8; Count: uint32);
var
    S : puint8;
    T : PuInt32;
    I : uint32;

begin
    S:= source;
    T:= PuInt32(dest);
    for I:= 0 to (Count div 4) - 1 do begin
      T^:= S[3] or (S[2] shl 8) or (S[1] shl 16) or (S[0] shl 24);
      inc(S, 4);
      inc(T);
    end;
end;

procedure SHA1Init(ctx : PSHA1Context);
begin
    memset(uint32(ctx), 0, sizeof(TSHA1Context));
    ctx^.State[0] := $67452301;
    ctx^.State[1] := $EFCDAB89;
    ctx^.State[2] := $98BADCFE;
    ctx^.State[3] := $10325476;
    ctx^.State[4] := $C3D2E1F0;
end;

const
    K20 = $5A827999;
    K40 = $6ED9EBA1;
    K60 = $8F1BBCDC;
    K80 = $CA62C1D6;

procedure SHA1Transform(ctx : PSHA1Context; buffer : pointer);
var
    A, B, C, D, E, T: cardinal;
    Data: array[0..15] of cardinal;
    i: sint32;

begin
    A:= ctx^.State[0];
    B:= ctx^.State[1];
    C:= ctx^.State[2];
    D:= ctx^.State[3];
    E:= ctx^.State[4];
    Invert(puint8(buffer), puint8(@Data), 64);

    i:= 0;
    repeat
        T:= (B and C) or (not B and D) + K20 + E;
        E:= D;
        D:= C;
        C:= RorDWord(B, 2);
        B:= A;
        A:= T + RolDWord(A, 5) + Data[i and 15];
        Data[i and 15]:= RolDword(Data[i and 15] xor Data[(i+2) and 15] xor Data[(i+8) and 15] xor Data[(i+13) and 15], 1);
        Inc(i);
    until i > 19;

    repeat
        T:= (B xor C xor D) + K40 + E;
        E:= D;
        D:= C;
        C:= RorDWord(B, 2);
        B:= A;
        A:= T + RolDWord(A, 5) + Data[i and 15];
        Data[i and 15]:= RolDword(Data[i and 15] xor Data[(i+2) and 15] xor Data[(i+8) and 15] xor Data[(i+13) and 15], 1);
        Inc(i);
    until i > 39;

    repeat
        T:= (B and C) or (B and D) or (C and D) + K60 + E;
        E:= D;
        D:= C;
        C:= RorDWord(B, 2);
        B:= A;
        A:= T + RolDWord(A, 5) + Data[i and 15];
        Data[i and 15]:= RolDword(Data[i and 15] xor Data[(i+2) and 15] xor Data[(i+8) and 15] xor Data[(i+13) and 15], 1);
        Inc(i);
    until i > 59;

    repeat
        T:= (B xor C xor D) + K80 + E;
        E:= D;
        D:= C;
        C:= RorDWord(B, 2);
        B:= A;
        A:= T + RolDWord(A, 5) + Data[i and 15];
        Data[i and 15]:= RolDword(Data[i and 15] xor Data[(i+2) and 15] xor Data[(i+8) and 15] xor Data[(i+13) and 15], 1);
        Inc(i);
    until i > 79;

    Inc(ctx^.State[0], A);
    Inc(ctx^.State[1], B);
    Inc(ctx^.State[2], C);
    Inc(ctx^.State[3], D);
    Inc(ctx^.State[4], E);

    Inc(ctx^.Length, 64);
end;

procedure SHA1Update(ctx : PSHA1Context; buffer : puint8; bufferLen : uint32 );
var
    Src: puint8;
    Num: uint32;

begin
    if bufferLen = 0 then exit;

    Src:= buffer;
    Num:= 0;

    if ctx^.BufCnt > 0 then begin
        Num:= 64 - ctx^.BufCnt;
        if Num > bufferLen then Num:= bufferLen;
        
        Move(Src^, ctx^.Buffer[ctx^.BufCnt], Num);
        Inc(ctx^.BufCnt, Num);
        Inc(Src, Num);

        if ctx^.BufCnt = 64 then begin
            SHA1Transform(ctx, @ctx^.Buffer);
            ctx^.BufCnt:= 0;
        end;
    end;

    Num:= BufferLen - Num;
    while Num >= 64 do begin
        SHA1Transform(ctx, Src);
        Inc(Src, 64);
        Dec(Num, 64);
    end;

    if Num > 0 then begin
        ctx^.BufCnt:= Num;
        Move(Src^, ctx^.Buffer, Num);
    end;
end;

const
    Padding: array[0..63] of uint8 = (
        $80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    );

procedure SHA1Final(ctx : PSHA1Context; digest : PSHA1Digest);
var
    PadLen: uint32;
    Bits: QWord;
    LenBuf: array[0..7] of uint8;

begin
    { Calculate total bit length }
    Bits := (ctx^.Length + ctx^.BufCnt) * 8;

    { Determine padding length }
    if ctx^.BufCnt >= 56 then
        PadLen := 120 - ctx^.BufCnt
    else
        PadLen := 56 - ctx^.BufCnt;

    { Append padding }
    SHA1Update(ctx, @Padding[0], PadLen);

    { Append length in big-endian }
    LenBuf[0] := uint8(Bits shr 56);
    LenBuf[1] := uint8(Bits shr 48);
    LenBuf[2] := uint8(Bits shr 40);
    LenBuf[3] := uint8(Bits shr 32);
    LenBuf[4] := uint8(Bits shr 24);
    LenBuf[5] := uint8(Bits shr 16);
    LenBuf[6] := uint8(Bits shr 8);
    LenBuf[7] := uint8(Bits);
    SHA1Update(ctx, @LenBuf[0], 8);

    { Convert state to big-endian digest }
    Invert(puint8(@ctx^.State[0]), puint8(digest), 20);

    { Clear context }
    memset(uint32(ctx), 0, SizeOf(TSHA1Context));
end;

end.