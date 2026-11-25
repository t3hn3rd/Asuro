unit core.fmt.cbor;

{$MODESWITCH RESULT}
{$POINTERMATH ON}

interface

const
    CBOR_MAX_DEPTH = 64;

type
    TCBORStatus = (cborOK, cborNeedInput, cborNeedOutput, cborInvalid,
                   cborUnsupported, cborDepthLimit);
    TCBORKind = (cborUnsigned, cborNegative, cborBytes, cborText,
                 cborArray, cborMap, cborFalse, cborTrue, cborNull,
                 cborUndefined, cborTag, cborSimple, cborFloat16, cborFloat32,
                 cborFloat64, cborIndefiniteBytes, cborIndefiniteText,
                 cborIndefiniteArray, cborIndefiniteMap, cborBreak);
    TCBORHead = record
        Kind : TCBORKind;
        Argument : QWord;
    end;

{ Make a header or convert a native signed integer without overflow. }
function MakeHead(kind : TCBORKind; argument : QWord) : TCBORHead;
function IntegerHead(value : Int64) : TCBORHead;
function TryGetInteger(const head : TCBORHead; var value : Int64) : Boolean;

{ Float headers retain raw IEEE 754 bits, including NaN payloads.
  These helpers convert native values to headers and widen any CBOR float
  to Double. Use Argument directly when the exact encoding matters. }
function SingleHead(value : Single) : TCBORHead;
function DoubleHead(value : Double) : TCBORHead;
function TryGetFloat(const head : TCBORHead; var value : Double) : Boolean;

{ Read or write one wire header and advance offset on success.
  Argument holds an unsigned value, -1 minus a negative value, a string
  length in bytes, an array element count, a map pair count, a tag number,
  a simple value number, or raw float bits. Other kinds require zero.
  WriteHead uses shortest integer/length/tag encodings. Container structure,
  break placement, and payloads are handled separately. }
function ReadHead(buffer : PUInt8; size : SizeUInt; var offset : SizeUInt;
                  var head : TCBORHead) : TCBORStatus;
function WriteHead(buffer : PUInt8; size : SizeUInt; var offset : SizeUInt;
                   const head : TCBORHead) : TCBORStatus;

{ Read or write a complete byte/text string. ReadString returns a borrowed
  view into the input buffer. WriteString takes a non-overlapping source.
  Both validate UTF-8 for text. On failure, offsets and read outputs are
  unchanged, and writes leave the output buffer unchanged. }
function ReadString(buffer : PUInt8; size : SizeUInt; var offset : SizeUInt;
                    var payload : PUInt8; var length : SizeUInt;
                    var kind : TCBORKind) : TCBORStatus;
function WriteString(buffer : PUInt8; size : SizeUInt; var offset : SizeUInt;
                     payload : PUInt8; length : SizeUInt;
                     kind : TCBORKind) : TCBORStatus;

{ Validate a UTF-8 payload without a CBOR header. }
function ValidUTF8(payload : PUInt8; length : SizeUInt) : Boolean;

{ Skip exactly one structurally complete item, checking UTF-8. The offset
  changes only on success. Validate requires exactly one item in the buffer.
  Map-key uniqueness and tag-specific semantics belong to the application. }
function SkipItem(buffer : PUInt8; size : SizeUInt;
                  var offset : SizeUInt) : TCBORStatus;
function Validate(buffer : PUInt8; size : SizeUInt) : TCBORStatus;

implementation

type
    TSingleBits = packed record
        case Boolean of
            False: (Number : Single);
            True: (Bits : LongWord);
    end;
    TDoubleBits = packed record
        case Boolean of
            False: (Number : Double);
            True: (Bits : QWord);
    end;

function MakeHead(kind : TCBORKind; argument : QWord) : TCBORHead;
begin
    Result.Kind := kind;
    Result.Argument := argument;
end;

function IntegerHead(value : Int64) : TCBORHead;
begin
    if value < 0 then Result := MakeHead(cborNegative, QWord(-1 - value))
    else Result := MakeHead(cborUnsigned, QWord(value));
end;

function TryGetInteger(const head : TCBORHead; var value : Int64) : Boolean;
begin
    Result := False;
    if head.Argument > QWord(High(Int64)) then Exit;
    case head.Kind of
        cborUnsigned: value := Int64(head.Argument);
        cborNegative: value := -1 - Int64(head.Argument);
    else
        Exit;
    end;
    Result := True;
