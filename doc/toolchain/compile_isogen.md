# compile_isogen.sh

Creates a bootable GRUB ISO image containing the Asuro kernel.

## Overview

`compile_isogen.sh` copies the compiled kernel binary into the ISO directory structure and invokes `grub-mkrescue` to produce a bootable CD-ROM image. The resulting `Asuro.iso` can be booted in any x86 emulator (QEMU, VirtualBox, etc.) or written to physical media.

## Prerequisites

- `grub-mkrescue` (from GRUB utilities) and `xorriso` (its backend) must be available.
- `bin/kernel.bin` must exist (produced by `compile_link.sh`).
- The `iso/boot/` directory must exist and contain a GRUB configuration file (`iso/boot/grub/grub.cfg`).

## Inputs

| Source | Description |
|--------|-------------|
| `bin/kernel.bin` | The linked kernel binary. |
| `iso/` | Pre-existing ISO directory tree with GRUB configuration. |

## Outputs

| File | Description |
|------|-------------|
| `Asuro.iso` | Bootable GRUB rescue ISO image. |
| `iso/boot/asuro.bin` | Copy of the kernel binary placed into the ISO tree. |

## Behavior

1. Copies `bin/kernel.bin` to `iso/boot/asuro.bin`.
2. Runs `grub-mkrescue -o Asuro.iso iso` to generate the bootable ISO from the `iso/` directory tree.

## Notes

- The GRUB configuration in `iso/boot/grub/grub.cfg` must reference `asuro.bin` as the kernel to load.
- The ISO is generated in the project root directory.
