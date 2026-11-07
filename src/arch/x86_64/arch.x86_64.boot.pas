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

unit arch.x86_64.boot;

interface

procedure kmain(info: pointer; magic: uint32); cdecl;

implementation

uses io.stdio, core.strings, driver.storage.fdtable, arch.x86_64.proc.sched, proc.mgr, arch.x86_64.context, arch.x86_64.irq, memory.heap, debug.early, arch.x86_64.debug, arch.x86_64.isr, boot.multiboot,
    arch.x86_64.memory.physical, arch.x86_64.memory.virtual;

function long_mode_active: boolean; assembler; nostackframe;
asm
    mov ecx, $C0000080
    rdmsr
    shr eax, 10
    and eax, 1
end;

procedure kmain(info: pointer; magic: uint32); cdecl; [public, alias: 'kmain'];
var
    wide: PtrUInt;
begin
    arch.x86_64.debug.init;
    arch.x86_64.isr.init;
    puts('ASURO x86_64: entered Pascal'#13#10);
    if (magic <> $2BADB002) or (info = nil) then begin
        puts('FAIL: Multiboot handoff'#13#10);
        bootstrap_halt;
    end;
    if (sizeof(pointer) <> 8) or (sizeof(PtrUInt) <> 8) or
       (sizeof(SizeUInt) <> 8) or (sizeof(uint32) <> 4) then begin
        puts('FAIL: native type widths'#13#10);
        bootstrap_halt;
    end;
    wide := PtrUInt($100000000) + PtrUInt(magic);
    if (wide shr 32 <> 1) or not long_mode_active then begin
        puts('FAIL: long mode or 64-bit arithmetic'#13#10);
        bootstrap_halt;
    end;
    puts('PASS: long mode, Multiboot handoff, 64-bit Pascal types'#13#10);
    arch.x86_64.isr.UnitTest;
    arch.x86_64.memory.physical.init(Pmultiboot_info_t(info));
    arch.x86_64.memory.physical.UnitTest;
    arch.x86_64.memory.virtual.init;
    arch.x86_64.memory.virtual.UnitTest;
    memory.heap.init;
    memory.heap.UnitTest;
    core.strings.UnitTest;
    io.stdio.init;
    arch.x86_64.irq.init;
    arch.x86_64.irq.UnitTest;
    arch.x86_64.context.UnitTest;
    driver.storage.fdtable.UnitTest;
    proc.mgr.init;
    arch.x86_64.proc.sched.init;
    arch.x86_64.proc.sched.UnitTest;
    {$ifdef ASURO_TEST_UD}
    arch.x86_64.isr.testFatal(6);
    {$endif}
    {$ifdef ASURO_TEST_PF}
    arch.x86_64.isr.testFatal(14);
    {$endif}
    {$ifdef ASURO_TEST_DF}
    arch.x86_64.isr.testFatal(8);
    {$endif}
    puts('ASURO x86_64: bootstrap complete; interrupts disabled'#13#10);
    bootstrap_halt;
end;

end.