end;

function SingleHead(value : Single) : TCBORHead;
var
    raw : TSingleBits;
begin
    raw.Number := value;
    Result := MakeHead(cborFloat32, raw.Bits);
end;

function DoubleHead(value : Double) : TCBORHead;
var
    raw : TDoubleBits;
begin
    raw.Number := value;
    Result := MakeHead(cborFloat64, raw.Bits);
end;

function TryGetFloat(const head : TCBORHead; var value : Double) : Boolean;
var
    raw : TDoubleBits;
    fraction, exponent, bias : QWord;
    fractionBits : Byte;
begin
    Result := False;
    case head.Kind of
        cborFloat16: begin
            if head.Argument > $FFFF then Exit;
            fractionBits := 10;
            bias := 15;
        end;
        cborFloat32: begin
            if head.Argument > QWord($FFFFFFFF) then Exit;
            fractionBits := 23;
            bias := 127;
        end;
        cborFloat64: begin
            raw.Bits := head.Argument;
            value := raw.Number;
            Result := True;
            Exit;
        end;
    else
        Exit;
    end;

    fraction := head.Argument and ((QWord(1) shl fractionBits) - 1);
    exponent := (head.Argument shr fractionBits) and (bias * 2 + 1);
    if head.Kind = cborFloat16 then raw.Bits := (head.Argument shr 15) shl 63
    else raw.Bits := (head.Argument shr 31) shl 63;
    if exponent = bias * 2 + 1 then exponent := 2047
    else if exponent <> 0 then exponent := exponent + 1023 - bias
    else if fraction <> 0 then begin
        exponent := 1024 - bias;
        while (fraction and (QWord(1) shl fractionBits)) = 0 do begin
            fraction := fraction shl 1;
            Dec(exponent);
        end;
        fraction := fraction and ((QWord(1) shl fractionBits) - 1);
    end;
    raw.Bits := raw.Bits or (exponent shl 52) or
                (fraction shl (52 - fractionBits));
    value := raw.Number;
    Result := True;
end;

function ReadHead(buffer : PUInt8; size : SizeUInt; var offset : SizeUInt;
                  var head : TCBORHead) : TCBORStatus;
var
    major, info, width, i : Byte;
    decoded : TCBORHead;
begin
    Result := cborInvalid;
    if offset > size then Exit;
    if (buffer = nil) and (size <> 0) then Exit;
    Result := cborNeedInput;
    if offset = size then Exit;

    major := buffer[offset] shr 5;
    info := buffer[offset] and $1F;
    Result := cborInvalid;
    if (info >= 28) and (info <= 30) then Exit;

    width := 0;
    decoded.Argument := 0;
    if info = 31 then begin
        case major of
            2..5: decoded.Kind := TCBORKind(Ord(cborIndefiniteBytes) + major - 2);
            7: decoded.Kind := cborBreak;
        else
            Exit;
        end;
    end else if major = 7 then begin
        case info of
            20..23: decoded.Kind := TCBORKind(Ord(cborFalse) + info - 20);
            25..27: decoded.Kind := TCBORKind(Ord(cborFloat16) + info - 25);
        else
            decoded.Kind := cborSimple;
            if info < 20 then decoded.Argument := info;
        end;
    end else begin
        if major = 6 then decoded.Kind := cborTag
        else decoded.Kind := TCBORKind(major);
        if info < 24 then decoded.Argument := info;
    end;

    if (info >= 24) and (info <= 27) then width := 1 shl (info - 24);
    Result := cborNeedInput;
    if size - offset - 1 < width then Exit;
    for i := 1 to width do
        decoded.Argument := (decoded.Argument shl 8) or buffer[offset + i];
    if (major = 7) and (info = 24) and (decoded.Argument < 32) then begin
        Result := cborInvalid;
        Exit;
    end;

    Inc(offset, 1 + width);
    head := decoded;
    Result := cborOK;
end;

function ArgumentWidth(value : QWord) : Byte;
begin
    if value < 24 then Result := 0
    else if value <= $FF then Result := 1
    else if value <= $FFFF then Result := 2
    else if value <= QWord($FFFFFFFF) then Result := 4
    else Result := 8;
