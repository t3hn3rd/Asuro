#!/bin/sh
ERRCOUNT=0
echo " "
echo "======================="
echo "== ASURO COMPILATION =="
echo "======================="
echo " "
echo "Checking out latest VM Source..."
echo " "
./updatevm.sh
echo " "
echo "Compiling ASM Stub..."
echo " "
rm lib/*

nasm -f elf src/stub/stub.asm -o lib/stub.o
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

./versioning.sh

if [ "$1" = "-d" ]
then
	echo "Compiling Debug FPC Sources..."
	echo " "
	fpc -Aelf -gw -n -va -O3 -Op3 -Si -Sc -Sg -Xd -CX -XXs -CfSSE -CfSSE2 -Rintel -Pi386 -Tlinux -FElib/ -Fusrc/* -Fusrc/driver/* src/kernel.pas
else
	echo "Compiling FPC Sources..."
	echo " "
	fpc -Aelf -gw -n -va -O3 -Op3 -Si -Sc -Sg -Xd -CX -XXs -CfSSE -CfSSE2 -Rintel -Pi386 -Tlinux -FElib/ -Fusrc/* -Fusrc/driver/* -Fusrc/driver/net/* src/kernel.pas
fi

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
	wget -q https://img.shields.io/badge/build-failed-red.svg -O release/build.svg
else
	echo "No errors."
	wget -q https://img.shields.io/badge/build-succeeded-green.svg -O release/build.svg	
fi
echo " "
echo "======================="
echo " "

cp Asuro.iso ~/host/Asuro.iso
cp Asuro.iso release/Asuro.iso

checksum=$(md5sum release/Asuro.iso | awk '{print $1}')
wget -q https://img.shields.io/badge/checksum-$checksum-important.svg -O release/checksum.svg	
cd release
touch *
#svn commit -m "Versioning Auto-Commit"
cd ..
