unit core.fmt.cbor.tests;

{$MODESWITCH RESULT}
{$POINTERMATH ON}

interface

procedure UnitTest;

implementation

uses
    core.fmt.cbor, test.harness;

const
    { RFC 8949, Appendix A and Appendix F.1. }
    ValidVectors : array[0..80] of PChar = (
        '00',
        '01',
        '0a',
        '17',
        '1818',
        '1819',
        '1864',
        '1903e8',
        '1a000f4240',
        '1b000000e8d4a51000',
        '1bffffffffffffffff',
        'c249010000000000000000',
        '3bffffffffffffffff',
        'c349010000000000000000',
        '20',
        '29',
        '3863',
        '3903e7',
        'f90000',
        'f98000',
        'f93c00',
        'fb3ff199999999999a',
        'f93e00',
        'f97bff',
        'fa47c35000',
        'fa7f7fffff',
        'fb7e37e43c8800759c',
        'f90001',
        'f90400',
        'f9c400',
        'fbc010666666666666',
        'f97c00',
        'f97e00',
        'f9fc00',
        'fa7f800000',
        'fa7fc00000',
        'faff800000',
        'fb7ff0000000000000',
        'fb7ff8000000000000',
        'fbfff0000000000000',
        'f4',
        'f5',
        'f6',
        'f7',
        'f0',
        'f8ff',
        'c074323031332d30332d32315432303a30343a30305a',
        'c11a514b67b0',
        'c1fb41d452d9ec200000',
        'd74401020304',
        'd818456449455446',
        'd82076687474703a2f2f7777772e6578616d706c652e636f6d',
        '40',
        '4401020304',
        '60',
        '6161',
        '6449455446',
        '62225c',
        '62c3bc',
        '63e6b0b4',
        '64f0908591',
        '80',
        '83010203',
        '8301820203820405',
        '98190102030405060708090a0b0c0d0e0f101112131415161718181819',
        'a0',
        'a201020304',
        'a26161016162820203',
        '826161a161626163',
        'a56161614161626142616361436164614461656145',
        '5f42010243030405ff',
        '7f657374726561646d696e67ff',
        '9fff',
        '9f018202039f0405ffff',
        '9f01820203820405ff',
        '83018202039f0405ff',
        '83019f0203ff820405',
        '9f0102030405060708090a0b0c0d0e0f101112131415161718181819ff',
        'bf61610161629f0203ffff',
        '826161bf61626163ff',
        'bf6346756ef563416d7421ff'
    );
    TruncatedVectors : array[0..41] of PChar = (
        '18',
        '19',
        '1a',
        '1b',
        '1901',
        '1a0102',
        '1b01020304050607',
        '38',
        '58',
        '78',
        '98',
        '9a01ff00',
        'b8',
        'd8',
        'f8',
        'f900',
        'fa0000',
        'fb000000',
        '41',
        '61',
        '5affffffff00',
        '5bffffffffffffffff010203',
        '7affffffff00',
        '7b7fffffffffffffff010203',
        '81',
        '818181818181818181',
        '8200',
        'a1',
        'a20102',
        'a100',
        'a2000000',
        'c0',
        '5f4100',
        '7f6100',
        '9f',
        '9f0102',
        'bf',
        'bf01020102',
        '819f',
        '9f8000',
        '9f9f9f9f9fffffffff',
        '9f819f819f9fffffff'
    );
    InvalidVectors : array[0..51] of PChar = (
        '1c',
        '1d',
        '1e',
        '3c',
        '3d',
        '3e',
        '5c',
        '5d',
        '5e',
        '7c',
        '7d',
        '7e',
        '9c',
        '9d',
        '9e',
        'bc',
        'bd',
        'be',
        'dc',
        'dd',
        'de',
        'fc',
        'fd',
        'fe',
        'f800',
        'f801',
        'f818',
        'f81f',
        '5f00ff',
        '5f21ff',
        '5f6100ff',
        '5f80ff',
        '5fa0ff',
        '5fc000ff',
        '5fe0ff',
        '7f4100ff',
        '5f5f4100ffff',
        '7f7f6100ffff',
        'ff',
        '81ff',
        '8200ff',
        'a1ff',
        'a1ff00',
        'a100ff',
        'a20000ff',
        '9f81ff',
        '9f829f819f9fffffffff',
        'bf00ff',
        'bf000000ff',
        '1f',
        '3f',
        'df'
    );

    { Invalid UTF-8, including a code point split across text chunks. }
    InvalidText : array[0..5] of PChar = (
        '62c0ae',
        '63eda080',
        '64f4908080',
        '62e282',
        '6180',
        '7f61c261a2ff'
    );

