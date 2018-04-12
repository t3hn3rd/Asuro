;
; Kernel stub
;
 
;
; We are in 32bits protected mode
;
[bits 32]
 
;
; Export entrypoint
;
global _loader
 
;
; Import kernel entrypoint
;
extern kmain
 
;
; Posible multiboot header flags
;
MULTIBOOT_MODULE_ALIGN          equ     1<<0
MULTIBOOT_MEMORY_MAP            equ     1<<1
MULTIBOOT_GRAPHICS_FIELDS       equ     1<<2
MULTIBOOT_ADDRESS_FIELDS        equ     1<<16
 
;
; Multiboot header defines
;
MULTIBOOT_HEADER_MAGIC          equ     0x1BADB002
MULTIBOOT_HEADER_FLAGS          equ     MULTIBOOT_MODULE_ALIGN | MULTIBOOT_MEMORY_MAP | MULTIBOOT_GRAPHICS_FIELDS
MULTIBOOT_HEADER_CHECKSUM       equ     -(MULTIBOOT_HEADER_MAGIC + MULTIBOOT_HEADER_FLAGS)
 
;
; Kernel stack size
;
KERNEL_STACKSIZE                equ     0x4000
KERNEL_VIRTUAL_BASE 		  equ	0xC0000000
KERNEL_PAGE_NUMBER			  equ	(KERNEL_VIRTUAL_BASE >> 22)
 
section .data
align 0x1000
_PageDirectory equ BootPageDirectory
global _PageDirectory
BootPageDirectory:
	dd 0x00000083
	times (KERNEL_PAGE_NUMBER - 1) dd 0
	dd 0x00000083
	times (1024 - KERNEL_PAGE_NUMBER - 1) dd 0

section .text
;
; Multiboot header
;
align 4
dd MULTIBOOT_HEADER_MAGIC
dd MULTIBOOT_HEADER_FLAGS
dd MULTIBOOT_HEADER_CHECKSUM
dd 0
dd 0
dd 0
dd 0
dd 0
dd 0
dd 1280
dd 1024
dd 16

;
; Entrypoint
;
loader equ _loader
;loader equ (_loader - 0xC0000000)
global loader

_loader:
	mov ecx, (BootPageDirectory - KERNEL_VIRTUAL_BASE)
	mov cr3, ecx
	
	mov ecx, cr4
	or ecx, 0x00000010
	mov cr4, ecx

	mov ecx, cr0
	or ecx, 0x80000000
	mov cr0, ecx

	lea ecx, [kstart]
	jmp ecx

kstart:
	   mov dword [BootPageDirectory], 0
    	   invlpg [0]	   		
        mov esp, KERNEL_STACK+KERNEL_STACKSIZE  ;Create kernel stack
        push eax                                ;Multiboot magic number
	    add ebx, KERNEL_VIRTUAL_BASE
        push ebx                                ;Multiboot info
        call kmain                              ;Call kernel entrypoint
        cli                                     ;Clear interrupts
        hlt                                     ;Halt machine
 
section .bss

;
; Kernel stack location
;
align 32
global KERNEL_STACK
KERNEL_STACK:
        resb KERNEL_STACKSIZE
