#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/architecture.sh"
echo " "
echo "======================="
echo " "
echo "Compiling FPC Sources..."
echo " "
# Keep other architectures out of FPC's unit resolution, including arch/ itself.
FU_PATHS=()
while IFS= read -r -d '' dir; do
    FU_PATHS+=("-Fu$dir")
done < <(find src wasuro compat -path src/arch -prune -o -type d -print0
         find "src/arch/$ASURO_ARCH" -type d -print0)

if [[ "$ASURO_ARCH" == "x86" ]]; then
    fpc -Aelf -gw -g -gl -n -v0e -O3 -OpPENTIUM3 -Si -Sc -Sg -Xd -CX -XXs -CfSSE -CfSSE2 -Rintel -Pi386 -Tlinux -FElib/ "${FU_PATHS[@]}" src/asuro.pas
else
    echo "No compiler found for target: $ASURO_ARCH" >&2
    exit 1
fi
