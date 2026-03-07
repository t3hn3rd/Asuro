#!/usr/bin/env bash
echo " "
echo "======================="
echo " "
echo "Compiling FPC Sources..."
echo " "
# Build -Fu flags for all directories under src/ and wasuro/
FU_PATHS="-Fusrc -Fuwasuro"
for dir in $(find src wasuro -type d 2>/dev/null); do
    FU_PATHS="$FU_PATHS -Fu$dir"
done

fpc -Aelf -gw -g -gl -n -v0ew -O3 -OpPENTIUM3 -Si -Sc -Sg -Xd -CX -XXs -CfSSE -CfSSE2 -Rintel -Pi386 -Tlinux -FElib/ $FU_PATHS src/kernel.pas