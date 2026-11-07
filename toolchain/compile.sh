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
TOOLCHAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TOOLCHAIN_DIR/target.sh"
mkdir -p "$OBJ_DIR" "$BIN_DIR"
# Preserve generated objects belonging to other targets.
find "$OBJ_DIR" -maxdepth 1 -type f \( -name '*.o' -o -name '*.ppu' -o -name '*.a' \) -delete

for step in "${BUILD_STEPS[@]}"; do
    if bash "$TOOLCHAIN_DIR/compile_$step.sh"; then
        echo "Success."
    else
        echo "Failed build step: $step" >&2
        if [ -n "$FINISH_SCRIPT" ]; then bash "$TOOLCHAIN_DIR/$FINISH_SCRIPT" failed; fi
        exit 1
    fi
done
if [ -n "$FINISH_SCRIPT" ]; then bash "$TOOLCHAIN_DIR/$FINISH_SCRIPT" success; fi
echo "No errors. Image: $ISO_FILE"
