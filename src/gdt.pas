unit gdt;
    
interface

uses
    util,
    types;

procedure create(base : dword; limit : dword; flags : byte);
procedure init();

type
    TSegmentDescriptor = bitpacked record
        limit_low     : WORD;
        base_low      : WORD;
        access        : Byte;
        limit_n_flags : Byte;
        base_high     : Byte;
    end;
    PSegmentDescriptor = ^TSegmentDescriptor;

implementation

var
   GDTarr : array [0..5] of TSegmentDescriptor;
   GDTptr : PSegmentDescriptor;
   GDT_length : integer = 0;
    
procedure create(base : dword; limit : dword; flags : byte);
var
    descriptor       : array[0..8] of Byte;
    descriptor_ptr   : PByte;

    s_descriptor     : TSegmentDescriptor;
    s_descriptor_ptr : PSegmentDescriptor;

begin
     descriptor_ptr:= @descriptor[0];
     s_descriptor_ptr:= @s_descriptor;
     if limit <= 65536 then begin
        descriptor[6] := $40 //1 <-- Will be overwritten by 2.
     end else begin
         if (limit and $FFF) <> $FFF then begin
     	    limit := (limit SHR 12) - 1;
         end else begin
    	     limit := limit SHR 12;
         end;
     end;

     descriptor[6] := $C0; //2 <-- Will be overwritten by 3;

     descriptor[0] := limit and $FF;
     descriptor[1] := (limit shr 8) and $FF;
     descriptor[6] := descriptor[6] or ((limit shr 16) and $F); //3 <-- has now overwritten both $C0 and $40 is now equal to limit or'd with limit shifted right 16 bits and constant $0F

     descriptor[2] := base and $FF;
     descriptor[3] := (base shr 8) and $FF;
     descriptor[4] := (base shr 16) and $FF;
     descriptor[7] := (base shr 24) and $FF;

     descriptor[5] := flags;

     asm 
         MOV EAX, descriptor_ptr
         MOV s_descriptor_ptr, EAX
     end;

     descriptor_ptr:= @descriptor[4];

     asm
        MOV EAX, descriptor_ptr
        MOV EBX, s_descriptor_ptr
        ADD EBX, 1
        MOV [EBX], EAX
     end;

     GDTarr[GDT_length] := s_descriptor;
     GDT_length := GDT_length + 1;
end;

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
        MOV EAX, data_addr
        MOV DS, AX
        MOV SS, AX
        MOV ES, AX
        MOV FS, AX
        MOV GS, AX
    end;
end;

end.
