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
function inb(port : word) : byte;
function inw(port : word) : word;
function inl(port : word) : dword;

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

procedure outl(port : word; val : longword); [public, alias: 'util_outl'];
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

procedure outw(port : word; val : word); [public, alias: 'util_outw'];
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

procedure outb(port : word; val : byte); [public, alias: 'util_outb'];
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

procedure halt_and_catch_fire(); [public, alias: 'util_halt_and_catch_fire'];
begin
     asm
          cli
          hlt
     end;
end;

function inl(port : word) : dword; [public, alias: 'util_inl'];
begin
     asm
          PUSH EAX
          PUSH EDX
          MOV DX, port
          IN EAX, DX
          MOV inl, EAX
          POP EDX
          POP EAX
     end;
end;

function inw(port : word) : word; [public, alias: 'util_inw'];
begin
     asm
          PUSH EAX
          PUSH EDX
          MOV DX, port
          IN AX, DX
          MOV inw, AX
          POP EDX
          POP EAX
     end;
end;

function inb(port : word) : byte; [public, alias: 'util_inb'];
begin
     asm
          PUSH EAX
          PUSH EDX
          MOV DX, port
          IN AL, DX
          MOV inb, AL
          POP EDX
          POP EAX
     end;
end;

end.