end;

function WriteHead(buffer : PUInt8; size : SizeUInt; var offset : SizeUInt;
                   const head : TCBORHead) : TCBORStatus;
var
    first, major, width, info, i : Byte;
    value : QWord;
begin
    Result := cborInvalid;
    if offset > size then Exit;
    if (buffer = nil) and (size <> 0) then Exit;

    value := head.Argument;
    width := 0;
    case head.Kind of
        cborUnsigned..cborMap, cborTag: begin
            if head.Kind = cborTag then major := 6
            else major := Ord(head.Kind);
            width := ArgumentWidth(value);
            case width of
                0: info := Byte(value);
                1: info := 24;
                2: info := 25;
                4: info := 26;
            else
                info := 27;
            end;
            first := (major shl 5) or info;
        end;
        cborFalse..cborUndefined: begin
            if value <> 0 then Exit;
            first := $F4 + Ord(head.Kind) - Ord(cborFalse);
        end;
        cborSimple: begin
            if value < 20 then first := $E0 + Byte(value)
            else begin
                if (value < 32) or (value > 255) then Exit;
                first := $F8;
                width := 1;
            end;
        end;
        cborFloat16..cborFloat64: begin
            info := Ord(head.Kind) - Ord(cborFloat16);
            width := 2 shl info;
            if width < 8 then
                if (value shr (8 * width)) <> 0 then Exit;
            first := $F9 + info;
        end;
        cborIndefiniteBytes..cborIndefiniteMap: begin
            if value <> 0 then Exit;
            major := Ord(head.Kind) - Ord(cborIndefiniteBytes) + 2;
            first := (major shl 5) or $1F;
        end;
        cborBreak: begin
            if value <> 0 then Exit;
            first := $FF;
        end;
    else
        Exit;
    end;

    Result := cborNeedOutput;
    if size - offset < 1 + width then Exit;
    buffer[offset] := first;
    for i := width downto 1 do begin
        buffer[offset + i] := Byte(value and $FF);
        value := value shr 8;
    end;
    Inc(offset, 1 + width);
    Result := cborOK;
end;

function ValidUTF8(payload : PUInt8; length : SizeUInt) : Boolean;
var
    pos : SizeUInt;
    first, next, remaining, minimum, maximum : Byte;
begin
    Result := False;
    if (payload = nil) and (length <> 0) then Exit;
    pos := 0;
    while pos < length do begin
        first := payload[pos];
        Inc(pos);
        if first < $80 then Continue;

        minimum := $80;
        maximum := $BF;
        case first of
            $C2..$DF: remaining := 1;
            $E0..$EF: begin
                remaining := 2;
                if first = $E0 then minimum := $A0;
                if first = $ED then maximum := $9F;
            end;
            $F0..$F4: begin
                remaining := 3;
                if first = $F0 then minimum := $90;
                if first = $F4 then maximum := $8F;
            end;
        else
            Exit;
        end;
        if length - pos < remaining then Exit;
        while remaining <> 0 do begin
            next := payload[pos];
            if (next < minimum) or (next > maximum) then Exit;
            minimum := $80;
            maximum := $BF;
            Inc(pos);
            Dec(remaining);
        end;
    end;
    Result := True;
end;

function ReadString(buffer : PUInt8; size : SizeUInt; var offset : SizeUInt;
                    var payload : PUInt8; var length : SizeUInt;
                    var kind : TCBORKind) : TCBORStatus;
var
    head : TCBORHead;
    pos, count : SizeUInt;
begin
    pos := offset;
    Result := ReadHead(buffer, size, pos, head);
    if Result <> cborOK then Exit;
    Result := cborInvalid;
    if head.Kind in [cborIndefiniteBytes, cborIndefiniteText] then begin
        Result := cborUnsupported;
        Exit;
    end;
    if (head.Kind <> cborBytes) and (head.Kind <> cborText) then Exit;

    Result := cborNeedInput;
    if head.Argument > QWord(size - pos) then Exit;
    count := SizeUInt(head.Argument);
    if head.Kind = cborText then begin
        Result := cborInvalid;
        if not ValidUTF8(buffer + pos, count) then Exit;
    end;
    payload := buffer + pos;
    length := count;
    kind := head.Kind;
    offset := pos + count;
    Result := cborOK;
