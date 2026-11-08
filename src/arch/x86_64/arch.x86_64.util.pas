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

unit arch.x86_64.util;

interface
function lockIRQ: PtrUInt;
procedure unlockIRQ(flags: PtrUInt);
procedure zero(dest: pointer; bytes: SizeUInt);
procedure invalidate(address: PtrUInt);
function pageRoot: uint64;
procedure outb(port: uint16; value: uint8);
function inb(port: uint16): uint8;

implementation

function lockIRQ: PtrUInt; assembler; nostackframe;
asm
    pushfq
    cli
    pop rax
end;

procedure unlockIRQ(flags: PtrUInt); assembler; nostackframe;
asm
    test rdi, $200
    jz @done
    sti
@done:
end;

procedure zero(dest: pointer; bytes: SizeUInt); assembler; nostackframe;
asm
    mov rcx, rsi
    shr rcx, 3
    xor eax, eax
    cld
    rep stosq
    mov rcx, rsi
    and rcx, 7
    rep stosb
end;

procedure invalidate(address: PtrUInt); assembler; nostackframe;
asm
    invlpg [rdi]
end;

function pageRoot: uint64; assembler; nostackframe;
asm
    mov rax, cr3
end;

procedure outb(port: uint16; value: uint8); assembler; nostackframe;
asm
    mov edx, edi
    mov eax, esi
    out dx, al
end;

function inb(port: uint16): uint8; assembler; nostackframe;
asm
    mov edx, edi
    xor eax, eax
    in al, dx
end;
end.
