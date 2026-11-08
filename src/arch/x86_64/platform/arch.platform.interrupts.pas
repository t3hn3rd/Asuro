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

unit arch.platform.interrupts;

interface
{$i ../../common/platform.interrupts.inc}

implementation
uses arch.x86_64.irq, arch.x86_64.util, arch.platform.diagnostics;

function timerTicks: uint64;
begin
    timerTicks := arch.x86_64.irq.ticks;
end;

procedure registerIRQ(vector: uint8; handler: TIRQHandler);
begin
    if not arch.x86_64.irq.registerIRQ(vector, handler) then
        fatal('IRQ', 'IRQ handler registration failed');
end;

procedure registerTimer(handler: TTimerHandler);
begin
    if not arch.x86_64.irq.registerTimer(handler) then
        fatal('IRQ', 'Timer handler registration failed');
end;

procedure routePCI(line, vector: uint8);
var
    flags: PtrUInt;
begin
    if (line >= 16) or (line = 2) or (vector <> line + 32) then
        fatal('IRQ', 'Unsupported PCI legacy IRQ route');
    flags := lockIRQ;
    if line < 8 then
        outb($21, inb($21) and not uint8(1 shl line))
    else begin
        outb($A1, inb($A1) and not uint8(1 shl (line - 8)));
        outb($21, inb($21) and not uint8(4));
    end;
    unlockIRQ(flags);
end;

end.
