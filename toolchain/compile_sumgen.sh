#!/usr/bin/env bash
# Target configuration updates: Copyright 2026 Aaron Hance.
source "$(dirname "${BASH_SOURCE[0]}")/target.sh"
echo " "
echo "======================="
echo " "
echo "Generating Checksum Badge..."
echo " "
checksum=$(md5sum "$ISO_FILE" | awk '{print $1}')
wget -q https://img.shields.io/badge/checksum-$checksum-important.svg -O release/checksum.svg 2>/dev/null