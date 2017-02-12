unit util;

{$ASMMODE intel}

interface

function hi(b : byte) : byte;
function lo(b : byte) : byte;
function switchendian(b : byte) : byte;
procedure outb(port : word; val : byte);
procedure outw(port : word; val : word);
procedure outl(port : word; val : longword);
procedure halt_and_catch_fire();

implementation

function hi(b : byte) : byte; [public, alias: 'util_hi'];
begin
     hi:= (b AND $F0) SHR 4;
end;

function lo(b : byte) : byte; [public, alias: 'util_lo'];
begin
     lo:= b AND $0F;
end;

function switchendian(b : byte) : byte; [public, alias: 'util_switchendian'];
begin
     switchendian:= (lo(b) SHL 4) OR hi(b);
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

procedure halt_and_catch_fire(); [public, alias: 'halt_and_catch_fire'];
begin
     asm
          cli
          hlt
     end;
end;

end.
