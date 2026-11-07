#!/usr/bin/env bash
# Copyright 2026 Aaron Hance
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
PASCAL_COMPILER=ppcx64
PASCAL_ENTRY="$ARCH_SOURCE_ROOT/arch.$ASURO_ARCH.boot.pas"
PASCAL_OPTIONS=(-O2)
C_TARGET_OPTIONS=(-m64)
NASM_FORMAT=elf64
LD_FORMAT=elf_x86_64
LINKER_SCRIPT="$TARGET_TOOLCHAIN_DIR/linker.script"
# The bootstrap does not depend on the desktop or hosted runtime.
BUILD_STEPS=(stub sources link isogen)
case "${ASURO_BOOT_TEST:-none}" in
    none) ;;
    ud|pf|df) PASCAL_OPTIONS+=("-dASURO_TEST_${ASURO_BOOT_TEST^^}") ;;
    *) echo "Unknown ASURO_BOOT_TEST" >&2; exit 1 ;;
esac

KERNEL_VALIDATOR=(grub-file --is-x86-multiboot)
