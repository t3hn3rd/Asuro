unit idt;

interface

uses
    util;

const
     ISR_RING_0 = $8E;
     ISR_RING_1 = $AE;
     ISR_RING_2 = $CE;
     ISR_RING_3 = $EE;

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
    IDT_Entries : Array [0..255] of TIDT_Entry;
    IDT_Pointer : TIDT_Pointer;

procedure init();
procedure set_gate(Number : uint8; Base : uint32; Selector : uint16; Flags : uint8);

implementation

procedure set_gate(Number : uint8; Base : uint32; Selector : uint16; Flags : uint8);
begin
    IDT_Entries[Number].base_high:= (Base and $FFFF0000) SHR 16;
    IDT_Entries[Number].base_low:= (Base and $0000FFFF);
    IDT_Entries[Number].selector:= Selector;
    IDT_Entries[Number].flags:= Flags;
    IDT_Entries[Number].always_0:= $00;
end;

procedure load(idt_pointer : uint32); assembler; nostackframe;
asm
    MOV EAX, idt_pointer
    LIDT [EAX]
end;

procedure init();
begin
    IDT_Pointer.limit:= (sizeof(TIDT_Entry) * 256) - 1;
    IDT_Pointer.base:= uint32(@IDT_Entries);
    util.memset(uint32(@IDT_Entries), 0, sizeof(TIDT_Entry) * 256);
    load(uint32(@IDT_Pointer));
end;

end.