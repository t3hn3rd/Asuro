#!/usr/bin/env bash
# Multi-architecture build updates: Copyright 2026 Aaron Hance.
set -e
source "$(dirname "${BASH_SOURCE[0]}")/target.sh"
echo " "
echo "======================="
echo " "
echo "Creating ISO..."
echo " "
mkdir -p "$ISO_ROOT/boot/grub"
if [ "$ASURO_ARCH" != x86 ]; then
    cp iso/boot/grub/grub.cfg "$ISO_ROOT/boot/grub/grub.cfg"
fi
cp "$BIN_DIR/kernel.bin" "$ISO_ROOT/boot/asuro.bin"
grub-mkrescue -o "$ISO_FILE" "$ISO_ROOT"
