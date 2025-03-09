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

declare -a run_steps=(
	'compile_stub.sh "Failed to compile stub!"'
	'compile_vergen.sh "Versions failed to compile"'
	'compile_sources.sh "Failed to compile FPC Sources!"'
	'compile_link.sh "Failed linking!"'
	'compile_isogen.sh "Failed to create ISO!"'
)

for command in "${run_steps[@]}"
do
	if [ "$ERRCOUNT" -eq "0" ]
	then
		runOrFail $(pwd)/$command
	fi
done

#Call generate final artifacts based on failure or success of the above.
if [ "$ERRCOUNT" -ne "0" ]
then
	. ./compile_finish.sh "failed"
else
	. ./compile_finish.sh "success"
fi

cd ..