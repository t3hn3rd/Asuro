#!/bin/sh
ERRCOUNT=0
echo " "
echo "======================="
echo "==    ASURO MOUNT    =="
echo "======================="
echo " "
echo "Mounting Asuro..."
sudo modprobe nbd
if [ $? -ne 0 ]
then
	echo "Failed load nbd!"
	ERRCOUNT=$((ERRCOUNT+1))
fi

sudo qemu-nbd --connect=/dev/nbd0 IMAGE.img
if [ $? -ne 0 ]
then
	echo "Failed to mount Image!"
	ERRCOUNT=$((ERRCOUNT+1))
fi

sudo partx -a /dev/nbd0
if [ $? -ne 0 ]
then
	echo "Failed to find Partitions!"
	ERRCOUNT=$((ERRCOUNT+1))
fi

sudo mount /dev/nbd0p1 /mnt/asuro
if [ $? -ne 0 ]
then
	echo "Failed to mount Asuro!"
	ERRCOUNT=$((ERRCOUNT+1))
fi

echo " "
echo "======================="
echo " "
if [ "$ERRCOUNT" -ne "0" ]
then
	./unmount.sh
	echo " "
	echo "======================="
	echo " "
	echo "$ERRCOUNT Errors Occurred, please review."
else
	echo "No errors."	
fi

echo " "
echo "======================="
echo " "
