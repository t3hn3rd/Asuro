# compile_sources.sh

Compiles the Asuro kernel Pascal sources with Free Pascal.

## Overview

`compile_sources.sh` invokes the Free Pascal Compiler (FPC) to compile the main kernel unit (`src/asuro.pas`) along with all dependent units. It dynamically discovers every subdirectory under `src/`, `wasuro/`, and `compat/` and passes them as unit search paths (`-Fu`) so that FPC can resolve all unit references.

## Prerequisites

- `fpc` (Free Pascal Compiler 3.2.2 or compatible) must be available.
- `find` must be available.
- The `src/`, `wasuro/`, and `compat/` directories must be populated with their respective Pascal sources.
- The `lib/` output directory must exist.

## Inputs

| Source | Description |
|--------|-------------|
| `src/asuro.pas` | The top-level kernel program unit. |
| `src/**/*.pas` | All kernel Pascal source units. |
| `wasuro/**/*.pas` | Wasuro WASM runtime units (pulled by `compile_wasuro.sh`). |
| `compat/**/*.pas` | Compatibility layer units. |

## Outputs

| File | Description |
|------|-------------|
| `lib/*.o` | ELF object files for each compiled unit. |
| `lib/*.ppu` | FPC precompiled unit files. |

## Behavior

1. Discovers all subdirectories under `src/`, `wasuro/`, and `compat/` using `find`.
2. Builds a `-Fu` flag string containing every discovered directory.
3. Invokes `fpc` with the following key flags:
   - `-Aelf` -- Output ELF-format assembly.
   - `-gw -g -gl` -- Generate DWARF debug info and line info.
   - `-n` -- Ignore `fpc.cfg`; do not load default configuration.
   - `-v0e` -- Verbosity: errors only.
   - `-O3` -- Aggressive optimization.
   - `-OpPENTIUM3` -- Optimize for Pentium III instruction scheduling.
   - `-Si -Sc -Sg` -- Enable inline, C-style operators, and goto support.
   - `-Xd` -- Do not search default library path.
   - `-CX -XXs` -- Create smartlinkable units and strip unused code.
   - `-CfSSE -CfSSE2` -- Use SSE/SSE2 floating-point.
   - `-Rintel` -- Use Intel assembler syntax.
   - `-Pi386 -Tlinux` -- Target i386 Linux (ELF).
   - `-FElib/` -- Output compiled files to `lib/`.

## Notes

- The `-n` flag is critical: it prevents FPC from loading any system-wide configuration that might introduce incompatible settings for the bare-metal target.
- The `-Xd` flag ensures FPC does not try to link against system libraries, since the kernel is freestanding.
- Object files produced here are later consumed by `compile_link.sh`.
