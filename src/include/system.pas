{ ************************************************
  * Asuro
  * Unit: system
  * Description: Standard System Types
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit system;

interface

const
     KERNEL_VIRTUAL_BASE = $C0000000;
     KERNEL_PAGE_NUMBER = KERNEL_VIRTUAL_BASE SHR 22;
     BSOD_ENABLE = true;
     TRACER_ENABLE = true;
     CONSOLE_SLOW_REDRAW = false; //Redraws the Window manager after every character, but slows performance.
     TRACE_TO_SERIAL = true;

type
    //internal types
    cardinal = 0..$FFFFFFFF;
    hresult = cardinal;
    dword = cardinal;
    integer = longint;
 
    pchar = ^char;

    //Standard Types
    uInt8  = BYTE;
    uInt16 = WORD;
    uInt32 = DWORD;
    uInt64 = QWORD;

    sInt8 = shortint;
    sInt16 = smallint;
    sInt32 = integer;
    sInt64 = longint;

    Float = Single;
 
    //Pointer Types
    PuByte = ^Byte;
    PuInt8 = PuByte;
    PuInt16 = ^uInt16;
    PuInt32 = ^uInt32;
    PuInt64 = ^uInt64;

    PsInt8 = ^sInt8;
    PsInt16 = ^sInt16;
    PsInt32 = ^sInt32;
    PsInt64 = ^sInt64;

    PFloat = ^Float;
    PDouble = ^Double;

    Void = ^uInt32;

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

implementation

end.
