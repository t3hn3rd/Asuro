#!/usr/bin/env bash
# Shared source-architecture selection; callers run from the repository root.
# Folder names: x86 = i386, x86_64 = x86_64.
export ASURO_ARCH="${ASURO_ARCH:-x86}"
if [[ ! "$ASURO_ARCH" =~ ^[a-z][a-z0-9_]*$ ]]; then
    echo "Invalid ASURO_ARCH: $ASURO_ARCH" >&2
    return 1
fi
if [[ ! -d "src/arch/$ASURO_ARCH" ]]; then
    echo "Architecture sources not found: src/arch/$ASURO_ARCH" >&2
    return 1
fi
