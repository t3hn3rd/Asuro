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
    bios_data_area, tracer;

function  INTE : boolean;
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
procedure io_wait;

procedure memset(location : uint32; value : uint8; size : uint32);
procedure memcpy(source : uint32; dest : uint32; size : uint32);

procedure printmemory(source : uint32; length : uint32; col : uint32; delim : PChar; offset_row : boolean);

procedure halt_and_catch_fire();
procedure halt_and_dont_catch_fire();
procedure BSOD(fault : pchar; info : pchar);
procedure psleep(t : uint16);
procedure sleep(seconds : uint32);

function get16bitcounter : uint16;
function get32bitcounter : uint32;
function get64bitcounter : uint64;
function getTSC : uint64;

function BCDToUint8(bcd : uint8) : uint8;

procedure resetSystem();

var
    endptr : uint32; external name '__end';
    stack  : uint32; external name 'KERNEL_STACK';

implementation

uses
    console, RTC;

procedure sleep1;
var
   DateTimeStart, DateTimeEnd : TDateTime;


begin
    DateTimeStart:= getDateTime;
    DateTimeEnd:= DateTimeStart;
    while DateTimeStart.seconds = DateTimeEnd.seconds do begin
        DateTimeEnd:= getDateTime;
    end;
end;

procedure sleep(seconds : uint32);
var
    i : uint32;

begin
    for i:=1 to seconds do begin
        sleep1;
    end;
end;

function INTE : boolean;
var
    flags : uint32;
begin
    asm
        PUSH EAX
        PUSHF
        POP EAX
        MOV flags, EAX
        POP EAX
    end;
    INTE:= (flags AND (1 SHL 9)) > 0;
end;

procedure io_wait;
var
    port : uint8;
    val  : uint8;
begin
    port:= $80;
    val:= 0;
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

procedure printmemory(source : uint32; length : uint32; col : uint32; delim : PChar; offset_row : boolean);
var
    buf : puint8;
    i   : uint32;

begin   
    buf:= puint8(source);
    for i:=0 to length-1 do begin
        if offset_row and (i = 0) then begin
            console.writehex(source + (i));
            console.writestring(': ');
        end; 
        console.writehexpair(buf[i]);
        if ((i+1) MOD col) = 0 then begin
            console.writestringln(' ');  
            if offset_row then begin
                console.writehex(source + (i + 1));
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
    //push_trace('util.memset');
    for i:=0 to size-1 do begin
        loc:= puint8(location + i);
        loc^:= value;
    end;
    //pop_trace;
end;

procedure memcpy(source : uint32; dest : uint32; size : uint32);
var
    src, dst : puint8;
    i : uint32;

begin
    //push_trace('util.memcpy');
    for i:=0 to size-1 do begin
        src:= puint8(source + i);
        dst:= puint8(dest + i);
        dst^:= src^;
    end;
    //pop_trace;
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

function BCDToUint8(bcd : uint8) : uint8;
begin
    BCDToUint8:= ((bcd SHR 4) * 10) + (bcd AND $0F);
end;

procedure resetSystem();
var
    good : uint8;

begin
    CLI;
    good:= $02;
    while (good AND $02) > 0 do good:= inb($64);
    outb($64, $FE);
    halt_and_catch_fire;
end;

function get16bitcounter : uint16;
begin
    get16bitcounter:= bios_data_area.Counters.c16;
end;

function get32bitcounter : uint32;
begin
    get32bitcounter:= bios_data_area.Counters.c32;
end;

function get64bitcounter : uint64;
begin
    get64bitcounter:= bios_data_area.Counters.c64;
end;

function getTSC : uint64;
var
    hi, lo : uint32;

begin
    asm
        PUSH EAX
        PUSH EDX
        RDTSC
        MOV hi, EDX
        MOV lo, EAX
        POP EDX
        POP EAX
    end;
    getTSC:= (hi SHL 32) OR lo;
end;

procedure BSOD(fault : pchar; info : pchar);
var
    trace : pchar;
    i     : uint32;
    z     : uint32;

begin
    console.disable_cursor;
    console.mouseEnabled(false);
    console.forceQuitAll;
    if not BSOD_ENABLE then exit;
    console.setdefaultattribute(console.combinecolors($FFFF, $F800));
    console.clear;
    console.writestringln(' ');
    console.writestringln(' ');
    console.writestring('             ');
    console.setdefaultattribute(console.combinecolors($0000, $FFFF));  
    console.writestring('                                                    ');
    console.setdefaultattribute(console.combinecolors($FFFF, $F800));
    console.writestringln(' ');
    console.writestring('             ');
    console.setdefaultattribute(console.combinecolors($0000, $FFFF)); 
    console.writestring('             ASURO DID A WHOOPSIE!  :(              ');
    console.setdefaultattribute(console.combinecolors($FFFF, $F800));
    console.writestringln(' ');
    console.writestring('             ');
    console.setdefaultattribute(console.combinecolors($0000, $FFFF)); 
    console.writestring('                                                    ');
    console.setdefaultattribute(console.combinecolors($FFFF, $F800));
    console.writestringln(' ');
    console.writestringln(' ');
    console.writestringln(' ');
    console.writestringln('    Asuro encountered an error and your computer is now a teapot.');
    console.writestringln(' ');
    console.writestringln('    Your data is almost certainly safe.');
    console.writestringln(' ');
    console.writestringln('    Details of the fault (for those boring enough to read) are as follows: ');
    console.writestringln(' ');
    console.writestring('    Fault ID:   ');
    console.writestringln(fault);
    console.writestring('    Fault Info: ');
    console.writestringln(info);
    console.writestringln(' ');
    console.writestring('    Call Stack: ');
    trace:= tracer.get_last_trace;
    if trace <> nil then begin
        console.writestring('[-0] ');
        console.writestringln(trace);
        for i:=1 to tracer.get_trace_count-1 do begin
            trace:= tracer.get_trace_N(i);
            if trace <> nil then begin
                console.writestring('                [');
                console.writestring('-');
                console.writeint(i);
                console.writestring('] ');
                console.writestringln(trace);
            end;
        end;
    end else begin
        console.writestringln('Unknown.');
    end;
    console.redrawWindows;
    halt_and_catch_fire();
end;

end.
