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

unit system;

interface

const TRACER_ENABLE = true;

type SizeInt = int64;
     SizeUInt = qword;

{$i ../common/system.types.inc}

type
    { SysV AMD64 nonvolatile register layout. Saved RSP points just past the return address. }
    jmp_buf = packed record
        rbx, rbp, r12, r13, r14, r15, rsp, rip: uint64;
    end;
    PJmp_buf = ^jmp_buf;
    PExceptAddr = ^TExceptAddr;
    TExceptAddr = record
        buf: PJmp_buf;
        next: PExceptAddr;
        frametype: longint;
    end;

var
    ASURO_KERNEL_START, ASURO_KERNEL_END, ASURO_KERNEL_SIZE: PtrUInt;
    ExceptAddrStack: PExceptAddr;
    ExitProc: CodePointer;
    StackBottom: Pointer;
    StackLength: SizeUInt;
    RandSeed: Cardinal;
    ExitCode: longint; public name 'operatingsystem_result';
    ErrorAddr: Pointer;
    ErrorCode: Word;

procedure init;
procedure bootstrap_halt; external name 'bootstrap_halt';
{$i ../common/system.compilerprocs.inc}

implementation

var
    kernelStart: byte; external name 'kernel_start';
    kernelEnd: byte; external name 'kernel_end';
    bootStackBottom: byte; external name 'stack_bottom';
    bootStackTop: byte; external name 'stack_top';
    InitFinalTable: TInitFinalTable; external name 'INITFINAL';

procedure reportRuntimeError(code: longint); external name 'x64_runtime_error';

procedure HandleErrorInternal(errno: longint);
begin
    ErrorCode := Word(errno);
    reportRuntimeError(errno);
    bootstrap_halt;
end;

{$i ../common/system.init.inc}
{$i ../common/system.runtime.inc}

procedure init;
begin
    if unitsInitialized then exit;
    ASURO_KERNEL_START := PtrUInt(@kernelStart);
    ASURO_KERNEL_END := PtrUInt(@kernelEnd);
    ASURO_KERNEL_SIZE := ASURO_KERNEL_END - ASURO_KERNEL_START;
    StackBottom := @bootStackBottom;
    StackLength := PtrUInt(@bootStackTop) - PtrUInt(StackBottom);
    initializeUnits;
end;

procedure fpc_initializeunits; [public, alias: 'FPC_INITIALIZEUNITS']; compilerproc;
begin
    init;
end;

{ SysV AMD64 passes Double in XMM0. CVTTSD2SI rounds toward zero without
  changing the caller's x87 control word or MXCSR rounding mode. }
function Trunc(d: Double): int64; [public, alias: 'FPC_TRUNC']; assembler; nostackframe;
asm
    cvttsd2si rax, xmm0
end;

function Round(d: Double): int64; [public, alias: 'FPC_ROUND']; assembler; nostackframe;
asm
    cvtsd2si rax, xmm0
end;

procedure fpc_do_exit; [public, alias: 'FPC_DO_EXIT']; compilerproc;
begin
    bootstrap_halt;
end;

function fpc_setjmp(var s: jmp_buf): longint; [public, alias: 'FPC_SETJMP']; compilerproc; assembler; nostackframe;
asm
    mov [rdi], rbx
    mov [rdi+8], rbp
    mov [rdi+16], r12
    mov [rdi+24], r13
    mov [rdi+32], r14
    mov [rdi+40], r15
    lea rax, [rsp+8]
    mov [rdi+48], rax
    mov rax, [rsp]
    mov [rdi+56], rax
    xor eax, eax
end;

procedure fpc_longjmp(var s: jmp_buf; value: longint); [public, alias: 'FPC_LONGJMP']; compilerproc; assembler; nostackframe;
asm
    mov eax, esi
    test eax, eax
    jnz @restore
    inc eax
@restore:
    mov rbx, [rdi]
    mov rbp, [rdi+8]
    mov r12, [rdi+16]
    mov r13, [rdi+24]
    mov r14, [rdi+32]
    mov r15, [rdi+40]
    mov rsp, [rdi+48]
    jmp qword [rdi+56]
end;

function fpc_mul_int64(f1, f2: int64): int64; [public, alias: 'FPC_MUL_INT64']; compilerproc;
begin
    fpc_mul_int64 := f1 * f2;
end;

function fpc_mul_dword_to_qword(f1, f2: uint32): qword; [public, alias: 'FPC_MUL_DWORD_TO_QWORD']; compilerproc;
begin
    fpc_mul_dword_to_qword := qword(f1) * f2;
end;

function fpc_div_int64(d, n: int64): int64; [public, alias: 'FPC_DIV_INT64']; compilerproc;
begin
    if d = 0 then HandleErrorInternal(200);
    if (n = Low(int64)) and (d = -1) then begin
        fpc_div_int64 := n;
        exit;
    end;
    fpc_div_int64 := n div d;
end;

function fpc_mod_int64(d, n: int64): int64; [public, alias: 'FPC_MOD_INT64']; compilerproc;
begin
    if d = 0 then HandleErrorInternal(200);
    if (n = Low(int64)) and (d = -1) then begin
        fpc_mod_int64 := 0;
        exit;
    end;
    fpc_mod_int64 := n mod d;
end;

function fpc_div_qword(d, n: qword): qword; [public, alias: 'FPC_DIV_QWORD']; compilerproc;
begin
    if d = 0 then HandleErrorInternal(200);
    fpc_div_qword := n div d;
end;

function fpc_mod_qword(d, n: qword): qword; [public, alias: 'FPC_MOD_QWORD']; compilerproc;
begin
    if d = 0 then HandleErrorInternal(200);
    fpc_mod_qword := n mod d;
end;

end.
