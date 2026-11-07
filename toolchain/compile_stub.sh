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
set -e
source "$(dirname "${BASH_SOURCE[0]}")/target.sh"
echo "Compiling assembly..."
# Include only standalone assembly under the target and enabled shared roots.
# Relative source paths keep equal basenames in separate directories distinct.
while IFS= read -r -d '' source_file; do
    object="$OBJ_DIR/${source_file//\//_}"
    nasm -f "$NASM_FORMAT" "$source_file" -o "${object%.asm}.o"
done < <(find "$ARCH_SOURCE_ROOT" "${ASM_SHARED_ROOTS[@]}" -type f -name '*.asm' -print0 | LC_ALL=C sort -z)
