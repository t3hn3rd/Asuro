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

{ Build-selected x86_64 adapter. }
unit arch.platform.cpu;

interface
{$i ../../common/platform.cpu.inc}

implementation
uses arch.x86_64.util, memory.raw;

function lock: PtrUInt;
begin
    lock := arch.x86_64.util.lockIRQ;
end;

procedure unlock(flags: PtrUInt);
begin
    if (flags and $200) <> 0 then asm
        sti
    end;
end;

procedure idle;
begin
    asm
        hlt
    end;
end;

procedure outb(port: uint16; value: uint8);
begin
    arch.x86_64.util.outb(port, value);
end;

function inb(port: uint16): uint8;
begin
    inb := arch.x86_64.util.inb(port);
end;

procedure copyBytes(source, dest: PtrUInt; bytes: SizeUInt);
begin
    memory.raw.move(pointer(source), pointer(dest), bytes);
end;

procedure zero(dest: pointer; bytes: SizeUInt);
begin
    arch.x86_64.util.zero(dest, bytes);
end;
procedure outl(port: uint16; value: uint32); assembler; nostackframe;
asm
    mov edx, edi
    mov eax, esi
    out dx, eax
end;

function inl(port: uint16): uint32; assembler; nostackframe;
asm
    mov edx, edi
    in eax, dx
end;

procedure queryCPU(leaf, subleaf: uint32; var registers: TCPURegisters); assembler; nostackframe;
asm
    push rbx
    mov r8, rdx
    mov eax, edi
    mov ecx, esi
    cpuid
    mov [r8], eax
    mov [r8 + 4], ebx
    mov [r8 + 8], ecx
    mov [r8 + 12], edx
    pop rbx
end;

procedure outw(port: uint16; value: uint16); assembler; nostackframe;
asm
    mov edx, edi
    mov eax, esi
    out dx, ax
end;

function inw(port: uint16): uint16; assembler; nostackframe;
asm
    mov edx, edi
    xor eax, eax
    in ax, dx
end;

end.
