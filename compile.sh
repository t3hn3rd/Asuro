#!/bin/sh
ERRCOUNT=0
echo " "
echo "======================="
echo " "
echo "Asuro Compilation"
echo " "

#Compile Stub.asm
./compile_stub.sh
if [ $? -ne 0 ]
then
	echo "Failed to compile stub!"
	ERRCOUNT=$((ERRCOUNT+1))	
else
	echo "Success."
fi

#Generate .pas with versioning headers.
./compile_vergen.sh

#Compile all .pas sources
./compile_sources.sh
if [ $? -ne 0 ]
then
	echo " "
	echo "Failed to compile FPC Sources!"
	ERRCOUNT=$((ERRCOUNT+1))	
else
	echo " "
	echo "Success."
fi

#Link into a binary.
./compile_link.sh
if [ $? -ne 0 ]
then
	echo "Failed linking!"
	ERRCOUNT=$((ERRCOUNT+1))
else
	echo "Success."
fi

#Generate an ISO with GRUB as the Bootloader.
./compile_isogen.sh
if [ $? -ne 0 ]
then
	echo "Failed to create ISO!"
	ERRCOUNT=$((ERRCOUNT+1))
else
	echo "Success."
fi

#Call generate final artifacts based on failure or success of the above.
if [ "$ERRCOUNT" -ne "0" ]
then
	./compile_finish.sh "failed"
else
	./compile_finish.sh "success"
fi

cd ..
