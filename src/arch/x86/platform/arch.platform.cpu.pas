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

{ Build-selected x86 adapter. }
unit arch.platform.cpu;

interface
{$i ../../common/platform.cpu.inc}

implementation
uses arch.x86.util, memory.raw;

function lock: PtrUInt; assembler; nostackframe;
asm
    pushfd;
    cli;
    pop eax
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
    arch.x86.util.outb(port, value);
end;

function inb(port: uint16): uint8;
begin
    inb := arch.x86.util.inb(port);
end;

procedure copyBytes(source, dest: PtrUInt; bytes: SizeUInt);
begin
    if bytes >= 16 then arch.x86.util.__REP_MOVSB_memcpy(source, dest, bytes)
    else memory.raw.move(pointer(source), pointer(dest), bytes);
end;

procedure outw(port: uint16; value: uint16);
begin
    arch.x86.util.outw(port, value);
end;

function inw(port: uint16): uint16;
begin
    inw := arch.x86.util.inw(port);
end;

procedure zero(dest: pointer; bytes: SizeUInt);
var
    d: pointer;
    b: SizeUInt;
begin
    d := dest;
    b := bytes;
    if b = 0 then exit;
    asm
        push edi
        mov edi, d
        mov ecx, b
        shr ecx, 2
        xor eax, eax
        cld
        rep stosd
        mov ecx, b
        and ecx, 3
        rep stosb
        pop edi
    end;
end;
procedure outl(port: uint16; value: uint32);
begin
    arch.x86.util.outl(port, value);
end;

function inl(port: uint16): uint32;
begin
    inl := arch.x86.util.inl(port);
end;

procedure queryCPU(leaf, subleaf: uint32; var registers: TCPURegisters); assembler; nostackframe;
asm
    push ebx
    push edi
    mov edi, ecx
    mov ecx, edx
    cpuid
    mov [edi], eax
    mov [edi + 4], ebx
    mov [edi + 8], ecx
    mov [edi + 12], edx
    pop edi
    pop ebx
end;

end.
