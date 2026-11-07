#!/usr/bin/env bash
# Multi-architecture build updates: Copyright 2026 Aaron Hance.
set -e
source "$(dirname "${BASH_SOURCE[0]}")/target.sh"
echo " "
echo "======================="
echo " "
echo "Compiling FPC Sources..."
echo " "
# Discover unit directories using the existing source roots. Architecture
# filtering follows the namespace convention; no unit directory is added by hand.
source_paths=()
while IFS= read -r -d '' dir; do
    case "$dir" in
        src/arch/*)
            namespace="${dir#src/arch/}"
            namespace="${namespace%%/*}"
            if [[ "$namespace" != "$ASURO_ARCH" && "$namespace" != common ]]; then
                continue
            fi
            ;;
    esac
    source_paths+=("-Fu$dir")
done < <(find src wasuro compat -type d -print0 | LC_ALL=C sort -zu)

exec "$PASCAL_COMPILER" -n -Si -Sc -Sg -Xd -CX -Rintel -Tlinux \
    "${PASCAL_OPTIONS[@]}" "${source_paths[@]}" \
    -FU"$OBJ_DIR" -FE"$BIN_DIR" "$PASCAL_ENTRY"
