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

unit arch.x86_64.debug;

interface
procedure init;

implementation
uses debug.early;
{ The stub initializes COM1. Bounded polling also allows boot without a UART. }
procedure putchar(ch: char); assembler; nostackframe;
asm
    mov ecx, 65536
    mov dx, $3FD
@wait:
    in al, dx
    test al, $20
    jnz @ready
    loop @wait
    ret
@ready:
    mov eax, edi
    mov dx, $3F8
    out dx, al
end;

procedure init;
begin
    debug.early.setWriter(@putchar);
end;
end.
