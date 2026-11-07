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
# Shared target selection. Source this file from build steps.
ASURO_ARCH="${ASURO_ARCH:-x86}"
case "$ASURO_ARCH" in
    x86)
        OBJ_DIR=lib
        BIN_DIR=bin
        ISO_ROOT=iso
        ISO_FILE=Asuro.iso
        NASM_FORMAT=elf
        LD_FORMAT=elf_i386
        LINKER_SCRIPT=toolchain/linker.script
        ;;
    x86_64)
        OBJ_DIR=lib/x86_64
        BIN_DIR=bin/x86_64
        ISO_ROOT=bin/x86_64/iso
        ISO_FILE=Asuro-x86_64.iso
        NASM_FORMAT=elf64
        LD_FORMAT=elf_x86_64
        LINKER_SCRIPT=toolchain/x86_64/linker.script
        ;;
    *) echo "Unsupported ASURO_ARCH: $ASURO_ARCH" >&2; exit 1 ;;
esac
export ASURO_ARCH OBJ_DIR BIN_DIR ISO_ROOT ISO_FILE NASM_FORMAT LD_FORMAT LINKER_SCRIPT
