#!/bin/sh
ERRCOUNT=0
echo " "
echo "======================="
echo "==  ASURO OPERATION  =="
echo "======================="
echo " "
echo "Running Asaro..."
qemu-system-i386 -cdrom Asuro.iso
if [ $? -ne 0 ]
then
	echo "Failed to run Asaro!"
	ERRCOUNT=$((ERRCOUNT+1))
else
	echo "Finished Successfully."
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