type
    TBuffer = array[0..63] of Byte;

function HexDigit(digit : Char) : Byte;
begin
    if digit <= '9' then Result := Ord(digit) - Ord('0')
    else Result := Ord(digit) - Ord('a') + 10;
end;

function FromHex(hex : PChar; var buffer : TBuffer) : SizeUInt;
begin
    Result := 0;
    while hex^ <> #0 do begin
        buffer[Result] := (HexDigit(hex[0]) shl 4) or HexDigit(hex[1]);
        Inc(Result);
        Inc(hex, 2);
    end;
end;

function RoundTrip(var input : TBuffer; size : SizeUInt) : Boolean;
var
    output : TBuffer;
    readPos, writePos, start, length, i : SizeUInt;
    head : TCBORHead;
    kind : TCBORKind;
    payload : PUInt8;
begin
    Result := False;
    readPos := 0;
    writePos := 0;
    while readPos < size do begin
        start := readPos;
        if ReadHead(@input[0], size, readPos, head) <> cborOK then Exit;
        if head.Kind in [cborBytes, cborText] then begin
            readPos := start;
            if ReadString(@input[0], size, readPos, payload, length, kind) <> cborOK then Exit;
            if core.fmt.cbor.WriteString(@output[0], SizeOf(output), writePos,
                           payload, length, kind) <> cborOK then Exit;
        end else if WriteHead(@output[0], SizeOf(output), writePos, head) <> cborOK then Exit;
    end;
    if writePos <> size then Exit;
    for i := 1 to size do
        if input[i - 1] <> output[i - 1] then Exit;
    Result := True;
end;

procedure UnitTest;
var
    buffer : TBuffer;
    nested : array[0..CBOR_MAX_DEPTH + 1] of Byte;
    head : TCBORHead;
    kind : TCBORKind;
    payload : PUInt8;
    size, offset, payloadLength, prefix : SizeUInt;
    i : LongInt;
    context : TTestContext;
    signedValue : Int64;
    floatValue : Double;

