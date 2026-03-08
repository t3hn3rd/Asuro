# compile_checksum.sh

Generates MD5 checksums for all Pascal source files.

## Overview

`compile_checksum.sh` iterates over every `.pas` file under `src/` and appends its MD5 hash to `checksums.md5`. This file serves as a source-level fingerprint used by `compile_vergen.sh` to produce a build integrity checksum.

## Prerequisites

- `md5sum` and `find` must be available.
- The `src/` directory must exist and contain `.pas` files.

## Inputs

All `*.pas` files found recursively under `src/`, up to 10 levels deep.

## Outputs

| File | Description |
|------|-------------|
| `checksums.md5` | A file containing one `md5sum`-format line per Pascal source file. |

## Behavior

1. Truncates (or creates) `checksums.md5` with an empty write (`echo >`).
2. Finds all directories under `src/` (up to 10 levels deep).
3. For each directory, iterates over `*.pas` files and computes their MD5 checksum.
4. Skips files matching any of the following conditions:
   - Path contains `.svn` (Subversion metadata).
   - The glob matched no files (literal `*.pas` string).
   - Path contains `include/asuro.pas`.
5. Appends each valid checksum line to `checksums.md5`.

## Notes

- The resulting `checksums.md5` is consumed by `compile_vergen.sh`, which hashes the checksum file itself to produce a single build fingerprint constant embedded in the kernel.
- The `.svn` exclusion is a legacy filter from when the project used Subversion for version control.