end;

function WriteString(buffer : PUInt8; size : SizeUInt; var offset : SizeUInt;
                     payload : PUInt8; length : SizeUInt;
                     kind : TCBORKind) : TCBORStatus;
var
    head : TCBORHead;
    headerSize, i : SizeUInt;
begin
    Result := cborInvalid;
    if (kind <> cborBytes) and (kind <> cborText) then Exit;
    if (payload = nil) and (length <> 0) then Exit;
    if (buffer = nil) and (size <> 0) then Exit;
    if offset > size then Exit;

    headerSize := 1 + ArgumentWidth(length);
    Result := cborNeedOutput;
    if headerSize > size - offset then Exit;
    if length > size - offset - headerSize then Exit;
    if kind = cborText then begin
        Result := cborInvalid;
        if not ValidUTF8(payload, length) then Exit;
    end;

    head.Kind := kind;
    head.Argument := length;
    Result := WriteHead(buffer, size, offset, head);
    if Result <> cborOK then Exit;
    i := 0;
    while i < length do begin
        buffer[offset + i] := payload[i];
        Inc(i);
    end;
    Inc(offset, length);
end;

function SkipItem(buffer : PUInt8; size : SizeUInt;
                  var offset : SizeUInt) : TCBORStatus;
type
    TFrame = record
        Remaining : QWord;
        Kind : TCBORKind;
        AwaitingValue : Boolean;
    end;
var
    frames : array[0..CBOR_MAX_DEPTH] of TFrame;
    depth : SizeUInt;
    pos, count : SizeUInt;
    head : TCBORHead;
    parent : TCBORKind;
begin
    pos := offset;
    depth := 0;
    frames[0].Kind := cborArray;
    frames[0].Remaining := 1;
    frames[0].AwaitingValue := False;

    repeat
        parent := frames[depth].Kind;
        if (parent in [cborArray, cborMap, cborTag]) and
           (frames[depth].Remaining = 0) then begin
            if depth = 0 then Break;
            Dec(depth);
            Continue;
        end;

        Result := ReadHead(buffer, size, pos, head);
        if Result <> cborOK then Exit;
        Result := cborInvalid;
        if head.Kind = cborBreak then begin
            if not (parent in [cborIndefiniteBytes..cborIndefiniteMap]) then Exit;
            if frames[depth].AwaitingValue then Exit;
            Dec(depth);
            Continue;
        end;

        case parent of
            cborIndefiniteBytes: if head.Kind <> cborBytes then Exit;
            cborIndefiniteText: if head.Kind <> cborText then Exit;
            cborArray, cborTag: Dec(frames[depth].Remaining);
            cborMap, cborIndefiniteMap: begin
                if frames[depth].AwaitingValue and (parent = cborMap) then
                    Dec(frames[depth].Remaining);
                frames[depth].AwaitingValue := not frames[depth].AwaitingValue;
            end;
        end;

        case head.Kind of
            cborBytes, cborText: begin
                Result := cborNeedInput;
                if head.Argument > QWord(size - pos) then Exit;
                count := SizeUInt(head.Argument);
                Result := cborInvalid;
                if head.Kind = cborText then
                    if not ValidUTF8(buffer + pos, count) then Exit;
                Inc(pos, count);
            end;
            cborArray, cborMap, cborTag,
            cborIndefiniteBytes..cborIndefiniteMap: begin
                if (head.Kind in [cborArray, cborMap]) and
                   (head.Argument = 0) then Continue;
                Result := cborDepthLimit;
                if depth = CBOR_MAX_DEPTH then Exit;
                Inc(depth);
                frames[depth].Kind := head.Kind;
                frames[depth].Remaining := head.Argument;
                if head.Kind = cborTag then frames[depth].Remaining := 1;
                frames[depth].AwaitingValue := False;
            end;
        end;
    until False;
    offset := pos;
    Result := cborOK;
end;

function Validate(buffer : PUInt8; size : SizeUInt) : TCBORStatus;
var
    offset : SizeUInt;
begin
    offset := 0;
    Result := SkipItem(buffer, size, offset);
    if (Result = cborOK) and (offset <> size) then Result := cborInvalid;
end;

end.
