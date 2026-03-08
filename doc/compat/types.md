# types

Empty compatibility shim that satisfies `uses types` references from the Wasuro WASM VM project.

## Overview

Some units in the Wasuro WASM VM source tree include `uses types` to pull in shared type definitions from the Asuro kernel. In the kernel proper, those types may be declared elsewhere or may no longer be needed in the WASM context. This stub unit provides an empty `types` compilation unit so that `uses types` resolves without error during the Wasuro build.

## Dependencies

None.

## Notes

- The unit declares no constants, types, variables, or routines. Its only purpose is to exist as a valid compilation unit.
- If Wasuro code is ever updated to remove the `uses types` dependency, this shim can be deleted.
