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
procedure GPF();

function hi(b : uint8) : uint8;
function lo(b : uint8) : uint8;
function switchendian(b : uint8) : uint8;
function getWord(i : uint32; hi : boolean) : uint16;
function getByte(i : uint32; index : uint8) : uint8;

procedure outb(port : uint16; val : uint8);
procedure outw(port : uint16; val : uint16);
procedure outl(port : uint16; val : uint32);
function inb(port : uint16) : uint8;
function inw(port : uint16) : uint16;
function inl(port : uint16) : uint32;

procedure memset(location : uint32; value : uint8; size : uint32);
procedure memcpy(source : uint32; dest : uint32; size : uint32);

procedure printmemory(source : uint32; length : uint32; col : uint32; delim : PChar; offset_row : boolean);

procedure halt_and_catch_fire();
procedure halt_and_dont_catch_fire();
procedure BSOD(fault : pchar; info : pchar);
procedure psleep(t : uint16);

var
    endptr : uint32; external name '__end';
    stack  : uint32; external name 'KERNEL_STACK';

implementation

uses
    console;

procedure printmemory(source : uint32; length : uint32; col : uint32; delim : PChar; offset_row : boolean);
var
    buf : puint8;
    i   : uint32;

begin
    buf:= puint8(source);
    for i:=0 to length do begin
        if offset_row and (i = 0) then begin
            console.writehex(source + (i * col));
            console.writestring(': ');
        end; 
        console.writehexpair(buf[i]);
        if ((i+1) MOD col) = 0 then begin
            console.writestringln(' ');  
            if offset_row then begin
                console.writehex(source + (i * col));
                console.writestring(': ');
            end;  
        end else begin
            console.writestring(delim);
        end;
    end;
    console.writestringln(' ');
end;

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

procedure GPF(); assembler;
asm
    INT 13
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
        if t2 < t1 then break;
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

procedure memcpy(source : uint32; dest : uint32; size : uint32);
var
    src, dst : puint8;
    i : uint32;

begin
    for i:=0 to size-1 do begin
        src:= puint8(source + i);
        dst:= puint8(dest + i);
        dst^:= src^;
    end;
end;

function getWord(i : uint32; hi : boolean) : uint16;
begin
    if hi then begin
        getWord:= (i AND $FFFF0000) SHR 16;
    end else begin
        getWord:= (i AND $0000FFFF);
    end;    
end;

function getByte(i : uint32; index : uint8) : uint8;
var
    mask : uint32;

begin
    mask:= ($FF SHL (8*index));
    getByte:= (i AND mask) SHR (8*index);
end;

procedure BSOD(fault : pchar; info : pchar);
begin
    console.setdefaultattribute(console.combinecolors(white, Red));
    console.clear;
    console.writestringln(' ');
    console.writestringln(' ');
    console.writestring('             ');
    console.setdefaultattribute(console.combinecolors(black, white));  
    console.writestring('                                                    ');
    console.setdefaultattribute(console.combinecolors(white, Red));
    console.writestringln(' ');
    console.writestring('             ');
    console.setdefaultattribute(console.combinecolors(black, white));
    console.writestring('             ASURO DID A WHOOPSIE!  :(              ');
    console.setdefaultattribute(console.combinecolors(lwhite, Red));
    console.writestringln(' ');
    console.writestring('             ');
    console.setdefaultattribute(console.combinecolors(black, white));
    console.writestring('                                                    ');
    console.setdefaultattribute(console.combinecolors(white, Red));
    console.writestringln(' ');
    console.writestringln(' ');
    console.writestringln(' ');
    console.writestringln('    Asuro encountered an error and your computer is now a teapot.');
    console.writestringln(' ');
    console.writestringln('    Your data is almost certainly safe. Probably.');
    console.writestringln(' ');
    console.writestringln('    The fault could have been caused by one or more of the following: ');
    console.writestringln('    - LDH_NN_65 malfunctioning.');
    console.writestringln('    - A devlopers inability to handle faults correctly.');
    console.writestringln('    - Spilt coffee.');
    console.writestringln('    - A monkey inside the PC Case.');
    console.writestringln(' ');
    console.writestringln(' ');
    console.writestringln('    Details of the fault (for those boring enough to read) are as follows: ');
    console.writestringln(' ');
    console.writestring('    Fault ID: ');
    console.writestringln(fault);
    console.writestring('    Fault Info: ');
    console.writestringln(info);
    console.writestringln(' ');
    console.writestringln(' ');
    halt_and_catch_fire();
end;

end.
