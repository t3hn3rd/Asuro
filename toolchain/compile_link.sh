#!/usr/bin/env bash
# Multi-architecture build updates: Copyright 2026 Aaron Hance.
set -e
source "$(dirname "${BASH_SOURCE[0]}")/target.sh"
echo " "
echo "======================="
echo " "
echo "Linking..."
echo " "
if [ "$ASURO_ARCH" = x86_64 ]; then
    ld -m "$LD_FORMAT" --gc-sections --no-warn-execstack \
        -T"$LINKER_SCRIPT" -o "$BIN_DIR/kernel.bin" "$OBJ_DIR/"*.o
    grub-file --is-x86-multiboot "$BIN_DIR/kernel.bin"
    exit
fi
objstring=""; 
for object in `find lib/ -maxdepth 1 -name "*.o"`; do
	if [ "$object" != "lib/stub.o" ]
	then
		objstring=$objstring$object" ";
	fi
done;
objstring=lib/stub.o" "$objstring 
echo "Object Files: "$objstring
echo " "

# Find libgcc for i386 (needed by LVGL compiled with gcc)
LIBGCC=$(gcc -m32 -print-libgcc-file-name)
echo "libgcc: ${LIBGCC}"

ld -m elf_i386 -s --gc-sections --no-warn-execstack -Ttoolchain/linker.script -o bin/kernel.bin $objstring --start-group lib/liblvgl.a ${LIBGCC} --end-group
