# core.version

Auto-generated kernel version and build metadata constants.

## Overview

`core.version` is a generated unit updated by the build system on every compilation. It provides string and integer constants describing the current kernel version, build toolchain versions, source statistics, and the build timestamp. Other units reference these constants for display in boot messages, the kernel panic screen, and any context where version identification is required.

## Dependencies

None.

## Constants

### VERSION
Full dotted version string with release label: `'1.1.3-alpha-176-g63b67f58'`.

### VERSION_MAJOR
Major version component string: `'1'`.

### VERSION_MINOR
Minor version component string: `'1'`.

### VERSION_SUB
Sub-version (patch) component string: `'3'`.

### REVISION
Short Git commit hash of HEAD at compile time: `'63b67f58'`.

### RELEASE
Git-describe release tag including commit distance and hash: `'alpha-176-g63b67f58'`.

### LINE_COUNT
Total source lines counted at compile time: `99538`.

### FILE_COUNT
Total source files counted at compile time: `175`.

### DRIVER_COUNT
Number of driver units counted at compile time: `69`.

### FPC_VERSION
Free Pascal Compiler version used to build the kernel: `'3.2.2'`.

### NASM_VERSION
NASM assembler version used to assemble architecture-specific stubs: `'2.16.01'`.

### MAKE_VERSION
GNU Make version used to drive the build: `'4.3'`.

### COMPILE_DATE
Compilation date in MM/DD/YY format: `'08/03/26'`.

### COMPILE_TIME
Compilation time in HH:MM:SS format: `'17:23:28'`.

### CHECKSUM
MD5 checksum of the compiled kernel image computed by the build system: `'c30f33c48e462403420808146b9075e1'`.

## Notes

This file is regenerated on every build. Manual edits will be overwritten. The unit has no implementation section.
