# compile.sh

Top-level build orchestrator for the Asuro kernel.

## Overview

`compile.sh` is the main entry point for building the Asuro operating system. It sequentially invokes each stage of the build pipeline, halting on the first failure. After all stages complete (or a failure occurs), it calls `compile_finish.sh` to generate a build-status badge and set the exit code.

## Prerequisites

- All sub-scripts must be present in the same directory as `compile.sh`.
- The Docker build container must provide: `bash`, `nasm`, `fpc`, `gcc`, `ld`, `grub-mkrescue`, `git`, `wget`, and standard POSIX utilities.

## Inputs

None directly. Each sub-script reads its own inputs from the source tree.

## Outputs

- All artifacts produced by the sub-scripts (object files, kernel binary, ISO image, version info, badges, documentation).
- Final exit code: `0` on success, `1` on failure.

## Behavior

1. Clears the `lib/` directory to ensure a clean build.
2. Defines a helper function `runOrFail` that runs a command and increments `ERRCOUNT` on failure.
3. Resolves its own directory (`TOOLCHAIN_DIR`) so sub-scripts can be located by absolute path.
4. Declares an ordered list of build steps (script name and error message pairs):
   - `compile_stub.sh` -- Assemble boot stubs.
   - `compile_vergen.sh` -- Generate version information.
   - `compile_lvgl.sh` -- Compile the LVGL graphics library.
   - `compile_wasuro.sh` -- Pull the Wasuro WASM runtime sources.
   - `compile_sources.sh` -- Compile Free Pascal kernel sources.
   - `compile_link.sh` -- Link all object files into `kernel.bin`.
   - `compile_isogen.sh` -- Create the bootable ISO image.
   - `compile_docs.sh` -- Generate project documentation.
5. Iterates through the steps. If `ERRCOUNT` is non-zero, all remaining steps are skipped.
6. Calls `compile_finish.sh` with either `"success"` or `"failed"` depending on whether any errors were recorded.
7. Changes directory back up one level (`cd ..`).

## Notes

- `compile_finish.sh` is sourced (`. script`) rather than executed as a sub-process, so its `exit` call terminates the entire pipeline.
- The build is fail-fast: the first failing step prevents all subsequent steps from running, but the finish step always runs to produce a status badge.
