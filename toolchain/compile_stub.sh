#!/usr/bin/env bash
echo " "
echo "======================="
echo " "
echo "Compiling Stub..."
echo " "
nasm -f elf src/arch/x86/boot/stub.asm -o lib/stub.o
nasm -f elf src/boot/splash_tga.asm -o lib/splash_tga.o