begin
    test.harness.Start(@context, 'core.fmt.cbor');
    for i := Low(ValidVectors) to High(ValidVectors) do begin
        size := FromHex(ValidVectors[i], buffer);
        test.harness.Assert(@context, Validate(@buffer[0], size) = cborOK, ValidVectors[i]);
        test.harness.Assert(@context, RoundTrip(buffer, size), ValidVectors[i]);
        for prefix := 0 to size - 1 do
            test.harness.Assert(@context, Validate(@buffer[0], prefix) = cborNeedInput, ValidVectors[i]);
    end;
    for i := Low(TruncatedVectors) to High(TruncatedVectors) do begin
        size := FromHex(TruncatedVectors[i], buffer);
        test.harness.Assert(@context, Validate(@buffer[0], size) = cborNeedInput, TruncatedVectors[i]);
    end;
    for i := Low(InvalidVectors) to High(InvalidVectors) do begin
        size := FromHex(InvalidVectors[i], buffer);
        test.harness.Assert(@context, Validate(@buffer[0], size) = cborInvalid, InvalidVectors[i]);
    end;
    for i := Low(InvalidText) to High(InvalidText) do begin
        size := FromHex(InvalidText[i], buffer);
        test.harness.Assert(@context, Validate(@buffer[0], size) = cborInvalid, InvalidText[i]);
    end;

    size := FromHex('001801', buffer);
    test.harness.Assert(@context, Validate(@buffer[0], size) = cborInvalid, 'Reject trailing data');
    offset := 0;
    test.harness.Assert(@context, SkipItem(@buffer[0], size, offset) = cborOK, 'Skip first item');
    test.harness.Assert(@context, offset = 1, 'Skip stops at next item');
    test.harness.Assert(@context, ReadHead(@buffer[0], size, offset, head) = cborOK, 'Accept a non-preferred integer');
    test.harness.Assert(@context, (head.Kind = cborUnsigned) and (head.Argument = 1), 'Decode unsigned 1');

    size := FromHex('3bffffffffffffffff', buffer);
    offset := 0;
    test.harness.Assert(@context, ReadHead(@buffer[0], size, offset, head) = cborOK, 'Read minimum wire integer');
    test.harness.Assert(@context, (head.Kind = cborNegative) and (head.Argument = High(QWord)), 'Preserve 64-bit negative argument');
    test.harness.Assert(@context, not TryGetInteger(head, signedValue), 'Reject native integer overflow');
    head := IntegerHead(Low(Int64));
    test.harness.Assert(@context, TryGetInteger(head, signedValue), 'Read minimum native integer');
    test.harness.Assert(@context, signedValue = Low(Int64), 'Preserve minimum native integer');

    head := MakeHead(cborFloat16, $3E00);
    test.harness.Assert(@context, TryGetFloat(head, floatValue), 'Read binary16');
    test.harness.Assert(@context, DoubleHead(floatValue).Argument = QWord($3FF8000000000000), 'Widen binary16 1.5');
    head := MakeHead(cborFloat16, 1);
    test.harness.Assert(@context, TryGetFloat(head, floatValue), 'Read binary16 subnormal');
    test.harness.Assert(@context, DoubleHead(floatValue).Argument = QWord($3E70000000000000), 'Widen binary16 subnormal');
    head := SingleHead(1.5);
    test.harness.Assert(@context, head.Argument = $3FC00000, 'Encode binary32 1.5');
    test.harness.Assert(@context, TryGetFloat(head, floatValue), 'Read binary32');
    test.harness.Assert(@context, DoubleHead(floatValue).Argument = QWord($3FF8000000000000), 'Widen binary32 1.5');

    size := FromHex('0081ff', buffer);
    offset := 1;
    test.harness.Assert(@context, SkipItem(@buffer[0], size, offset) = cborInvalid, 'Reject break in definite array');
    test.harness.Assert(@context, offset = 1, 'Skip failure preserves offset');
    size := FromHex('64f09085', buffer);
    offset := 0;
    payloadLength := 17;
    payload := nil;
    kind := cborMap;
    test.harness.Assert(@context, ReadString(@buffer[0], size, offset, payload, payloadLength, kind) = cborNeedInput,
          'Incomplete string needs input');
    test.harness.Assert(@context, (offset = 0) and (payloadLength = 17) and (payload = nil) and (kind = cborMap),
          'Read failure preserves outputs');
    offset := 1;
    buffer[1] := $AA;
    test.harness.Assert(@context, core.fmt.cbor.WriteString(@buffer[0], 2, offset, @buffer[0], 1, cborBytes) = cborNeedOutput,
          'Short buffer needs output');
    test.harness.Assert(@context, (offset = 1) and (buffer[1] = $AA), 'Write failure preserves buffer and offset');
    test.harness.Assert(@context, WriteHead(@buffer[0], 2, offset, MakeHead(cborSimple, 24)) = cborInvalid,
          'Reject reserved simple value on write');
    test.harness.Assert(@context, WriteHead(@buffer[0], 2, offset, MakeHead(cborFloat16, $10000)) = cborInvalid,
          'Reject oversized binary16 on write');

    for i := 0 to CBOR_MAX_DEPTH do nested[i] := $81;
    nested[CBOR_MAX_DEPTH + 1] := 0;
    test.harness.Assert(@context, Validate(@nested[1], CBOR_MAX_DEPTH + 1) = cborOK, 'Accept depth limit');
    test.harness.Assert(@context, Validate(@nested[0], SizeOf(nested)) = cborDepthLimit, 'Report exceeded depth limit');

    test.harness.Finish(@context);
end;

end.
