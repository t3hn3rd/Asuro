# app.wasm.runner

WASM binary file handler and process launcher for the Asuro WASM runtime.

## Overview

`app.wasm.runner` bridges the Asuro file dispatch system and the WASURO WebAssembly interpreter. At initialization it registers the WASM magic bytes (`\0asm`) with `driver.storage.filedispatch` so that any `.wasm` file executed from the terminal is routed to the `wasm_file_handler` function.

When a WASM file is dispatched, the handler reads the file from VFS, parses the binary, wires all WASI preview1 hooks to the Asuro IO bridge, allocates a shim record, serializes command-line arguments, creates a preemptive process, and registers a cleanup callback so that all VM memory is freed when the process exits or is killed.

## Dependencies

- `io.stdio`, `debug.tracer`
- `driver.storage.vfs`, `driver.storage.types`
- `memory.heap`, `core.strings`, `io.syslog`
- `core.util`, `arch.x86.util`
- `proc.mgr`, `proc.types`
- `driver.storage.filedispatch`
- `app.wasm.shim`, `app.wasm.io`, `app.wasm.cleanup`
- `wasm`, `wasm.types.builtin`, `wasm.types.context`, `wasm.types.constants`

## Constants

### WASM_TICK_BUDGET
`1024` — Number of WASM opcodes executed per scheduler yield iteration.

### WASI_MODULE
`'wasi_snapshot_preview1'` — WASI module name used when registering host functions.

## Functions and Procedures

### init

```pascal
procedure init;
```

Calls `wasm_init` to initialize the WASURO VM, then registers `wasm_file_handler` with `driver.storage.filedispatch` for the 4-byte WASM magic signature (`$00 $61 $73 $6D`).

### wasm_file_handler (internal)

```pascal
function wasm_file_handler(path: pchar; params: PParamList;
                            stdin_buf, stdout_buf, stderr_buf: POutBuf): uint32;
```

File dispatch callback. Performs the following steps:

1. Determines file size via `driver.storage.vfs.FileSize`.
2. Allocates a read buffer and reads the file.
3. Parses the WASM binary via `wasm_load`; aborts if the binary is invalid.
4. Allocates and zeroes a `TProcessWASMShim`.
5. Serializes command-line parameters into the shim's `ArgBuf` via `serializeParams`.
6. Wires all WASI hooks (fd_write, fd_read, proc_exit, clock, random, args, environ) to `app.wasm.io` implementations.
7. Registers `asuro_wasi_args_get` as a direct host function before calling `wasm_register_wasi_preview1`.
8. Creates the process via `proc.mgr.create` at priority 5.
9. Attaches stdin, stdout, and stderr buffers to the process context.
10. Binds the shim as a custom resource with `app.wasm.cleanup.wasm_resource_cleanup` for kill-safe teardown.

Returns the new process ID on success, or 0 on any failure.

### wasm_entry (internal)

```pascal
procedure wasm_entry(ctx: PProcessContext);
```

Process entry point for WASM execution. Calls `wasm_prepare_start` to set up the `_start` export frame. Executes `WASM_TICK_BUDGET` opcodes per loop iteration via `wasm_tick`, yielding to the scheduler between batches. Checks for `smTerminate` and `smKill` messages. On completion propagates the VM exit code to the process context.

### serializeParams (internal)

Flattens a `PParamList` into a contiguous null-terminated argument buffer stored in the shim. Sets `ArgCount` and `ArgBufSize` for use by `asuro_args_sizes_get` and `asuro_wasi_args_get`.

## Notes

The file buffer (`shim^.FileBuffer`) is kept alive for the duration of execution because the WASM parser may hold pointers into it. It is freed by `wasm_resource_cleanup` when the process is reaped. If process creation fails after the shim is allocated, the shim and its ArgBuf are freed inline before returning 0.
