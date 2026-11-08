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
uses arch.x86.isr.mgr, arch.x86.isr.tmr0, arch.x86.isr.ioapic,
    arch.x86.bda, arch.platform.cpu;

function timerTicks: uint64;
var
    flags: PtrUInt;
begin
    flags := arch.platform.cpu.lock;
    timerTicks := Counters.c64;
    arch.platform.cpu.unlock(flags);
end;

procedure registerIRQ(vector: uint8; handler: TIRQHandler);
begin
    arch.x86.isr.mgr.registerISR(vector, handler);
end;

procedure registerTimer(handler: TTimerHandler);
begin
    arch.x86.isr.tmr0.hook(PtrUInt(handler));
end;

procedure routePCI(line, vector: uint8);
begin
    arch.x86.isr.ioapic.init;
    arch.x86.isr.ioapic.route_pci_irq(line, vector);
end;

end.
