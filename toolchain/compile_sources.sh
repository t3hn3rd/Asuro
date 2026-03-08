#!/usr/bin/env bash
echo " "
echo "======================="
echo " "
echo "Compiling FPC Sources..."
echo " "
# Build -Fu flags for all directories under src/, wasuro/ and compat/
FU_PATHS="-Fusrc -Fuwasuro -Fucompat"
for dir in $(find src wasuro compat -type d 2>/dev/null); do
    FU_PATHS="$FU_PATHS -Fu$dir"
done

fpc -Aelf -gw -g -gl -n -v0e -O3 -OpPENTIUM3 -Si -Sc -Sg -Xd -CX -XXs -CfSSE -CfSSE2 -Rintel -Pi386 -Tlinux -FElib/ $FU_PATHS src/asuro.pas