#!/usr/bin/env bash
echo " "
echo "======================="
echo " "
echo "Linking..."
echo " "
objstring=""; 
for object in `find lib/ -name "*.o"`; do
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