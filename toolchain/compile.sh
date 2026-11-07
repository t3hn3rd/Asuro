#!/usr/bin/env bash
# Multi-architecture build updates: Copyright 2026 Aaron Hance.
ERRCOUNT=0
echo " "
echo "======================="
echo " "
echo "Asuro Compilation"
echo " "

TOOLCHAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TOOLCHAIN_DIR/target.sh"
mkdir -p "$OBJ_DIR" "$BIN_DIR"
# Clean only this target's generated objects; preserve other architectures.
find "$OBJ_DIR" -maxdepth 1 -type f \( -name '*.o' -o -name '*.ppu' -o -name '*.a' \) -delete

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
	"compile_stub.sh" "Failed to compile stub!"
	"compile_vergen.sh" "Versions failed to compile"
	"compile_lvgl.sh" "Failed to compile LVGL!"
	"compile_icons.sh" "Failed to generate icons!"
	"compile_wasuro.sh" "Failed to pull Wasuro!"
	"compile_sources.sh" "Failed to compile FPC Sources!"
	"compile_initcalls.sh" "Failed to generate INITFINAL table!"
	"compile_link.sh" "Failed linking!"
	"compile_isogen.sh" "Failed to create ISO!"
	"compile_docs.sh" "Failed to generate documentation!"
)

if [ "$ASURO_ARCH" = x86_64 ]; then
    # Bootstrap milestone: no desktop/runtime dependencies until they are ported.
    run_steps=(
        "compile_stub.sh" "Failed to compile stub!"
        "compile_sources.sh" "Failed to compile FPC Sources!"
        "compile_link.sh" "Failed linking!"
        "compile_isogen.sh" "Failed to create ISO!"
    )
fi

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
if [ "$ASURO_ARCH" = x86_64 ]; then
    if [ "$ERRCOUNT" -ne 0 ]; then exit 1; fi
    echo "No errors. Bootstrap image: $ISO_FILE"
    exit 0
fi
if [ "$ERRCOUNT" -ne "0" ]
then
	. "${TOOLCHAIN_DIR}/compile_finish.sh" "failed"
else
	. "${TOOLCHAIN_DIR}/compile_finish.sh" "success"
fi

cd ..
