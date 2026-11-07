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
echo "Linking..."
objects=()
boot_object="$OBJ_DIR/${ASM_ENTRY//\//_}"
boot_object="${boot_object%.asm}.o"
objects+=("$boot_object")
while IFS= read -r -d '' object; do
    if [ "$object" != "$boot_object" ]; then objects+=("$object"); fi
done < <(find "$OBJ_DIR" -maxdepth 1 -type f -name '*.o' -print0 | LC_ALL=C sort -z)
libraries=()
while IFS= read -r -d '' library; do libraries+=("$library"); done \
    < <(find "$OBJ_DIR" -maxdepth 1 -type f -name '*.a' -print0 | LC_ALL=C sort -z)
if "$LINK_COMPILER_RUNTIME"; then
    libraries+=("$("$C_COMPILER" "${C_TARGET_OPTIONS[@]}" -print-libgcc-file-name)")
fi
ld -m "$LD_FORMAT" "${LINK_OPTIONS[@]}" --gc-sections --no-warn-execstack \
    -T"$LINKER_SCRIPT" -o "$BIN_DIR/kernel.bin" "${objects[@]}" \
    --start-group "${libraries[@]}" --end-group
"${KERNEL_VALIDATOR[@]}" "$BIN_DIR/kernel.bin"
