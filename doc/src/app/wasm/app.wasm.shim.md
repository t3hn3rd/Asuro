# app.wasm.shim

Bridge record and fault classification types connecting the Asuro process model to the WASURO VM.

## Overview

`app.wasm.shim` defines the `TProcessWASMShim` record, which is the central link between an Asuro `TProcessContext` and a WASURO `PWASMProcessContext`. The shim is allocated by `app.wasm.runner` when a WASM binary is launched, stored in the process's `Local` field, and passed as the `handle` argument to `app.wasm.cleanup.wasm_resource_cleanup` when the process exits.

## Dependencies

- `proc.types`
- `wasm.types.context`

## Types

### TWASMFaultKind

```pascal
TWASMFaultKind = (
    wfNone,           { No fault — normal completion }
    wfInvalidBinary,  { Parse or validation failure }
    wfNoStartExport,  { _start not found in exports }
    wfUnexpectedHalt, { Running=false with no ExitCode, IP < Limit }
    wfCodeOverrun,    { IP ran past code limit }
    wfUnknown         { Catch-all }
);
```

Classification of the reason a WASM process stopped execution, recorded in the shim after `wasm_entry` returns.

### TProcessWASMShim / PProcessWASMShim

```pascal
TProcessWASMShim = record
    ProcessCtx : PProcessContext;
    WASMCtx    : PWASMProcessContext;
    FileBuffer : puint8;
    FileSize   : uint32;
    FaultKind  : TWASMFaultKind;
    FaultIP    : uint32;
    ArgCount   : uint32;
    ArgBuf     : pchar;
    ArgBufSize : uint32;
end;
```

| Field | Description |
|---|---|
| `ProcessCtx` | The owning Asuro process context |
| `WASMCtx` | The WASURO VM execution context |
| `FileBuffer` | Heap-allocated buffer holding the raw `.wasm` file bytes |
| `FileSize` | Number of bytes read into `FileBuffer` |
| `FaultKind` | Fault classification set after execution ends |
| `FaultIP` | Instruction pointer value at the time of fault |
| `ArgCount` | Number of command-line arguments |
| `ArgBuf` | Flat buffer of null-terminated argument strings |
| `ArgBufSize` | Total byte size of `ArgBuf` |

## Notes

This unit contains no implementation code; it is a pure type definition unit. The shim is intentionally kept separate from the runner and IO units to avoid circular unit dependencies.
