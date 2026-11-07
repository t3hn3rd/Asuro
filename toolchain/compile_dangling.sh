#!/usr/bin/env bash
set -euo pipefail

echo "Generating dangling Pascal units..."
TOOLCHAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${TOOLCHAIN_DIR}/.."
source "$TOOLCHAIN_DIR/architecture.sh"
OUT="$(pwd)/src/boot/dangling_units.inc"
# Remove stale output before attempting analysis. Work in a separate temporary
# repository so developer Moderne runs and generated sources cannot contaminate it.
rm -f "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src" "$WORK/compat"
cp -a src/. "$WORK/src/"
cp -a compat/. "$WORK/compat/"
# Do not parse inactive architectures: incomplete ports must not break this build.
for dir in "$WORK/src/arch/"*; do
    [[ "$(basename "$dir")" == "$ASURO_ARCH" ]] || rm -rf "$dir"
done
git -C "$WORK" init -q
git -C "$WORK" remote add origin https://gitea.spexeah.com/Spexeah/Asuro.git
PASCAL_JAVA_OPTIONS='-Dpascal.sourceRoots=src,compat -Dpascal.failOnParseError=true' pascal-lst "$WORK"
mod run "$WORK" --recipe org.openrewrite.pascal.boot.FindDanglingUnits \
    --recipe-option "architecture=$ASURO_ARCH"
dangling-include "$WORK" "$OUT"
