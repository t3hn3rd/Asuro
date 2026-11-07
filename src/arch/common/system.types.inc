//  Copyright 2021 Kieron Morris & Aaron Hance
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

{ Shared compiler and scalar types. Included by each architecture system unit. }
type
    //internal core.types
    cardinal = 0..$FFFFFFFF;
    hresult = type longint;
    dword = cardinal;
    integer = longint;
    pchar = ^char;

    //Standard Types
    uInt8  = BYTE;
    uInt16 = WORD;
    uInt32 = DWORD;
    uInt64 = QWORD;
    uint128 = packed record
      case Integer of
        0: (
            Hi : uint64;
            Lo : uint64;
        );
        1: (
            DWords : array [0..3] of uint32;
        );
        2: (
            Words : array [0..7] of uint16;
        );
        3: (
            Bytes : array [0..15] of uint8;
        );
    end;

    sInt8 = shortint;
    sInt16 = smallint;
    sInt32 = integer;
    sInt64 = int64;

    Float = Single;

    //Pointer Types
    PuByte = ^Byte;
    PuInt8 = PuByte;
    PuInt16 = ^uInt16;
    PuInt32 = ^uInt32;
    PuInt64 = ^uInt64;
    PuInt128 = ^uint128;

    PsInt8 = ^sInt8;
    PsInt16 = ^sInt16;
    PsInt32 = ^sInt32;
    PsInt64 = ^sInt64;

    PFloat = ^Float;
    PDouble = ^Double;

    Void = ^uInt32;

    yord = uInt8;
    xord = uInt8;
    zord = uInt16;

    //Alternate Types
    UBit1 =  0..(1 shl 01) - 1;
    UBit2 =  0..(1 shl 02) - 1;
    UBit3 =  0..(1 shl 03) - 1;
    UBit4 =  0..(1 shl 04) - 1;
    UBit5 =  0..(1 shl 05) - 1;
    UBit6 =  0..(1 shl 06) - 1;
    UBit7 =  0..(1 shl 07) - 1;
    UBit9 =  0..(1 shl 09) - 1;
    UBit10 = 0..(1 shl 10) - 1;
    UBit11 = 0..(1 shl 11) - 1;
    UBit12 = 0..(1 shl 12) - 1;
    UBit13 = 0..(1 shl 13) - 1;
    UBit14 = 0..(1 shl 14) - 1;
    UBit15 = 0..(1 shl 15) - 1;
    UBit16 = 0..(1 shl 16) - 1;
    UBit17 = 0..(1 shl 17) - 1;
    UBit18 = 0..(1 shl 18) - 1;
    UBit19 = 0..(1 shl 19) - 1;
    UBit20 = 0..(1 shl 20) - 1;
    UBit21 = 0..(1 shl 21) - 1;
    UBit22 = 0..(1 shl 22) - 1;
    UBit23 = 0..(1 shl 23) - 1;
    UBit24 = 0..(1 shl 24) - 1;
    UBit25 = 0..(1 shl 25) - 1;
    UBit26 = 0..(1 shl 26) - 1;
    UBit27 = 0..(1 shl 27) - 1;
    UBit28 = 0..(1 shl 28) - 1;
    UBit30 = 0..(1 shl 30) - 1;
    UBit31 = 0..(1 shl 31) - 1;

    TBitMask = bitpacked record
      b0,b1,b2,b3,b4,b5,b6,b7 : Boolean;
    end;
    PBitMask = ^TBitMask;

    TMask = bitpacked array[0..7] of Boolean;
    PMask = ^TMask;

    PText = ^Text;

    { ---- Types required by FPC 3.2.2 compiler internals ---- }

    { Native widths follow the selected compiler target. Fixed-width types above
      remain unchanged for hardware descriptors and on-disk structures. }
    PtrInt = SizeInt;
    PtrUInt = SizeUInt;
    ValSInt = SizeInt;
    ValUInt = SizeUInt;
    NativeInt = SizeInt;
    NativeUInt = SizeUInt;
    CodePointer = Pointer;
    PCodePointer = ^CodePointer;
    PSizeInt = ^SizeInt;

    { RTTI type kind enumeration — must match compiler's internal list }
    TTypeKind = (
        tkUnknown, tkInteger, tkChar, tkEnumeration, tkFloat,
        tkSet, tkMethod, tkSString, tkLString, tkAString,
        tkWString, tkVariant, tkArray, tkRecord, tkInterface,
        tkClass, tkObject, tkWChar, tkBool, tkInt64,
        tkQWord, tkDynArray, tkInterfaceRaw, tkProcVar, tkUString,
        tkUChar, tkHelper, tkFile, tkClassRef, tkPointer
    );

    { GUID record — required by compiler for interface support }
    PGuid = ^TGuid;
    TGuid = packed record
        case Integer of
            1: (Data1: DWord; Data2: Word; Data3: Word; Data4: array[0..7] of Byte);
            2: (D1: DWord; D2: Word; D3: Word; D4: array[0..7] of Byte);
            3: (time_low: DWord; time_mid: Word; time_hi_and_version: Word;
                clock_seq_hi_and_reserved: Byte; clock_seq_low: Byte;
                node: array[0..5] of Byte);
    end;

    { File record core.types — required by compiler for file I/O internals }
    FileRec = packed record
        Handle    : longint;
        Mode      : longint;
        RecSize   : SizeInt;
        _private  : array[0..31] of byte;
        UserData  : array[0..31] of byte;
        name      : array[0..255] of char;
    end;
    PFileRec = ^FileRec;

    TextBuf = array[0..255] of char;
    TextRec = packed record
        Handle    : longint;
        Mode      : longint;
        BufSize   : SizeInt;
        _private  : SizeInt;
        BufPos    : SizeInt;
        BufEnd    : SizeInt;
        BufPtr    : ^TextBuf;
        OpenFunc  : CodePointer;
        InOutFunc : CodePointer;
        FlushFunc : CodePointer;
        CloseFunc : CodePointer;
        UserData  : array[0..31] of byte;
        name      : array[0..255] of char;
        LineEnd   : array[0..3] of char;
        Buffer    : TextBuf;
    end;
    PTextRec = ^TextRec;

    { FPC 3.2.2 INITFINAL table — compiler-generated unit init/finalize table.
      Each unit with an initialization or finalization section gets an entry.
      The table is emitted by the compiler under the symbol 'INITFINAL'. }
    TInitFinalRec = packed record
        InitProc : CodePointer;
        FinalProc: CodePointer;
    end;

    TInitFinalTable = packed record
        TableCount : longint;
        Procs      : array[1..1] of TInitFinalRec; { open array, actual size = TableCount }
    end;
    PInitFinalTable = ^TInitFinalTable;

    { Procedure type for calling initialization procs from the INITFINAL table }
    TProcedure = procedure;
