# app.wasm.cleanup

Teardown handler for WASURO VM allocations when a WASM process exits or is killed.

## Overview

`app.wasm.cleanup` provides a single public procedure, `wasm_resource_cleanup`, whose signature matches the `TResourceCleanup` callback type used by `proc.mgr.bindResource`. When a WASM process terminates (normally or via kill), the process manager invokes this callback with the shim pointer, which then walks the entire `PWASMProcessContext` and frees every heap allocation made during parsing and VM setup.

Because the WASURO VM library is treated as read-only, teardown is performed entirely on the Asuro side by mirroring the known allocation patterns from the WASM parser and VM initializer.

## Dependencies

- `memory.heap`
- `wasm.types.builtin`, `wasm.types.context`, `wasm.types.sections`
- `wasm.types.heap`, `wasm.types.values`
- `app.wasm.shim`

## Functions and Procedures

### wasm_resource_cleanup

```pascal
procedure wasm_resource_cleanup(handle: void);
```

Top-level cleanup entry point. Casts `handle` to `PProcessWASMShim` and frees all nested WASM structures in order:

1. Execution state: heap memory pages, operand and control stacks, globals, tables, data segments, element segments, flat code buffer.
2. Section data: type section (per-type parameter and return type arrays), import section (module and field name strings), function section, export section (entry name strings), code section (per-entry code buffers and local variable arrays), memory section.
3. Resolved imports array and host function registry entries array.
4. The `PWASMProcessContext` record itself.
5. Shim-owned allocations: `FileBuffer` and `ArgBuf`.
6. The `PProcessWASMShim` record itself.

Each sub-free procedure guards against `nil` pointers before dereferencing.

## Notes

Import section `ModuleName` and `FieldName` pointers in the resolved imports array alias the strings already freed by `freeImportSection`, so they must not be freed a second time. Similarly, `ModuleName` and `FieldName` in the host function registry entries are compile-time string constants and must not be freed. The `ExecutionState.Locals` pointer aliases an entry inside `CodeSection` and has no independent free.
