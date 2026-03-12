# app.wasm

WebAssembly VM backend initialiser.

## Overview

This unit initialises the Wasuro WebAssembly virtual machine backend. It wires up the VM's character output to the syslog interface and calls the main `wasm_init` entry point.

## Boot Registration

Registered with `boot.mgr` as `app.wasm` at the `final` barrier.

## Dependencies

- `boot.mgr`
- `io.syslog`
- `wasm.vm.io`
- `wasm`

## Procedures

### init

```pascal
procedure init;
```

Sets the WASM VM's write-character callback to `io.syslog.logchar` and calls `wasm.wasm_init` to initialise the VM runtime.
