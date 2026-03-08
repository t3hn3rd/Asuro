# compile_link.sh

Links all object files and libraries into the final kernel binary.

## Overview

`compile_link.sh` collects every `.o` object file in `lib/`, locates `libgcc` for i386, and invokes the GNU linker (`ld`) to produce `bin/kernel.bin`. The linker script `toolchain/linker.script` controls the memory layout of the resulting binary.

## Prerequisites

- `ld` (GNU linker) and `gcc` must be available.
- All object files must have been produced by prior build steps (`compile_stub.sh`, `compile_sources.sh`).
- `lib/liblvgl.a` must exist (produced by `compile_lvgl.sh`).
- `toolchain/linker.script` must exist.
- The `bin/` output directory must exist.

## Inputs

| Source | Description |
|--------|-------------|
| `lib/*.o` | All ELF object files (boot stub, Pascal units, splash screen, etc.). |
| `lib/liblvgl.a` | Static LVGL library archive. |
| `libgcc` (system) | GCC runtime support library for i386, located via `gcc -m32 -print-libgcc-file-name`. |
| `toolchain/linker.script` | Linker script defining section layout and entry point. |

## Outputs

| File | Description |
|------|-------------|
| `bin/kernel.bin` | The final linked, stripped kernel binary. |

## Behavior

1. Collects all `.o` files from `lib/`, excluding `lib/stub.o` from the general list.
2. Prepends `lib/stub.o` to the front of the object list so the boot entry point is linked first.
3. Locates `libgcc` for the 32-bit target using `gcc -m32 -print-libgcc-file-name`.
4. Invokes `ld` with the following flags:
   - `-m elf_i386` -- Target i386 ELF format.
   - `-s` -- Strip all symbol information.
   - `--gc-sections` -- Remove unused sections (works with FPC's `-CX -XXs` smart-linking).
   - `-T toolchain/linker.script` -- Use the project linker script.
   - `--start-group` / `--end-group` -- Wraps `liblvgl.a` and `libgcc` to resolve circular references between them.

## Notes

- `stub.o` must be first in the link order because it contains the multiboot header and the initial entry point that GRUB transfers control to.
- The `--start-group` / `--end-group` construct allows the linker to iterate over `liblvgl.a` and `libgcc` multiple times to resolve all symbols, which is necessary when C library objects have mutual dependencies.
