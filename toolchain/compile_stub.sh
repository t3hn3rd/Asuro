#!/usr/bin/env bash
# Multi-architecture build updates: Copyright 2026 Aaron Hance.
set -e
source "$(dirname "${BASH_SOURCE[0]}")/target.sh"
echo " "
echo "======================="
echo " "
echo "Compiling Stub..."
echo " "
nasm -f "$NASM_FORMAT" "src/arch/$ASURO_ARCH/boot/stub.asm" -o "$OBJ_DIR/stub.o"
if [ "$ASURO_ARCH" = x86 ]; then
    nasm -f "$NASM_FORMAT" src/boot/splash_tga.asm -o "$OBJ_DIR/splash_tga.o"
else
    nasm -f "$NASM_FORMAT" src/arch/x86_64/isr/entry.asm -o "$OBJ_DIR/isr_entry.o"
fi
