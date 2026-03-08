#!/usr/bin/env bash
ERRCOUNT=0
echo " "
echo "======================="
echo " "
echo "Asuro Compilation"
echo " "

#Compile Stub.asm
rm -f lib/*

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

TOOLCHAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

declare -a run_steps=(
	"compile_stub.sh" "Failed to compile stub!"
	"compile_vergen.sh" "Versions failed to compile"
	"compile_lvgl.sh" "Failed to compile LVGL!"
	"compile_wasuro.sh" "Failed to pull Wasuro!"
	"compile_sources.sh" "Failed to compile FPC Sources!"
	"compile_link.sh" "Failed linking!"
	"compile_isogen.sh" "Failed to create ISO!"
	"compile_docs.sh" "Failed to generate documentation!"
)

for ((i=0; i<${#run_steps[@]}; i+=2))
do
	if [ "$ERRCOUNT" -eq "0" ]
	then
			script="${TOOLCHAIN_DIR}/${run_steps[$i]}"
			message="${run_steps[$i+1]}"
			runOrFail "$script" "$message"
	fi
done

#Call generate final artifacts based on failure or success of the above.
if [ "$ERRCOUNT" -ne "0" ]
then
	. "${TOOLCHAIN_DIR}/compile_finish.sh" "failed"
else
	. "${TOOLCHAIN_DIR}/compile_finish.sh" "success"
fi

cd ..