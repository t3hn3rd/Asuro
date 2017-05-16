unit idt;

interface

uses
    system,
    types;

type
    TIDT_Entry = bitpacked record
        base_low  : uint16;
        selector  : uint16;
        always_0  : uint8;
        flags     : uint8;
        base_high : uint16; 
    end;
    PIDT_Entry = ^TIDT_Entry;

    TIDT_Pointer = bitpacked record
        limit : uint16;
        base  : uint32;
    end;
    PIDT_Pointer = ^TIDT_Pointer;

var
    IDT : Array [0..255] of TIDT_Entry;
    IDT_Pointer : TIDT_Pointer;

implementation

end.