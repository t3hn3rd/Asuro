unit types;

interface

type
    //Standard Types
    Int8  = BYTE;
    Int16 = WORD;
    Int32 = DWORD;
    Int64 = QWORD;

    //Pointer Types
    PByte = ^Byte;
    PInt8 = PByte;
    PInt16 = ^Int16;
    PInt32 = ^Int32;
    PInt64 = ^Int64;

    Void = ^Int32;



implementation

end.
