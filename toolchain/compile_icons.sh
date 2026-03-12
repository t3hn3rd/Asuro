#!/usr/bin/env bash
# compile_icons.sh — Generate file-type icon bitmap fonts from Font Awesome.
# Runs gen_file_icons.py to produce asuro_icons_{32,64,128}.c in lvglh/,
# then compiles each into a .o in lib/ for linking.
set -e

TOOLCHAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="$(pwd)/lvglh"
OUT_DIR="$(pwd)/lib"
FONT_CACHE="$(pwd)/img"
LVGL_DIR="/tmp/lvgl"
CACHE_DIR="/code/lvgl"

# Use cached LVGL source (or /tmp clone) for include paths
if [ -d "${CACHE_DIR}/src" ]; then
    LVGL_INC="${CACHE_DIR}"
elif [ -d "${LVGL_DIR}/src" ]; then
    LVGL_INC="${LVGL_DIR}"
else
    LVGL_INC="${CACHE_DIR}"
fi

CC="gcc"
CFLAGS="-m32 -march=i686 -ffreestanding \
    -fno-builtin -fno-stack-protector -fno-pic -fno-pie \
    -O2 -Wall -Wno-unused-function -Wno-unused-variable \
    -I${CONF_DIR} \
    -I${LVGL_INC} \
    -I${LVGL_INC}/.. \
    -DLV_CONF_INCLUDE_SIMPLE"

echo " "
echo "======================="
echo " "
echo "Generating file-type icons..."
echo " "

# Run the Python generator
python3 "${TOOLCHAIN_DIR}/gen_file_icons.py" "${CONF_DIR}" --font-dir "${FONT_CACHE}"

# Compile generated C files into object files
ERRORS=0
for src in "${CONF_DIR}"/asuro_icons_*.c; do
    [ -f "$src" ] || continue
    base="$(basename "${src%.c}")"
    echo "  Compiling ${base}.c ..."
    if ! $CC $CFLAGS -c "$src" -o "${OUT_DIR}/${base}.o" 2>&1; then
        echo "  FAILED: ${base}.c"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ "$ERRORS" -ne 0 ]; then
    echo "Icon compilation FAILED (${ERRORS} errors)."
    exit 1
fi

echo " "
echo "Icons generated and compiled."
echo " "
