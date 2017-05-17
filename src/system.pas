unit system;

interface

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

implementation

end.
