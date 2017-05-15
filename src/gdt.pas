unit gdt;
    
interface

uses
    util;

type 
    TSegementDescriptor = bitpacked record
        limit_low     : WORD;
        base_low      : WORD;
        access        : Byte;
        limit_n_flags : Byte;
        base_high     : Byte;
    end;

var
    GDTarr : array[0..3] of TSegementDescriptor;
    GDTptr : ^TSegementDescriptor;    
    GDT_length : integer = 0;

    procedure init();
    procedure create(base : dword; limit : dword; flags : byte);
    
implementation

procedure init(); 
var 
    data_addr : dword;
begin
    GDTptr := @GDTarr[0];
    data_addr := (@GDTarr[2] - @GDTarr[0]) shr 16;
    create($0000, $0000, $00); //null segment / GDT pointer
    create($0000, $FFFF, $9A); //code descriptor
    create($0000, $FFFF, $92); //data descriptor
    asm
        LGDT GDTptr
        MOV AX, data_addr
        MOV DS, AX
        MOV SS, AX
        MOV ES, AX
        MOV FS, AX
        MOV GS, AX
    end;
end;
    
procedure create(base : dword; limit : dword; flags : byte);
var
    descriptor : array[0..8] of Byte;
    descriptor_ptr : ^Byte = @descriptor[0];
    s_descriptor : TSegementDescriptor;
    s_descriptor_ptr : ^TSegementDescriptor = @s_descriptor;
begin
    if limit <= 65536 then
        descriptor[6] := $40
    else
        if (limit and $FFF) <> $FFF then
            limit := (limit >> 12) -1
        else
            limit := limit >> 12;
        descriptor[6] := $C0;

    descriptor[0] := limit and $FF;
    descriptor[1] := (limit shr 8) and $FF;
    descriptor[6] := limit or ((limit shr 16) and $F);

    descriptor[2] := base and $FF;
    descriptor[3] := (base shr 8) and $FF;
    descriptor[4] := (base shr 16) and $FF;
    descriptor[7] := (base shr 24) and $FF;

    descriptor[5] := flags;

    asm 
        MOV EAX, descriptor_ptr
        MOV s_descriptor_ptr, EAX
    end;

    descriptor_ptr = @descriptor[4];

    asm
        MOV EAX, descriptor_ptr
        MOV EBX, s_descriptor_ptr
        ADD EBX, 1
        MOV (EBX), EAX
    end;

    GDTarr[GDT_length] := s_descriptor;
    GDT_length := GDT_length + 1;
end;

    
end.