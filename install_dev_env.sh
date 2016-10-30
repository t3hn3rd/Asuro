#!/bin/sh
ERRCOUNT=0
echo " "
echo "==================================="
echo "== ASURO DEV ENVIRONMENT INSTALL =="
echo "==================================="

echo " "
echo "Installing Build Essentials..."
sudo apt-get install build-essential:i386
if [ $? -ne 0 ]
then
	echo "Failed to install!"
	ERRCOUNT=$((ERRCOUNT+1))	
else
	echo "Success."
fi

echo " "
echo "Installing NASM..."
sudo apt-get install nasm
if [ $? -ne 0 ]
then
	echo "Failed to install!"
	ERRCOUNT=$((ERRCOUNT+1))	
else
	echo "Success."
fi

echo " "
echo "Installing Bin-Utils..."
sudo apt-get install binutils:i386
if [ $? -ne 0 ]
then
	echo "Failed to install!"
	ERRCOUNT=$((ERRCOUNT+1))	
else
	echo "Success."
fi

echo " "
echo "Installing FPC Sources..."
sudo apt-get install fpc-src:i386
if [ $? -ne 0 ]
then
	echo "Failed to install!"
	ERRCOUNT=$((ERRCOUNT+1))	
else
	echo "Success."
fi

echo " "
echo "Installing FPC..."
sudo apt-get install fpc:i386
if [ $? -ne 0 ]
then
	echo "Failed to install!"
	ERRCOUNT=$((ERRCOUNT+1))	
else
	echo "Success."
fi

echo " "
echo "Installing QEmu..."
sudo apt-get install qemu
if [ $? -ne 0 ]
then
	echo "Failed to install!"
	ERRCOUNT=$((ERRCOUNT+1))	
else
	echo "Success."
fi



echo " "
echo "WARNING: We assume you already have Grub installed."
echo "         Asuro depends on grub-mkrescue."

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


