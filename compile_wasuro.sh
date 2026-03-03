#!/usr/bin/env bash
# compile_wasuro.sh — Pull Wasuro WASM runtime source into /wasuro
# Clones the repo (sparse, src/wasm only) and copies the Pascal sources
# into /code/wasuro so the FPC build can reference them via -Fu.
set -e

WASURO_REPO="https://gitea.spexeah.com/Spexeah/Wasuro.git"
WASURO_BRANCH="develop"
WASURO_TMP="/tmp/wasuro"
WASURO_OUT="/code/wasuro"

echo " "
echo "======================="
echo " "
echo "Pulling Wasuro WASM runtime..."
echo " "

# Skip if wasuro/ already has .pas files (cached from previous build)
if [ -n "$(find "${WASURO_OUT}" -name '*.pas' 2>/dev/null | head -1)" ]; then
    echo "Wasuro sources already present in ${WASURO_OUT}, skipping pull."
    echo " "
    exit 0
fi

# Clone sparse checkout (only src/wasm)
rm -rf "$WASURO_TMP"
git clone --depth 1 --branch "${WASURO_BRANCH}" --filter=blob:none --sparse \
    "${WASURO_REPO}" "${WASURO_TMP}" 2>&1
cd "$WASURO_TMP"
git sparse-checkout set src/wasm 2>&1
cd /code

echo "Copying src/wasm to ${WASURO_OUT}..."
rm -rf "$WASURO_OUT"
mkdir -p "$WASURO_OUT"
cp -a "${WASURO_TMP}/src/wasm/"* "$WASURO_OUT"/
rm -rf "$WASURO_TMP"

TOTAL=$(find "$WASURO_OUT" -name '*.pas' | wc -l)
echo "Copied ${TOTAL} Pascal source files."
echo " "
echo "Wasuro pull complete."
echo " "
