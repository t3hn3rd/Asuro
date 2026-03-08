# compile_sumgen.sh

Generates an MD5 checksum badge for the final ISO image.

## Overview

`compile_sumgen.sh` computes the MD5 hash of `Asuro.iso` and downloads a shields.io SVG badge displaying the checksum. This badge is stored in the `release/` directory for use in project documentation and release pages.

## Prerequisites

- `md5sum`, `awk`, and `wget` must be available.
- `Asuro.iso` must exist in the current directory (produced by `compile_isogen.sh`).
- The `release/` directory must exist.

## Inputs

| Source | Description |
|--------|-------------|
| `Asuro.iso` | The final bootable ISO image. |

## Outputs

| File | Description |
|------|-------------|
| `release/checksum.svg` | Shields.io badge displaying the ISO's MD5 checksum. |

## Behavior

1. Computes the MD5 checksum of `Asuro.iso` using `md5sum`.
2. Downloads a shields.io badge SVG with the checksum value and saves it to `release/checksum.svg`.

## Notes

- This script is not currently listed in the `compile.sh` pipeline. It may be invoked separately or have been superseded by badge generation in `compile_vergen.sh`.
- The `wget` call is silenced (`-q`) and its stderr is redirected to `/dev/null`, so download failures are silent.
