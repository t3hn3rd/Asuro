# compile_stub.sh

Assembles the low-level boot stub and splash screen objects.

## Overview

`compile_stub.sh` uses NASM to assemble two assembly source files into ELF object files. These objects contain the initial boot entry point and an embedded splash-screen TGA image, both of which are linked into the final kernel binary.

## Prerequisites

- `nasm` must be available on the PATH.
- The source files `src/arch/x86/boot/stub.asm` and `src/boot/splash_tga.asm` must exist.
- The `lib/` output directory must exist (created by `compile.sh` which clears it beforehand).

## Inputs

| File | Description |
|------|-------------|
| `src/arch/x86/boot/stub.asm` | x86 boot stub -- the kernel entry point before Pascal code takes over. |
| `src/boot/splash_tga.asm` | Embeds a TGA splash screen image as a binary blob. |

## Outputs

| File | Description |
|------|-------------|
| `lib/stub.o` | ELF object for the boot stub. |
| `lib/splash_tga.o` | ELF object for the splash screen data. |

## Behavior

1. Assembles `stub.asm` into `lib/stub.o` using NASM with the ELF output format (`-f elf`).
2. Assembles `splash_tga.asm` into `lib/splash_tga.o` using the same format.

## Notes

- Both files are assembled as 32-bit ELF objects, consistent with the i386 target architecture.
- `stub.o` is treated specially during linking: `compile_link.sh` places it first in the link order so that the boot entry point appears at the expected address.
