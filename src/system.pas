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
    UBit2 = 0..(1 shl 2) - 1;
    UBit3 = 0..(1 shl 3) - 1;
    UBit4 = 0..(1 shl 4) - 1;
    UBit5 = 0..(1 shl 5) - 1;
    UBit6 = 0..(1 shl 6) - 1;
    UBit7 = 0..(1 shl 7) - 1;
    UBit20 = 0..(1 shl 20) - 1;

implementation

end.
