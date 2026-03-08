# core.types

Dummy compatibility unit providing a named home for the `core.types` identifier.

## Overview

`core.types` is an intentionally empty unit whose sole purpose is to satisfy the Free Pascal unit dependency resolver when a virtual machine build environment requires a unit named `core.types` to be present. It contains no type definitions, constants, or routines. Actual shared type definitions used by Asuro modules are declared in the units that own them, or in `core.ds.types` for data structure types.

## Notes

This unit should not be used as a dependency in new code. It exists purely for VM build-system compatibility and exports no symbols.
