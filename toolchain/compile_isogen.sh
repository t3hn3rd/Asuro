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
echo "Creating ISO..."
mkdir -p "$ISO_ROOT/boot/grub"
if [ "$(realpath "$GRUB_CONFIG")" != "$(realpath "$ISO_ROOT/boot/grub/grub.cfg")" ]; then
    cp "$GRUB_CONFIG" "$ISO_ROOT/boot/grub/grub.cfg"
fi
cp "$BIN_DIR/kernel.bin" "$ISO_ROOT/boot/asuro.bin"
grub-mkrescue -o "$ISO_FILE" "$ISO_ROOT"
