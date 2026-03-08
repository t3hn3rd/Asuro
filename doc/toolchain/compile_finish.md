# compile_finish.sh

Reports build status and generates the build result badge.

## Overview

`compile_finish.sh` is the final step in the Asuro build pipeline. It is sourced (not executed) by `compile.sh` and receives a single argument indicating whether the build succeeded or failed. It downloads the appropriate shields.io badge and exits with the corresponding exit code.

## Prerequisites

- `wget` must be available (though badge download failure is non-fatal).
- The `release/` directory must exist.

## Inputs

| Input | Description |
|-------|-------------|
| `$1` | A string argument: `"failed"` or `"success"`. Passed by `compile.sh`. |

## Outputs

| File | Description |
|------|-------------|
| `release/build.svg` | A shields.io badge: red "build-failed" or green "build-succeeded". |

## Behavior

1. If `$1` is `"failed"`:
   - Prints an error message directing the user to review the log.
   - Downloads a red "build-failed" badge to `release/build.svg`.
   - Exits with code 1.
2. Otherwise:
   - Prints a success message.
   - Downloads a green "build-succeeded" badge to `release/build.svg`.
   - Exits with code 0.

## Notes

- This script is sourced (`. compile_finish.sh`) by `compile.sh`, meaning its `exit` call terminates the parent shell. This is intentional -- it sets the final exit code for the entire build pipeline.
- Badge download is silent and non-blocking; if `wget` fails (e.g., no network), the build still reports the correct exit code.
