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

bits 32
global loader
global bootstrap_halt
global bootstrap_tss_descriptor
global stack_top
extern kmain
extern load_end
extern kernel_end

; Explicit Multiboot v1 load addresses allow GRUB to load this ELF64 image
; while still handing off in 32-bit protected mode. All bootstrap addresses
; are below 4 GiB. The linker keeps this header first in the load image.
section .multiboot align=4
header:
    dd 0x1BADB002
    dd 0x00010007
    dd -(0x1BADB002 + 0x00010007)
    dd header
    dd header
    dd load_end
    dd kernel_end
    dd loader
    dd 0, 1024, 768, 32

section .text
loader:
    cli
    cld
    ; Own flat descriptors before relying on the bootloader's data segments.
    lgdt [gdt_pointer]
    jmp 0x08:protected_entry
protected_entry:
    mov dx, 0x10
    mov ds, dx
    mov es, dx
    mov ss, dx
    mov esp, stack_top
    mov esi, eax                 ; preserve Multiboot magic across CPUID
    mov ebp, ebx                 ; physical Multiboot info pointer
    call serial_init
    cmp esi, 0x2BADB002
    jne fail_boot

    ; CPUID availability: toggle EFLAGS.ID and restore the original flags.
    pushfd
    pop eax
    mov ecx, eax
    xor eax, 1 << 21
    push eax
    popfd
    pushfd
    pop eax
    push ecx
    popfd
    xor eax, ecx
    test eax, 1 << 21
    jz fail_cpu
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jb fail_cpu
    mov eax, 0x80000001
    cpuid
    test edx, 1 << 29
    jz fail_cpu

    ; Reserve six bootstrap pages: PML4, PDPT, and four page directories.
    ; Identity-map the first 4 GiB using 2 MiB leaves, including boot data.
    mov edi, pml4
    xor eax, eax
    mov ecx, (6 * 4096) / 4
    rep stosd
    mov dword [pml4], pdpt + 3
    mov edi, pdpt
    mov eax, page_directories + 3
    mov ecx, 4
.pdpt:
    mov [edi], eax
    add edi, 8
    add eax, 4096
    loop .pdpt
    mov edi, page_directories
    mov eax, 0x83
    mov ecx, 2048
.pages:
    mov [edi], eax
    add edi, 8
    add eax, 0x200000
    loop .pages

    ; Multiboot enters with paging off. PAE must precede activation of LME.
    mov eax, cr4
    or eax, (1 << 5) | (1 << 9) | (1 << 10)
    mov cr4, eax
    mov eax, pml4
    mov cr3, eax
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8
    wrmsr
    mov eax, cr0
    and eax, ~((1 << 2) | (1 << 3))  ; clear EM/TS for compiler SSE2 use
    or eax, (1 << 31) | (1 << 1)
    mov cr0, eax
    jmp 0x18:long_entry

fail_boot:
    mov bl, 'B'
    jmp fail
fail_cpu:
    mov bl, 'C'
fail:
    mov ecx, 65536
    mov dx, 0x3FD
.wait:
    in al, dx
    test al, 0x20
    jnz .write
    loop .wait
    jmp .halt
.write:
    mov dx, 0x3F8
    mov al, bl
    out dx, al
.halt:
    cli
    hlt
    jmp .halt

serial_init:
    mov dx, 0x3F9
    xor al, al
    out dx, al
    mov dx, 0x3FB
    mov al, 0x80
    out dx, al
    mov dx, 0x3F8
    mov al, 1
    out dx, al
    mov dx, 0x3F9
    xor al, al
    out dx, al
    mov dx, 0x3FB
    mov al, 3
    out dx, al
    mov dx, 0x3FA
    mov al, 0xC7
    out dx, al
    mov dx, 0x3FC
    mov al, 0x0B
    out dx, al
    ret

bits 64
long_entry:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    xor eax, eax
    mov fs, ax
    mov gs, ax
    mov rsp, stack_top
    mov edi, ebp                ; SysV AMD64: RDI=info, RSI=magic
    xor ebp, ebp
    fninit
    ldmxcsr [rel initial_mxcsr]
    call kmain
bootstrap_halt:
    cli
    hlt
    jmp bootstrap_halt

section .data align=8
gdt:
    dq 0
    dq 0x00CF9A000000FFFF      ; 0x08: 32-bit flat code
    dq 0x00CF92000000FFFF      ; 0x10: flat data
    dq 0x00AF9A000000FFFF      ; 0x18: 64-bit code, L=1 D=0
bootstrap_tss_descriptor:
    dq 0, 0                   ; 0x20: 16-byte TSS descriptor filled before LTR
gdt_end:
gdt_pointer:
    dw gdt_end - gdt - 1
    dd gdt
section .rodata align=4
initial_mxcsr:
    dd 0x1F80

section .bss align=4096
; Early boot has no allocator. These bounded reservations are owned by the
; bootstrap and must remain reserved when the physical allocator is introduced.
pml4: resb 4096
pdpt: resb 4096
page_directories: resb 4 * 4096
align 16
stack_bottom: resb 16384
stack_top:
