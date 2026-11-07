#!/usr/bin/env bash
# Multi-architecture build updates: Copyright 2026 Aaron Hance.
set -e
source "$(dirname "${BASH_SOURCE[0]}")/target.sh"
echo " "
echo "======================="
echo " "
echo "Compiling FPC Sources..."
echo " "
# The build selects one platform implementation; shared units cannot select CPUs.
python3 toolchain/check_arch_boundaries.py
# Build -Fu flags for the selected architecture and shared sources.
if [ "$ASURO_ARCH" = x86_64 ]; then
    test_flags=()
    case "${ASURO_BOOT_TEST:-none}" in
        none) ;;
        ud) test_flags=(-dASURO_TEST_UD) ;;
        pf) test_flags=(-dASURO_TEST_PF) ;;
        df) test_flags=(-dASURO_TEST_DF) ;;
        *) echo "Unknown ASURO_BOOT_TEST" >&2; exit 1 ;;
    esac
    # Restrict search paths: never accidentally select the i386 system unit.
    exec ppcx64 -n -O2 -Si -Sc -Sg -Xd -CX -Rintel -Tlinux \
        -Fu"src/arch/$ASURO_ARCH/platform" -Fusrc/core -Fusrc/core/strings -Fusrc/driver/storage -Fusrc/arch/x86_64/proc -Fusrc/core/ds -Fusrc/proc -Fusrc/io -Fusrc/arch/common -Fusrc/debug -Fusrc/boot -Fusrc/memory -Fusrc/arch/x86_64/memory -Fu"src/arch/x86_64" -FU"$OBJ_DIR" -FE"$BIN_DIR" "${test_flags[@]}" \
        src/arch/x86_64/arch.x86_64.boot.pas
fi
FU_PATHS="-Fusrc/arch/$ASURO_ARCH/platform -Fusrc -Fuwasuro -Fucompat"
for dir in $(find src wasuro compat -type d -not -path 'src/arch/*' 2>/dev/null) \
           $(find "src/arch/$ASURO_ARCH" src/arch/common -type d -not -path '*/platform*'); do
    FU_PATHS="$FU_PATHS -Fu$dir"
done

fpc -Aelf -gw -g -gl -n -v0e -O3 -OpPENTIUM3 -Si -Sc -Sg -Xd -CX -XXs -CfSSE -CfSSE2 -Rintel -Pi386 -Tlinux -FElib/ $FU_PATHS src/asuro.pas
