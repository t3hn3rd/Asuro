; Copyright 2026 Aaron Hance
;
; Licensed under the Apache License, Version 2.0 (the "License");
; you may not use this file except in compliance with the License.
; You may obtain a copy of the License at
; http://www.apache.org/licenses/LICENSE-2.0
; Unless required by applicable law or agreed to in writing, software
; distributed under the License is distributed on an "AS IS" BASIS,
; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
; See the License for the specific language governing permissions and
; limitations under the License.

bits 64
extern x64_exception_dispatch
extern x64_select_context
extern bootstrap_halt

global x64_isr_table
global x64_test_breakpoint
global x64_test_breakpoint_return
global x64_test_expected_rsp
global x64_test_page_fault
global x64_test_page_fault_instruction
global x64_test_page_fault_return
global x64_test_double_fault
global x64_test_invalid_opcode
global x64_df_stack_bottom, x64_df_stack_top
global x64_nmi_stack_top, x64_mc_stack_top

section .text
; Normalize hardware error-code and no-error-code frames. Never use software
; INT to invoke vectors whose CPU-generated exceptions push an error code.
%assign vector 0
%rep 256
isr_%+vector:
%if vector != 8 && vector != 10 && vector != 11 && vector != 12 && vector != 13 && vector != 14 && vector != 17 && vector != 21 && vector != 29 && vector != 30
    push qword 0
%endif
    push qword vector
    jmp common_entry
%assign vector vector+1
%endrep

common_entry:
    push rax
    push rcx
    push rdx
    push rbx
    push rbp
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    mov rax, cr2
    push rax
    ; All interrupted registers are saved before changing DF or calling Pascal.
    cld
    mov rbx, rsp
    sub rsp, 528+15
    and rsp, -16
    fxsave64 [rsp]
    mov [rsp+512], rbx
    mov r12, rsp
    mov rdi, rbx
    call x64_exception_dispatch
    mov rdi, r12
    call x64_select_context
    fxrstor64 [rax]
    mov rsp, [rax+512]
    add rsp, 8                  ; captured CR2
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rbp
    pop rbx
    pop rdx
    pop rcx
    pop rax
    add rsp, 16                 ; normalized vector and error code
    iretq

; Test the real entry/return path, including nonvolatile registers, high halves,
; DF/CF, x87, and XMM0/XMM15. Preserve the caller's original FX state as well.
x64_test_breakpoint:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 536                ; aligned 512-byte FX area + scratch
    fxsave64 [rsp]
    mov [rel x64_test_expected_rsp], rsp
    fninit
    fld1
    pcmpeqd xmm0, xmm0
    pcmpeqd xmm15, xmm15
%macro SEED 1
    mov %1, 0x1122334455667788
%endmacro
    SEED rax
    SEED rcx
    SEED rdx
    SEED rbx
    SEED rbp
    SEED rsi
    SEED rdi
    SEED r8
    SEED r9
    SEED r10
    SEED r11
    SEED r12
    SEED r13
    SEED r14
    SEED r15
    std
    stc
    int3
x64_test_breakpoint_return:
    pushfq
    pop qword [rsp+512]
    cld
%macro CHECK 1
    cmp %1, [rel expected_gpr]
    jne .failed
%endmacro
    CHECK rax
    CHECK rcx
    CHECK rdx
    CHECK rbx
    CHECK rbp
    CHECK rsi
    CHECK rdi
    CHECK r8
    CHECK r9
    CHECK r10
    CHECK r11
    CHECK r12
    CHECK r13
    CHECK r14
    CHECK r15
    mov eax, [rsp+512]
    and eax, 0x401              ; CF and DF must both survive IRETQ
    cmp eax, 0x401
    jne .failed
    pmovmskb eax, xmm0
    cmp eax, 0xFFFF
    jne .failed
    pmovmskb eax, xmm15
    cmp eax, 0xFFFF
    jne .failed
    fistp qword [rsp+512]
    cmp qword [rsp+512], 1
    jne .failed
    mov eax, 1
    jmp .done
.failed:
    xor eax, eax
.done:
    fxrstor64 [rsp]
    add rsp, 536
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

x64_test_page_fault:
    mov rax, 0x100000000        ; canonical, just beyond the bootstrap mapping
x64_test_page_fault_instruction:
    mov [rax], rax              ; write fault: nonzero hardware error code (2)
x64_test_page_fault_return:
    ret

x64_test_invalid_opcode:
    ud2
    jmp bootstrap_halt

x64_test_double_fault:
    ; Both ordinary #UD and #PF delivery need this unmapped stack. #DF must
    ; switch to IST1 and report the original broken RSP without touching it.
    mov rsp, 0x100001000
    ud2
    jmp bootstrap_halt

section .rodata align=8
expected_gpr: dq 0x1122334455667788
x64_isr_table:
%assign vector 0
%rep 256
    dq isr_%+vector
%assign vector vector+1
%endrep

section .bss align=16
x64_test_expected_rsp: resq 1
alignb 16
; Bounded bootstrap reservations, before an allocator exists. Keep these
; reserved in the future allocator. NMI/MC cannot overwrite the #DF stack.
x64_df_stack_bottom: resb 16384
x64_df_stack_top:
    resb 8192
x64_nmi_stack_top:
    resb 8192
x64_mc_stack_top:

section .text
global x64_test_context_registers
; RDI: monotonically increasing switch counter; RSI: distinct 64-bit pattern.
; Preserve the caller's ABI/FX state while checking real timer preemption.
x64_test_context_registers:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    sub rsp, 560
    and rsp, -16
    fxsave64 [rsp]
    mov [rsp+520], rsi
    mov r12, rsi
    mov r13, rdi
    mov r14d, [rdi]
    add r14d, 9
    movq xmm15, rsi
    punpcklqdq xmm15, xmm15
    mov eax, esi
    inc eax
    mov [rsp+512], eax
    fninit
    fild dword [rsp+512]
.wait:
    pause
    cmp [r13], r14d
    jb .wait
    xor eax, eax
    cmp r12, [rsp+520]
    jne .done
    cmp rsi, [rsp+520]
    jne .done
    movq rdx, xmm15
    cmp rdx, [rsp+520]
    jne .done
    movdqa xmm0, xmm15
    psrldq xmm0, 8
    movq rdx, xmm0
    cmp rdx, [rsp+520]
    jne .done
    fistp dword [rsp+516]
    mov edx, [rsp+512]
    cmp edx, [rsp+516]
    jne .done
    mov eax, 1
.done:
    fxrstor64 [rsp]
    lea rsp, [rbp-24]
    pop r14
    pop r13
    pop r12
    pop rbp
    ret
