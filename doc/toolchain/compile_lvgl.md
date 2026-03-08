# compile_lvgl.sh

Downloads and compiles LVGL v9.2 into a static library for the kernel.

## Overview

`compile_lvgl.sh` clones the LVGL graphics library source, cross-compiles every C source file to 32-bit freestanding ELF objects, and archives them into `lib/liblvgl.a`. It also compiles any custom Asuro-specific LVGL extension files found in `lvglh/`. A caching mechanism on the host-mounted `/code/lvgl/` directory allows subsequent builds to skip the entire compilation.

## Prerequisites

- `git`, `gcc`, `ar`, and standard POSIX utilities must be available.
- The `lvglh/` directory must contain an `lv_conf.h` configuration header (and optionally custom `.c` files).
- The `lib/` output directory must exist.

## Inputs

| Source | Description |
|--------|-------------|
| LVGL Git repository | Cloned from `https://github.com/lvgl/lvgl.git` at tag `v9.2.2`. |
| `lvglh/` | Project-local directory containing `lv_conf.h` and optional custom C source files. |
| `/code/lvgl/liblvgl.a` | Optional cached artifact from a previous build (host mount). |

## Outputs

| File | Description |
|------|-------------|
| `lib/liblvgl.a` | Static archive containing all compiled LVGL and custom extension objects. |
| `/code/lvgl/` | Cached copy of the static library, LVGL source, and object files for future builds. |

## Behavior

1. **Cache check**: If `/code/lvgl/liblvgl.a` exists, copies it to `lib/` and exits immediately.
2. **Clone**: Shallow-clones the LVGL repository at the specified version tag into `/tmp/lvgl`.
3. **Discover sources**: Finds all `.c` files under the LVGL `src/` directory, excluding test files.
4. **Compile**: Compiles each source file with GCC using the following key flags:
   - `-m32 -march=i686` -- 32-bit i686 target.
   - `-ffreestanding -fno-builtin -fno-stack-protector -fno-pic -fno-pie` -- Bare-metal environment.
   - `-O2` -- Optimization level 2.
   - `-DLV_CONF_INCLUDE_SIMPLE` -- Tells LVGL to include `lv_conf.h` via a simple path.
   - Include paths for `lvglh/` and the LVGL source tree.
5. **Archive**: Collects all `.o` files into `lib/liblvgl.a` using `ar rcs`.
6. **Custom extensions**: If `lvglh/` contains `.c` files, compiles them with the same flags and appends the resulting objects to `liblvgl.a`.
7. **Cache write**: Copies the static library, source, and objects to `/code/lvgl/` on the host mount for future builds.

Progress is reported every 50 files. The script aborts with exit code 1 if any compilation errors occur.

## Notes

- All intermediate work (clone, object files) happens in `/tmp` for speed on container-local filesystems.
- The cache lives on the host mount at `/code/lvgl/`. Deleting `lvgl/liblvgl.a` from the project root forces a full rebuild.
- The static library is linked into the kernel by `compile_link.sh` using `--start-group` / `--end-group` alongside `libgcc`.
