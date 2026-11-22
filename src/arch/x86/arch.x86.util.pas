//  Copyright 2021 Kieron Morris
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

{ 
    arch.x86.util - x86 I/O and low-level CPU utilities.

    Port I/O (outb/inb/outw/inw/outl/inl), CLI/STI, TSC reads,
    BSOD, halt, reset, and anything requiring inline x86 assembly.

    @author(Kieron Morris <kjm@kieronmorris.me>)
    @author(Aaron Hance <ah@aaronhance.me>)
}
unit arch.x86.util;

{$ASMMODE intel}

interface

uses
    arch.x86.bda;

function  INTE : boolean;
procedure CLI();
procedure STI();
procedure GPF();

procedure outb(port : uint16; val : uint8);
procedure outw(port : uint16; val : uint16);
procedure outl(port : uint16; val : uint32);
function inb(port : uint16) : uint8;
function inw(port : uint16) : uint16;
function inl(port : uint16) : uint32;
procedure io_wait;

procedure __SSE_128_memcpy(source : uint32; dest : uint32);
procedure __REP_MOVSB_memcpy(source : uint32; dest : uint32; size : uint32);

procedure halt_and_catch_fire();
procedure halt_and_dont_catch_fire();
procedure psleep(t : uint16);
procedure sleep(seconds : uint32);

function get16bitcounter : uint16;
function get32bitcounter : uint32;
function get64bitcounter : uint64;
function getTSC : uint64;

function div6432(dividend : uint64; divisor : uint32) : uint64;

procedure resetSystem();

function getESP : uint32;

function RolDWord(AValue : uint32; Dist : uint8) : uint32;
function RorDWord(AValue : uint32; Dist : uint8) : uint32;

function MsSinceSystemBoot : uint64;

var
    endptr : uint32; external name '__end';
    stack  : uint32; external name 'KERNEL_STACK';

implementation

uses
    arch.x86.cpu,
    arch.x86.isr.types,
    driver.timer.rtc,
    driver.io.serial;

function MsSinceSystemBoot : uint64;
begin
    MsSinceSystemBoot:= div6432(getTSC, (CPUID.ClockSpeed.Hz div 1000));
end;

function div6432(dividend : uint64; divisor : uint32) : uint64;
var
    d0, d4 : uint32;
    r0, r4 : uint32;

begin
    d4:= dividend SHR 32;
    d0:= dividend AND $FFFFFFFF;
    asm
        PUSHAD
        xor edx, edx
        mov eax, d4
        div divisor
        mov r4, eax
        mov eax, d0
        div divisor
        mov r0, eax
        POPAD
    end;
    div6432:= (r0 SHL 32) OR r4;
end;

procedure __SSE_128_memcpy(source : uint32; dest : uint32); assembler;
asm
    MOV EAX, Source
    MOVAPS XMM1, [EAX]
    MOV EAX, Dest
    MOVAPS [EAX], XMM1
end;

procedure __REP_MOVSB_memcpy(source : uint32; dest : uint32; size : uint32); assembler;
asm
    push esi
    push edi
    cld
    mov esi, source
    mov edi, dest
    mov ecx, size
    rep movsb
    pop edi
    pop esi
end;

function getESP : uint32;
var
    tmp: uint32;
begin
    asm
        MOV tmp, ESP
    end;
    getESP := tmp;
end;

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

procedure psleep(t : uint16);
var
    t1, t2 : uint16;
    spin   : uint32;
begin
    t1 := BDA^.Ticks;

    { Busy-spin briefly to give the tick counter a chance to advance.
      If after ~50 000 iterations the counter hasn't moved, the timer
      ISR isn't installed yet — fall back to a rough CPU busy-wait
      (~1 ms per requested tick at typical Bochs/VBox speed). }
    spin := 0;
    t2 := t1;
    while t2 = t1 do begin
        spin := spin + 1;
        if spin > 50000 then begin
            { Timer not running — approximate delay with busy loop.
              Each outer iteration ≈ a few µs; 50000 * t gives a
              very rough ms-scale delay that is good enough for the
              hardware settle times that call psleep. }
            for spin := 1 to uint32(t) * 50000 do
                asm nop end;
            exit;
        end;
        t2 := BDA^.Ticks;
    end;

    { Timer is running — use real ticks }
    t1 := BDA^.Ticks;
    while t2 - t1 < t do begin
        t2 := BDA^.Ticks;
        if t2 < t1 then break; { tick counter wrapped }
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
     io_wait;
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
     io_wait;
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
     io_wait;
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
var
     tmp : uint32;
begin
     asm
          PUSH EAX
          PUSH EDX
          MOV DX, port
          IN EAX, DX
          MOV tmp, EAX
          POP EDX
          POP EAX
     end;
     inl := tmp;
     io_wait;
end;

function inw(port : uint16) : uint16; [public, alias: 'util_inw'];
var
     tmp : uint16;
begin
     asm
          PUSH EAX
          PUSH EDX
          MOV DX, port
          IN AX, DX
          MOV tmp, AX
          POP EDX
          POP EAX
     end;
     inw := tmp;
     io_wait;
end;

function inb(port : uint16) : uint8; [public, alias: 'util_inb'];
var
     tmp : uint8;
begin
     asm
          PUSH EAX
          PUSH EDX
          MOV DX, port
          IN AL, DX
          MOV tmp, AL
          POP EDX
          POP EAX
     end;
     inb := tmp;
     io_wait;
end;

function get16bitcounter : uint16;
begin
    get16bitcounter:= arch.x86.bda.Counters.c16;
end;

function get32bitcounter : uint32;
begin
    get32bitcounter:= arch.x86.bda.Counters.c32;
end;

function get64bitcounter : uint64;
begin
    get64bitcounter:= arch.x86.bda.Counters.c64;
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

function RolDWord(AValue : uint32; Dist : uint8) : uint32;
var
    result : uint32;
    i      : uint8;    

begin
    result:= AValue;
    asm
        PUSH EAX
    end;
    for i:=0 to Dist-1 do begin
        asm
            MOV EAX, result
            ROL EAX, 1
            MOV result, EAX
        end;
    end;
    asm
        POP EAX
    end;
    RolDWord:= result;
end;

function RorDWord(AValue : uint32; Dist : uint8) : uint32;
var
    result : uint32;
    i      : uint8;    

begin
    result:= AValue;
    asm
        PUSH EAX
    end;
    for i:=0 to Dist-1 do begin
        asm
            MOV EAX, result
            ROR EAX, 1
            MOV result, EAX
        end;
    end;
    asm
        POP EAX
    end;
    RorDWord:= result;
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

end.
