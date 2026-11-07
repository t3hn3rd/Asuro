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
# Load a target profile by convention rather than branching in build steps.
ASURO_ARCH="${ASURO_ARCH:-x86}"
if [[ ! "$ASURO_ARCH" =~ ^[a-zA-Z0-9_]+$ ]]; then
    echo "Invalid ASURO_ARCH" >&2; exit 1
fi
profile="$(dirname "${BASH_SOURCE[0]}")/targets/$ASURO_ARCH.sh"
if [ ! -f "$profile" ]; then echo "Unsupported ASURO_ARCH: $ASURO_ARCH" >&2; exit 1; fi
ARCH_SOURCE_ROOT="src/arch/$ASURO_ARCH"
TARGET_TOOLCHAIN_DIR="toolchain/$ASURO_ARCH"
OBJ_DIR="lib/$ASURO_ARCH"
BIN_DIR="bin/$ASURO_ARCH"
ISO_ROOT="$BIN_DIR/iso"
ISO_FILE="Asuro-$ASURO_ARCH.iso"
GRUB_CONFIG=iso/boot/grub/grub.cfg
ASM_ENTRY="$ARCH_SOURCE_ROOT/boot/stub.asm"
C_COMPILER=gcc
LINK_OPTIONS=()
LINK_COMPILER_RUNTIME=false
ASM_SHARED_ROOTS=()
FINISH_SCRIPT=
LVGL_CACHE_NAME="liblvgl-$ASURO_ARCH.a"
source "$profile"
export ASURO_ARCH OBJ_DIR BIN_DIR ISO_ROOT ISO_FILE
