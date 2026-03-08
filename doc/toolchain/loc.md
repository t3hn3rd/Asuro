# loc.sh

Counts the total lines of Pascal source code in the project.

## Overview

`loc.sh` is a utility script that counts the total number of lines across all `.pas` files in the project. It is called by `compile_vergen.sh` to embed a line count into the kernel's version metadata.

## Prerequisites

- `find`, `xargs`, `wc`, and `awk` must be available.

## Inputs

All `*.pas` files found recursively from the current working directory.

## Outputs

Prints a single line to stdout containing the total line count (e.g., `42567`).

## Behavior

1. Uses `find` to locate all `.pas` files starting from the current directory.
2. Pipes the file list to `xargs wc -l` to count lines in each file.
3. Uses `awk` to extract the grand total from the last line of `wc` output.

## Notes

- The output is consumed by `compile_vergen.sh` via command substitution and piped through `awk` to extract just the numeric value.
- This script produces no files; it only writes to stdout.
