#!/bin/sh
echo " "
echo "======================="
echo " "
echo "Compiling Stub..."
echo " "
rm lib/*
nasm -f elf src/stub/stub.asm -o lib/stub.o