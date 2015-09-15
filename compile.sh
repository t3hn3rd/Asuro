#!/bin/sh
ERRCOUNT=0
echo "======================="
echo "== ASURO COMPILATION =="
echo "======================="
echo " "
echo "Compiling ASM Stub..."
echo " "
nasm -f elf src/stub.asm -o lib/stub.o
if [ $? -ne 0 ]
then
	echo "Failed to compile stub!"
	ERRCOUNT=$((ERRCOUNT+1))	
else
	echo "Success."
fi

echo " "
echo "======================="
echo " "
echo "Compiling FPC Sources..."
echo " "
fpc -Aelf -n -O3 -Op3 -Si -Sc -Sg -Xd -CX -XXs -Rintel -Tlinux -FElib/ src/kernel.pas
if [ $? -ne 0 ]
then
	echo "Failed to compile FPC Sources!"
	ERRCOUNT=$((ERRCOUNT+1))	
else
	echo "Success."
fi

echo " "
echo "======================="
echo " "
echo "Linking..."
echo " "
ld -m elf_i386 -s --gc-sections -Tlinker.script -o bin/kernel.bin lib/stub.o lib/kernel.o lib/multiboot.o lib/system.o lib/console.o
if [ $? -ne 0 ]
then
	echo "Failed linking!"
	ERRCOUNT=$((ERRCOUNT+1))
else
	echo "Success."
fi

echo " "
echo "======================="
echo " "
echo "Creating ISO..."
echo " "
cp bin/kernel.bin iso/boot/asuro.bin
grub-mkrescue -o Asuro.iso iso
if [ $? -ne 0 ]
then
	echo "Failed to create ISO!"
	ERRCOUNT=$((ERRCOUNT+1))
else
	echo "Success."
fi

echo " "
echo "======================="
echo " "
if [ "$ERRCOUNT" -ne "0" ]
then
	echo "$ERRCOUNT Errors Occurred, please review."
else
	echo "No errors."	
fi
echo " "
echo "======================="
echo " "
