# app.wasm.io

WASI hook implementations bridging the WASURO VM to Asuro process I/O buffers.

## Overview

`app.wasm.io` provides concrete implementations of the WASI preview1 system call hooks that the WASURO VM calls when a WASM module performs I/O. File descriptors 0, 1, and 2 are routed to the owning Asuro process's `StdIn`, `StdOut`, and `StdErr` `POutBuf` buffers respectively.

A module-level `ActiveShimPtr` variable is set to the current shim before each tick batch and cleared afterwards. Because all hook calls occur synchronously within `wasm_tick` under the preemptive scheduler, this is safe with no additional locking.

## Dependencies

- `app.wasm.shim`
- `wasm.types.builtin`, `wasm.types.context`, `wasm.types.values`
- `io.stdio`, `proc.types`
- `wasm.types.wasi`, `wasm.types.stack`, `wasm.types.heap`
- `arch.x86.bda`, `core.rand`
- `core.util`, `arch.x86.util`

## Functions and Procedures

### setActiveShim / clearActiveShim

```pascal
procedure setActiveShim(shim: PProcessWASMShim);
procedure clearActiveShim;
```

Must be called immediately before and after each `wasm_tick` batch to establish and remove the active shim context for hook callbacks.

### asuro_fd_write

```pascal
function asuro_fd_write(fd: TWASMUInt32; buf: TWASMPUInt8; len: TWASMUInt32): TWASMUInt32;
```

WASI `fd_write` hook. Routes fd 1 to `StdOut` and fd 2 to `StdErr` by calling `io.stdio.bufWriteChar` for each byte. Returns the number of bytes written, or 0 for unsupported file descriptors.

### asuro_fd_read

```pascal
function asuro_fd_read(fd: TWASMUInt32; buf: TWASMPUInt8; len: TWASMUInt32): TWASMUInt32;
```

WASI `fd_read` hook. Non-blocking read from fd 0 (`StdIn`). Returns whatever bytes are currently available in the stdin buffer, or 0 if empty.

### asuro_proc_exit

```pascal
procedure asuro_proc_exit(code: TWASMUInt32);
```

WASI `proc_exit` hook. Propagates the exit code to the Asuro process context's `ExitCode` field.

### asuro_clock_time_get

```pascal
function asuro_clock_time_get(clock_id: TWASMUInt32; precision: TWASMUInt64; var time: TWASMUInt64): TWASMUInt32;
```

Returns the current time in nanoseconds derived from the BIOS 1024 Hz tick counter (`Counters.c64 * 976562`).

### asuro_clock_res_get

```pascal
function asuro_clock_res_get(clock_id: TWASMUInt32; var resolution: TWASMUInt64): TWASMUInt32;
```

Returns a clock resolution of 976562 nanoseconds (~0.977 ms, i.e. 1/1024 second).

### asuro_random_get

```pascal
function asuro_random_get(buf: TWASMPUInt8; len: TWASMUInt32): TWASMUInt32;
```

Fills the buffer with random bytes from `core.rand.rand32`, packing four bytes per call.

### asuro_args_sizes_get

```pascal
function asuro_args_sizes_get(var count: TWASMUInt32; var buf_size: TWASMUInt32): TWASMUInt32;
```

Returns the argument count and total flat buffer size from the active shim.

### asuro_wasi_args_get

```pascal
procedure asuro_wasi_args_get(Context: PWASMProcessContext);
```

Direct host-function override for the WASI `args_get` call (registered before `wasm_register_wasi_preview1` so it takes priority). Pops `argv_ptr` and `argv_buf_ptr` from the operand stack, writes each null-terminated argument string into WASM linear memory at `argv_buf_ptr + offset`, and writes the corresponding WASM-side pointer into the `argv` array.

### asuro_environ_sizes_get / asuro_environ_get

Return an empty environment (count 0, buffer size 0). No environment variables are exposed to WASM modules.

## Notes

The standard `asuro_args_get` hook function is never called by the WASURO preview1 glue because `asuro_wasi_args_get` is registered as a direct host function replacement and takes priority in the registry lookup.
