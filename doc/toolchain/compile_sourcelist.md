# compile_sourcelist.sh

Generates a list of all Pascal source files in the project.

## Overview

`compile_sourcelist.sh` scans the parent directory for all `.pas` files and writes their paths to `sources.list`. This file can be used by other tools or scripts that need a manifest of Pascal source files.

## Prerequisites

- `find` must be available.
- Must be run from a subdirectory of the project root (it searches `..`).

## Inputs

The entire project directory tree (searched recursively for `*.pas` files).

## Outputs

| File | Description |
|------|-------------|
| `sources.list` | A newline-delimited list of absolute paths to all `.pas` files found. |

## Behavior

1. Uses `find` to locate all files matching `*.pas` in the parent directory.
2. Writes the results to `sources.list` in the current working directory.
3. Exits with code 0.

## Notes

- This script is not currently listed in the `compile.sh` build pipeline steps. It may be used as a standalone utility or by external tooling.
