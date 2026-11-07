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
# Legacy output locations are retained for the existing VirtualBox workflow.
OBJ_DIR=lib
BIN_DIR=bin
ISO_ROOT=iso
ISO_FILE=Asuro.iso
PASCAL_COMPILER=fpc
PASCAL_ENTRY=src/asuro.pas
PASCAL_OPTIONS=(-Aelf -gw -g -gl -v0e -O3 -OpPENTIUM3 -XXs -CfSSE -CfSSE2 -Pi386)
C_TARGET_OPTIONS=(-m32 -march=i686)
NASM_FORMAT=elf
LD_FORMAT=elf_i386
LINKER_SCRIPT=toolchain/linker.script
LINK_OPTIONS=(-s)
LINK_COMPILER_RUNTIME=true
ASM_SHARED_ROOTS=(src/boot)
BUILD_STEPS=(stub vergen lvgl icons wasuro sources initcalls link isogen docs)
FINISH_SCRIPT=compile_finish.sh
LVGL_CACHE_NAME=liblvgl.a

KERNEL_VALIDATOR=(grub-file --is-x86-multiboot)
