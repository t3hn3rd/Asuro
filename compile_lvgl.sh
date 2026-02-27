#!/usr/bin/env bash
# compile_lvgl.sh — Download LVGL v9.2 source and compile into lib/liblvgl.a
# Clone & compile in /tmp (fast container-local fs).
# Copy source + objects to /lvgl (host mount) for debugging.
set -e

LVGL_VERSION="v9.2.2"
LVGL_REPO="https://github.com/lvgl/lvgl.git"
LVGL_DIR="/tmp/lvgl"
OBJ_DIR="/tmp/lvgl_obj"
CONF_DIR="$(pwd)"
OUT_DIR="$(pwd)/lib"

CC="gcc"
CFLAGS="-m32 -march=i686 -ffreestanding \
    -fno-builtin -fno-stack-protector -fno-pic -fno-pie \
    -O2 -Wall -Wno-unused-function -Wno-unused-variable \
    -I${CONF_DIR} \
    -I${LVGL_DIR} \
    -I${LVGL_DIR}/.. \
    -DLV_CONF_INCLUDE_SIMPLE"

echo " "
echo "======================="
echo " "
echo "Compiling LVGL..."
echo " "

# Clone LVGL into /tmp (container-local)
rm -rf "$LVGL_DIR"
echo "Downloading LVGL ${LVGL_VERSION}..."
git clone --depth 1 --branch "${LVGL_VERSION}" "${LVGL_REPO}" "${LVGL_DIR}" 2>&1
echo "Download complete."

# Gather all LVGL .c source files (core library only, no demos/examples)
SOURCES=$(find "${LVGL_DIR}/src" -name '*.c' -not -path '*/test/*')
TOTAL=$(echo "$SOURCES" | wc -l)
echo "Found ${TOTAL} LVGL source files."

# Compile each .c file to .o (container-local)
rm -rf "$OBJ_DIR"
mkdir -p "$OBJ_DIR"

COUNT=0
ERRORS=0
for src in $SOURCES; do
    COUNT=$((COUNT + 1))
    rel="${src#${LVGL_DIR}/src/}"
    obj_path="${OBJ_DIR}/${rel%.c}.o"
    mkdir -p "$(dirname "$obj_path")"

    if ! $CC $CFLAGS -c "$src" -o "$obj_path" 2>&1; then
        echo "FAILED: $rel"
        ERRORS=$((ERRORS + 1))
    fi

    if [ $((COUNT % 50)) -eq 0 ]; then
        echo "  Compiled ${COUNT}/${TOTAL}..."
    fi
done

echo "Compiled ${COUNT} files (${ERRORS} errors)."

if [ "$ERRORS" -ne 0 ]; then
    echo "LVGL compilation FAILED with ${ERRORS} errors."
    exit 1
fi

# Archive into static library
OBJECTS=$(find "$OBJ_DIR" -name '*.o')
ar rcs "${OUT_DIR}/liblvgl.a" $OBJECTS
echo "Created ${OUT_DIR}/liblvgl.a"

# Copy source + objects to /lvgl host mount for debugging
echo "Copying LVGL source and objects to host mount..."
rm -rf /lvgl/* /lvgl/.[!.]* /lvgl/..?* 2>/dev/null || true
cp -a "$LVGL_DIR/src" /lvgl/src
cp -a "$OBJ_DIR" /lvgl/obj
echo "Done."

echo " "
echo "LVGL compilation complete."
echo " "
