#!/usr/bin/env bash
ERRCOUNT=0
echo " "
echo "======================="
echo " "
echo "Asuro Compilation"
echo " "

#Compile Stub.asm
rm lib/*

runOrFail() {
	local binary=$1
	local errorText=$2
	if $binary; then
		echo "Success."
	else
		echo "$errorText"
		ERRCOUNT=$((ERRCOUNT+1))
	fi
}

runOrFail $(pwd)/compile_stub.sh "Failed to compile stub!"

#Generate .pas with versioning headers.
runOrFail $(pwd)/compile_vergen.sh "Versions failed to compile"

#Compile all .pas sources
runOrFail $(pwd)/compile_sources.sh "Failed to compile FPC Sources!"

#Link into a binary.
runOrFail $(pwd)/compile_link.sh "Failed linking!"

#Generate an ISO with GRUB as the Bootloader.
runOrFail ./compile_isogen.sh "Failed to create ISO!"

#Call generate final artifacts based on failure or success of the above.
if [ "$ERRCOUNT" -ne "0" ]
then
	./compile_finish.sh "failed"
else
	./compile_finish.sh "success"
fi

cd ..