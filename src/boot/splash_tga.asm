; Embed the boot splash TGA image into .rodata so it is linked
; directly into the kernel binary.
;
; Exported symbols:
;   _splash_tga_start  – pointer to the first byte of the TGA file
;   _splash_tga_end    – pointer one past the last byte
;   _splash_tga_size   – uint32 containing the file size

section .rodata

global _splash_tga_start
global _splash_tga_end
global _splash_tga_size

global _panic_tga_start
global _panic_tga_end
global _panic_tga_size

_splash_tga_start:
    incbin "img/asuro.tga"
_splash_tga_end:

_panic_tga_start:
    incbin "img/teapot.tga"
_panic_tga_end:

_splash_tga_size: dd (_splash_tga_end - _splash_tga_start)
_panic_tga_size: dd (_panic_tga_end - _panic_tga_start)
