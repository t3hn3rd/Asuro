#!/usr/bin/env bash
echo " "
echo "======================="
echo " "
echo "Creating ISO..."
echo " "
cp bin/kernel.bin iso/boot/asuro.bin
grub-mkrescue -o Asuro.iso iso