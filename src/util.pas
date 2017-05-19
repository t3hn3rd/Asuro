{ ************************************************
  * Asuro
  * Unit: util
  * Description: Utilities for data manipulation
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit util;

{$ASMMODE intel}

interface

uses
    bios_data_area;

procedure CLI();
procedure STI();
function hi(b : uint8) : uint8;
function lo(b : uint8) : uint8;
function switchendian(b : uint8) : uint8;
procedure outb(port : uint16; val : uint8);
procedure outw(port : uint16; val : uint16);
procedure outl(port : uint16; val : uint32);
procedure halt_and_catch_fire();
procedure halt_and_dont_catch_fire();
function inb(port : uint16) : uint8;
function inw(port : uint16) : uint16;
function inl(port : uint16) : uint32;
procedure memset(location : uint32; value : uint8; size : uint32);
procedure psleep(t : uint16);

var
    endptr : uint32; external name '__end';

implementation

uses
    console;

function hi(b : uint8) : uint8; [public, alias: 'util_hi'];
begin
     hi:= (b AND $F0) SHR 4;
end;

function lo(b : uint8) : uint8; [public, alias: 'util_lo'];
begin
     lo:= b AND $0F;
end;

procedure CLI(); assembler; nostackframe;
asm
    CLI
end;

procedure STI(); assembler; nostackframe;
asm
    STI
end;

function switchendian(b : uint8) : uint8; [public, alias: 'util_switchendian'];
begin
     switchendian:= (lo(b) SHL 4) OR hi(b);
end;

procedure psleep(t : uint16);
var
    t1, t2 : uint16;

begin
    t1:= BDA^.Ticks;
    t2:= BDA^.Ticks;
    while t2-t1 < t do begin
        t2:= BDA^.Ticks;
    end;
end;

procedure outl(port : uint16; val : uint32); [public, alias: 'util_outl'];
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

procedure outw(port : uint16; val : uint16); [public, alias: 'util_outw'];
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

procedure outb(port : uint16; val : uint8); [public, alias: 'util_outb'];
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

procedure halt_and_dont_catch_fire(); [public, alias: 'util_halt_and_dont_catch_fire'];
begin
    while true do begin
    end;
end;

function inl(port : uint16) : uint32; [public, alias: 'util_inl'];
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

function inw(port : uint16) : uint16; [public, alias: 'util_inw'];
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

function inb(port : uint16) : uint8; [public, alias: 'util_inb'];
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

procedure memset(location : uint32; value : uint8; size : uint32);
var
    loc : puint8;
    i   : uint32;

begin
    for i:=0 to size-1 do begin
        loc:= puint8(location + i);
        loc^:= value;
    end;
end;

end.
