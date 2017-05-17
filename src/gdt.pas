{ ************************************************
  * Asuro
  * Unit: GDT
  * Description: GDT Structure and Implementation
  ************************************************
  * Author: K Morris
  * Contributors: A Hance
  ************************************************ }

unit gdt;

interface

type
    TGDT_Entry = bitpacked record
        limit_low   : uint16;
        base_low    : uint16;
        base_middle : uint8;
        access      : uint8;
        granularity : uint8;
        base_high   : uint8;
    end;
    PGDT_Entry = ^TGDT_Entry;

    TGDT_Pointer = bitpacked record
        limit : uint16;
        base  : uint32;
    end;

var
    gdt_entries : array[0..4] of TGDT_Entry;
    gdt_pointer : TGDT_Pointer;

procedure init();
    
implementation

procedure flush_gdt(gdt_pointer : uint32); assembler; nostackframe;
asm
    MOV EAX, gdt_pointer
    LGDT [EAX]
    MOV AX, $10
    MOV DS, AX
    MOV ES, AX
    MOV FS, AX
    MOV GS, AX
    MOV SS, AX
    db $EA          // Bypass stupid inline ASM restrictions-
    dw @@flush, $08 // by assembling the farjump instruction ourselves.                    
@@flush:            // It's just data, honest gov'.
end;

procedure set_gate(Gate_Number : uint32; Base : uint32; Limit : uint32; Access : uint8; Granularity : uint8);
begin
    gdt_entries[Gate_Number].base_low    := (Base AND $FFFF);
    gdt_entries[Gate_Number].base_middle := (Base SHR 16) AND $FF;
    gdt_entries[Gate_Number].base_high   := (Base SHR 24) AND $FF;
    gdt_entries[Gate_Number].limit_low   := (Limit AND $FFFF);
    gdt_entries[Gate_Number].granularity := ((Limit SHR 16) AND $0F) OR (Granularity AND $F0);
    gdt_entries[Gate_Number].access      := Access;    
end;

procedure init();
begin
    gdt_pointer.limit := (sizeof(TGDT_Entry) * 5) - 1;
    gdt_pointer.base  := uint32(@gdt_entries);
    set_gate($00, $00, $00,       $00, $00);
    set_gate($01, $00, $FFFFFFFF, $9A, $CF);
    set_gate($02, $00, $FFFFFFFF, $92, $CF);
    set_gate($03, $00, $FFFFFFFF, $FA, $CF);
    set_gate($04, $00, $FFFFFFFF, $F2, $CF);
    flush_gdt(uint32(@gdt_pointer))
end;

end.