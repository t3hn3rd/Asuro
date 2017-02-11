unit util;

{$ASMMODE intel}

interface

function util_hi(b : byte) : byte;
function util_lo(b : byte) : byte;
function util_switchendian(b : byte) : byte;
procedure outb(port : word; val : byte);
procedure outw(port : word; val : word);
procedure outl(port : word; val : longword);

implementation

function util_hi(b : byte) : byte; [public, alias: 'util_hi'];
begin
     util_hi:= (b AND $F0) SHR 4;
end;

function util_lo(b : byte) : byte; [public, alias: 'util_lo'];
begin
     util_lo:= b AND $0F;
end;

function util_switchendian(b : byte) : byte; [public, alias: 'util_switchendian'];
begin
     util_switchendian:= (util_lo(b) SHL 4) OR util_hi(b);
end;

procedure outl(port : word; val : longword); [public, alias: 'outl'];
begin
     asm
          PUSH EAX
          PUSH EDX
          MOV DX, port
          MOV EAX, val
          OUT DX, EAX
          POP EDX
          POP EAX
     end;
end;

procedure outw(port : word; val : word); [public, alias: 'outw'];
begin
     asm
          PUSH EAX
          PUSH EDX
          MOV DX, port
          MOV AX, val
          OUT DX, AX
          POP EDX
          POP EAX
     end;
end;

procedure outb(port : word; val : byte); [public, alias: 'outb'];
begin
     asm
          PUSH EAX
          PUSH EDX
          MOV DX, port
          MOV AL, val
          OUT DX, AL
          POP EDX
          POP EAX
     end;
end;

end.
