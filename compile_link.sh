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
ld -m elf_i386 -s --gc-sections -Tlinker.script -o bin/kernel.bin $objstring