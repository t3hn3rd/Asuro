// Copyright 2026 Aaron Hance
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

{ Shared PC interrupt-controller programming. Call with interrupts disabled. }
unit arch.common.legacyirq;
interface
const
    PIT_INPUT_HZ = 1193182;
    PIT_DIVISOR = 149;
procedure remap(masterMask, slaveMask: uint8);
procedure masks(masterMask, slaveMask: uint8);
procedure timerStart;
function realIRQ(line: uint8): boolean;
procedure acknowledge(line: uint8);
implementation
uses arch.platform.cpu;
procedure writeSlow(port: uint16; value: uint8);
begin
    outb(port, value);
    outb($80, 0);
end;
procedure masks(masterMask, slaveMask: uint8);
begin
    writeSlow($21, masterMask); writeSlow($A1, slaveMask);
end;
procedure remap(masterMask, slaveMask: uint8);
begin
    writeSlow($20, $11); writeSlow($A0, $11);
    writeSlow($21, $20); writeSlow($A1, $28);
    writeSlow($21, $04); writeSlow($A1, $02);
    writeSlow($21, $01); writeSlow($A1, $01);
    masks(masterMask, slaveMask);
end;
procedure timerStart;
begin
    { Channel 0, low/high byte, mode 2, binary. }
    outb($43, $34);
    outb($40, PIT_DIVISOR and $FF);
    outb($40, PIT_DIVISOR shr 8);
end;
function realIRQ(line: uint8): boolean;
begin
    realIRQ := line < 16;
    if line = 7 then begin
        outb($20, $0B);
        realIRQ := (inb($20) and $80) <> 0;
    end else if line = 15 then begin
        outb($A0, $0B);
        realIRQ := (inb($A0) and $80) <> 0;
        { A spurious slave request still put master IRQ2 in service. }
        if not realIRQ then outb($20, $20);
    end;
end;
procedure acknowledge(line: uint8);
begin
    if line >= 16 then exit;
    if line >= 8 then outb($A0, $20);
    outb($20, $20);
end;
end.
