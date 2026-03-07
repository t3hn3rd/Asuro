#!/usr/bin/env bash
echo " "
echo "======================="
echo " "
echo "Compiling Stub..."
echo " "
nasm -f elf src/stub/stub.asm -o lib/stub.o
nasm -f elf src/stub/splash_tga.asm -o lib/splash_tga.o