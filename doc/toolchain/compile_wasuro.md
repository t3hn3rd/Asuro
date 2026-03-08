# compile_wasuro.sh

Pulls the Wasuro WASM runtime Pascal sources into the build tree.

## Overview

`compile_wasuro.sh` fetches the Wasuro WebAssembly runtime from its Git repository using a sparse checkout (only the `src/wasm` subtree) and copies the Pascal source files into the local `wasuro/` directory. This makes the Wasuro units available to the FPC compiler via `-Fu` include paths during `compile_sources.sh`.

## Prerequisites

- `git` must be available and able to reach `https://gitea.spexeah.com/Spexeah/Wasuro.git`.
- The `find` and `cp` utilities must be available.

## Inputs

| Source | Description |
|--------|-------------|
| Wasuro Git repository | Cloned (sparse, depth 1) from the `develop` branch. |

## Outputs

| File | Description |
|------|-------------|
| `wasuro/*.pas` | Pascal source files for the WASM runtime, ready for inclusion in the FPC build. |

## Behavior

1. **Cache check**: If `.pas` files already exist in `wasuro/`, the script prints a message and exits immediately, skipping the network fetch.
2. **Sparse clone**: Clones the Wasuro repository into `/tmp/wasuro` with `--depth 1`, `--filter=blob:none`, and `--sparse`, then sets the sparse-checkout to `src/wasm`.
3. **Copy**: Copies the contents of the cloned `src/wasm/` directory into `wasuro/`.
4. **Cleanup**: Removes the temporary clone from `/tmp`.
5. Reports the number of Pascal files copied.

## Notes

- The sparse checkout minimizes download size by fetching only the `src/wasm` subtree.
- Once `wasuro/` is populated, subsequent builds reuse the cached files without re-cloning. To force a fresh pull, delete the `wasuro/` directory.
- The script uses `set -e`, so any failure (network error, git error) aborts the build.
