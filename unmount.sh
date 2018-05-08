#!/bin/sh
ERRCOUNT=0
echo " "
echo "========================="
echo "==    ASURO UNMOUNT    =="
echo "========================="
echo " "
echo "Unmounting Asuro..."
sudo umount /mnt/asuro
sudo qemu-nbd --disconnect /dev/nbd0
sudo rmmod nbd
