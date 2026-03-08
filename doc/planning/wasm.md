# WASM Integration — Architecture Plan

## Overview
Integrate the WASURO WebAssembly VM as a **first-class citizen** in Asuro's preemptive process model. WASM binaries are loaded from the filesystem, identified by magic header, and executed as preemptive processes. All I/O is routed through WASI hooks bridged to the process's StdIO buffers. VM faults are surfaced as structured errors with process-level exit code propagation.

### Key Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Execution model | **Budgeted ticks + voluntary yield** (1024 opcodes per iteration) | Finer control over CPU time; sub-quantum fairness between WASM processes; explicit `proc_yield` after each batch |
| Program loading | **Extensible file type dispatcher** (magic-first, extension-fallback) | Typing any filename in the terminal routes to the correct handler; WASM is one handler among future others (images, flat binaries, etc.) |
| WASI ↔ StdIO bridge | **Shim layer with explicit context** | Wrapper record holds both `PProcessContext` + `PWASMProcessContext`; hooks look up IO buffers from the shim, no reliance on `CurrentProcess` global |
| VM fault handling | **Structured fault enum + diagnostic info** + exit code bubbling | `TWASMFaultKind` enum + `LastFaultIP` on the Asuro side; fault propagates to `PProcessContext.ExitCode` |
| Tick budget | **1024 opcodes** per yield | ~1ms of VM work per iteration at ~1 MIPS; responsive scheduling |
| File dispatch strategy | **Magic-first**, extension-fallback | Robust — file with wrong extension still works; first 8 bytes read, checked against registered magic headers |
| Handler API | **Handler receives file path + IO buffers** | Handler reads file itself via VFS; flexible for streaming/partial-read patterns |
| WASM cleanup | **Asuro-side cleanup function** (cannot modify `wasuro/`) | Walks `PWASMProcessContext` fields and kfrees all allocations; registered as resource binding for kill-safety |
| Code location | **`src/prog/wasm/`** subdirectory | Dedicated directory for WASM process integration: runner, IO bridge, cleanup |
| Dispatch registry | **Central `src/filedispatch.pas`** unit | Registration API for magic → handler mappings; vterminal calls `dispatch()` when command lookup fails |

## Architecture Diagram

```
Terminal input: "hello.wasm --arg1 foo"
        │
        ▼
┌──────────────────┐                     ┌────────────────────┐
│   vterminal      │──command lookup──▶   │ stdio.findCommand  │
│  processCommand  │                     │  → not found       │
│                  │◀────────────────────│                    │
│                  │                     └────────────────────┘
│                  │
│                  │──file dispatch──▶   ┌──────────────────────┐
│                  │                     │  filedispatch.dispatch│
│                  │                     │  1. resolve path      │
│                  │                     │  2. read first 8 bytes│
│                  │                     │  3. check magic table │
│                  │                     │     $6D736100 → WASM  │
│                  │                     │  4. call handler      │
│                  │                     └──────────┬───────────┘
│                  │                                │
│                  │                                ▼
│                  │                     ┌──────────────────────┐
│                  │                     │  wasmrunner.handler  │
│                  │                     │  1. read full file    │
│                  │                     │  2. wasm_load()       │
│                  │                     │  3. validate          │
│                  │                     │  4. create shim       │
│                  │                     │  5. serialize params  │
│                  │                     │  6. wire WASI hooks   │
│                  │                     │  7. create process    │
│                  │◀────────────────────│  8. return PID        │
│  ForegroundPID   │                     └──────────────────────┘
└──────────────────┘

                        Process executes via scheduler:
                     ┌──────────────────────────────────┐
                     │  wasm_entry(ctx : PProcessContext)│
                     │                                  │
                     │  shim := PProcessWASMShim(Local) │
                     │  wctx := shim^.WASMCtx           │
                     │                                  │
                     │  wasm_prepare_start(wctx)        │
                     │  while wctx^.ExecutionState       │
                     │        .Running do begin          │
                     │    for i := 1 to 1024 do          │
                     │      if not wasm_tick(wctx) then  │
                     │        break;                    │
                     │    check PendingMsg               │
                     │    proc_yield;                    │
                     │  end;                            │
                     │                                  │
                     │  propagate exit code              │
                     │  { return → trampoline →          │
                     │    psFinished → reap }            │
                     └──────────────────────────────────┘
```

## Data Structures

### File Dispatch Registry (`src/filedispatch.pas`)

```pascal
const
    MAX_MAGIC_LEN = 8;     { Maximum magic header length }
    MAX_HANDLERS  = 16;    { Maximum registered file handlers }

type
    { File handler callback — receives resolved path, params, and IO buffers.
      Returns true if the handler accepted the file and launched a process. }
    TFileHandler = function(path : pchar;
                            params : PParamList;
                            stdin_buf, stdout_buf, stderr_buf : POutBuf) : boolean;

    { A registered file type handler }
    TFileHandlerEntry = record
        Magic       : array[0..MAX_MAGIC_LEN-1] of uint8;  { Magic bytes to match }
        MagicLen    : uint8;                                 { Length of magic sequence }
        Name        : array[0..15] of char;                  { Human-readable name, e.g. 'WASM' }
        Handler     : TFileHandler;                          { Handler function }
    end;
    PFileHandlerEntry = ^TFileHandlerEntry;
```

**API:**
```pascal
procedure init;
procedure registerHandler(magic : puint8; magicLen : uint8; name : pchar; handler : TFileHandler);
function  dispatch(path : pchar; params : PParamList;
                   stdin_buf, stdout_buf, stderr_buf : POutBuf) : boolean;
```

**Flow:**
1. `dispatch()` resolves the path against the terminal's CWD.
2. Opens the file via VFS, reads first `MAX_MAGIC_LEN` bytes.
3. Iterates registered handlers, comparing magic bytes.
4. If a magic match is found, calls `handler(path, params, ...)`.
5. If no magic match, falls back to file extension lookup (future).
6. If no match at all, returns false — vterminal reports "unknown command or file".

### WASM Process Shim (`src/prog/wasm/wasmshim.pas`)

```pascal
type
    { Bridges the Asuro process model to the WASURO VM context }
    PProcessWASMShim = ^TProcessWASMShim;
    TProcessWASMShim = record
        ProcessCtx  : PProcessContext;         { The owning Asuro process }
        WASMCtx     : PWASMProcessContext;     { The WASURO VM context }
        FileBuffer  : puint8;                  { kalloc'd buffer holding the .wasm file }
        FileSize    : uint32;                  { Size of the loaded file }
        ArgCount    : uint32;                  { Number of command-line arguments }
        ArgBuf      : pchar;                   { Flat buffer of null-terminated arg strings }
        ArgBufSize  : uint32;                  { Total byte size of ArgBuf }
    end;
```

The shim is allocated by the WASM handler and stored in `PProcessContext.Local`. All WASI hook implementations read from this shim to find the appropriate IO buffers and command-line arguments.

### WASM Fault Info (Asuro-side, in `wasmshim.pas`)

```pascal
type
    TWASMFaultKind = (
        wfNone,                  { No fault }
        wfInvalidBinary,         { Parse/validation failure }
        wfNoStartExport,         { _start not found in exports }
        wfStackOverflow,         { Operand or control stack overflow }
        wfStackUnderflow,        { Operand or control stack underflow }
        wfOutOfBoundsMemory,     { Linear memory access out of bounds }
        wfUnreachable,           { unreachable opcode executed }
        wfDivisionByZero,        { Integer division by zero }
        wfInvalidFunctionIndex,  { Call to non-existent function }
        wfUnimplementedOpcode,   { Opcode not yet implemented }
        wfImportNotResolved,     { Unresolved import at call time }
        wfUnknown                { Catch-all for unexpected failures }
    );
```

**Note:** These are detected on the Asuro side by inspecting `PWASMProcessContext` state after tick returns false (checking `Running`, `ExitCode`, stack states, etc.). The wasuro VM itself is not modified.

## WASI ↔ StdIO Bridge (`src/prog/wasm/wasmio.pas`)

The bridge provides WASI hook implementations that route to Asuro's `POutBuf` system.

### Design

A **module-level variable** `ActiveShim : PProcessWASMShim` is set before each tick batch and cleared after. The WASI hooks read from this variable. This is safe because:
- WASM execution is single-threaded per process
- Hooks only fire synchronously during `wasm_tick()`
- Preemption saves/restores the full register state but does not re-enter the hook mid-execution

```pascal
var
    ActiveShim : PProcessWASMShim;

{ Set before tick batch, cleared after }
procedure setActiveShim(shim : PProcessWASMShim);
procedure clearActiveShim;

{ WASI hook implementations — registered via wasm_set_fd_write etc. }
function asuro_fd_write(fd: uint32; buf: puint8; len: uint32): uint32;
function asuro_fd_read(fd: uint32; buf: puint8; len: uint32): uint32;
function asuro_proc_exit(code: uint32);
function asuro_clock_time_get(clock_id: uint32; precision: uint64; var time: uint64): uint32;
function asuro_random_get(buf: puint8; len: uint32): uint32;
function asuro_args_sizes_get(var count: uint32; var buf_size: uint32): uint32;
function asuro_args_get(argv: puint32; argv_buf: puint8): uint32;

{ Direct TWASMHostFunc override for args_get — registered as a custom
  host function because the wasuro preview1 glue for args_get is a
  stub that does not call the hook. Registered BEFORE
  wasm_register_wasi_preview1 to take priority in first-match lookup. }
procedure asuro_wasi_args_get(Context : PWASMProcessContext);
```

### args passthrough

Command-line parameters received by the file handler as a `PParamList` (from `stdio`) are
serialized into a flat buffer of packed null-terminated strings stored in the shim:

```
serializeParams(shim, params)
  → shim^.ArgCount  = number of params
  → shim^.ArgBuf    = "param1\0param2\0param3\0"
  → shim^.ArgBufSize = total bytes including null terminators
```

- `asuro_args_sizes_get` (WASI hook): returns `ArgCount` / `ArgBufSize` from the active shim.
- `asuro_wasi_args_get` (direct host function): pops `argv_ptr` / `argv_buf_ptr` from the
  WASM operand stack, walks the flat `ArgBuf`, writes strings into WASM linear memory at
  `argv_buf_ptr`, and records each string's WASM offset into the `argv` array.

This approach is necessary because the wasuro `_WASI_args_get` glue procedure is a stub that
does not invoke the `OnArgsGet` hook. Our custom host function is registered in the host
function registry **before** the bulk WASI preview1 registration, so it is found first by
`find_in_registry`'s linear scan.

### fd_write Implementation
```
1. Check fd: 1 = stdout, 2 = stderr, else return WASI_EBADF
2. Get POutBuf from ActiveShim^.ProcessCtx^.StdOut (or StdErr)
3. Copy buf[0..len-1] into the POutBuf via bufWriteRaw or equivalent
4. Return len (bytes written)
```

### fd_read Implementation
```
1. Check fd: 0 = stdin, else return WASI_EBADF
2. Get POutBuf from ActiveShim^.ProcessCtx^.StdIn
3. If no data available, return 0 (non-blocking) or proc_await (blocking)
4. Copy available data into buf, return bytes read
```

### proc_exit Implementation
```
1. Store code in WASMCtx^.ExitCode
2. Set WASMCtx^.ExecutionState.Running := false
   (Actually, cannot modify wasuro/ — so we handle this via the tick loop:
    the proc_exit WASI hook in wasuro already handles this internally)
3. Set ProcessCtx^.ExitCode := code
```

## WASM Process Entry Point (`src/prog/wasm/wasmrunner.pas`)

```pascal
procedure wasm_entry(ctx : PProcessContext);
var
    shim : PProcessWASMShim;
    wctx : PWASMProcessContext;
    i    : uint32;
begin
    shim := PProcessWASMShim(ctx^.Local);
    wctx := shim^.WASMCtx;

    { Prepare for execution }
    if not wasm_prepare_start(wctx) then begin
        bufWriteStrLn(ctx^.StdErr, 'WASM: _start export not found');
        ctx^.ExitCode := 1;
        exit;
    end;

    { Budgeted execution loop }
    while wctx^.ExecutionState.Running do begin

        { Check for termination request }
        if ctx^.PendingMsg = smTerminate then begin
            bufWriteStrLn(ctx^.StdErr, 'WASM: terminated by signal');
            ctx^.ExitCode := 130;  { Convention: 128 + signal }
            exit;
        end;

        { Execute 1024 opcodes }
        wasmio.setActiveShim(shim);
        for i := 1 to 1024 do begin
            if not wasm_tick(wctx) then
                break;
        end;
        wasmio.clearActiveShim;

        { Yield to scheduler }
        proc_yield;
    end;

    { Propagate exit code }
    ctx^.ExitCode := wctx^.ExitCode;

    { Detect and report faults }
    if (not wctx^.ExecutionState.Running) and (wctx^.ExitCode = 0) then begin
        { Normal completion — check for abnormal state }
        if wctx^.ExecutionState.IP >= wctx^.ExecutionState.Limit then begin
            { Ran off the end of code — could be normal or fault }
        end;
    end;

    { Cleanup: shim + WASM context freed via resource binding on reap }
end;
```

### File Handler (called by filedispatch)

```pascal
function wasm_file_handler(path : pchar;
                           params : PParamList;
                           stdin_buf, stdout_buf, stderr_buf : POutBuf) : boolean;
var
    shim     : PProcessWASMShim;
    wctx     : PWASMProcessContext;
    buf      : puint8;
    bufsize  : uint32;
    proc     : PProcessContext;
begin
    wasm_file_handler := false;

    { 1. Read the file from VFS }
    bufsize := vfs.GetFileSize(path);
    if bufsize = 0 then begin
        bufWriteStrLn(stderr_buf, 'WASM: cannot read file or file empty');
        exit;
    end;
    buf := puint8(kalloc(bufsize));
    if vfs.ReadFileByPath(path, buf, bufsize) <> bufsize then begin
        kfree(void(buf));
        bufWriteStrLn(stderr_buf, 'WASM: file read failed');
        exit;
    end;

    { 2. Parse the WASM binary }
    wctx := wasm_load(buf, puint8(uint32(buf) + bufsize));
    if (wctx = nil) or (not wctx^.ValidBinary) then begin
        kfree(void(buf));
        bufWriteStrLn(stderr_buf, 'WASM: invalid binary');
        exit;
    end;

    { 3. Create the shim }
    shim := PProcessWASMShim(kalloc(SizeOf(TProcessWASMShim)));
    shim^.WASMCtx := wctx;
    shim^.FileBuffer := buf;
    shim^.FileSize := bufsize;

    { 4. Wire up WASI hooks }
    wasm_set_fd_write(wctx, @wasmio.asuro_fd_write);
    wasm_set_fd_read(wctx, @wasmio.asuro_fd_read);
    wasm_set_proc_exit(wctx, @wasmio.asuro_proc_exit);
    wasm_set_clock_time_get(wctx, @wasmio.asuro_clock_time_get);
    wasm_set_random_get(wctx, @wasmio.asuro_random_get);
    wasm_set_args_sizes_get(wctx, @wasmio.asuro_args_sizes_get);
    wasm_set_args_get(wctx, @wasmio.asuro_args_get);
    wasm_register_wasi_preview1(wctx);

    { 5. Create the process }
    proc := processmanager.create('WASM', @wasm_entry, void(shim), 5);

    { 6. Set process StdIO to the terminal's buffers }
    proc^.StdIn := stdin_buf;
    proc^.StdOut := stdout_buf;
    proc^.StdErr := stderr_buf;

    { 7. Complete the shim — process context is now known }
    shim^.ProcessCtx := proc;

    { 8. Register cleanup for kill-safety }
    processmanager.bindResource(proc, rkCustom, void(shim), @wasm_cleanup);

    wasm_file_handler := true;
end;
```

## WASM Context Cleanup (`src/prog/wasm/wasmcleanup.pas`)

Since we cannot modify `wasuro/`, the cleanup function lives on the Asuro side and manually frees all `PWASMProcessContext` allocations by walking the known struct layout.

```pascal
procedure wasm_cleanup(handle : void);
var
    shim : PProcessWASMShim;
    wctx : PWASMProcessContext;
    i    : uint32;
begin
    shim := PProcessWASMShim(handle);
    wctx := shim^.WASMCtx;

    if wctx <> nil then begin
        { Free execution state allocations }
        if wctx^.ExecutionState.Memory <> nil then
            { Free the WASM heap — wasm.types.heap stores a buffer pointer }
            wasm_heap_free(wctx^.ExecutionState.Memory);

        if wctx^.ExecutionState.Control_Stack <> nil then
            wasm_stack_free(wctx^.ExecutionState.Control_Stack);

        if wctx^.ExecutionState.Operand_Stack <> nil then
            wasm_stack_free(wctx^.ExecutionState.Operand_Stack);

        if wctx^.ExecutionState.Locals <> nil then
            kfree(void(wctx^.ExecutionState.Locals));

        if wctx^.ExecutionState.Globals <> nil then begin
            if wctx^.ExecutionState.Globals^.Globals <> nil then
                kfree(void(wctx^.ExecutionState.Globals^.Globals));
            kfree(void(wctx^.ExecutionState.Globals));
        end;

        if wctx^.ExecutionState.Tables <> nil then begin
            { Free individual table entries }
            for i := 0 to wctx^.ExecutionState.Tables^.TableCount - 1 do begin
                if wctx^.ExecutionState.Tables^.Tables[i].Elements <> nil then
                    kfree(void(wctx^.ExecutionState.Tables^.Tables[i].Elements));
            end;
            if wctx^.ExecutionState.Tables^.Tables <> nil then
                kfree(void(wctx^.ExecutionState.Tables^.Tables));
            kfree(void(wctx^.ExecutionState.Tables));
        end;

        { Free sections }
        if wctx^.Sections.TypeSection <> nil then
            kfree(void(wctx^.Sections.TypeSection));
        if wctx^.Sections.ImportSection <> nil then
            kfree(void(wctx^.Sections.ImportSection));
        if wctx^.Sections.FunctionSection <> nil then
            kfree(void(wctx^.Sections.FunctionSection));
        if wctx^.Sections.ExportSection <> nil then
            kfree(void(wctx^.Sections.ExportSection));
        if wctx^.Sections.CodeSection <> nil then
            kfree(void(wctx^.Sections.CodeSection));
        if wctx^.Sections.MemorySection <> nil then
            kfree(void(wctx^.Sections.MemorySection));

        { Free resolved imports }
        if wctx^.ResolvedImports.Imports <> nil then
            kfree(void(wctx^.ResolvedImports.Imports));

        { Free host function registry }
        if wctx^.HostFuncRegistry.Entries <> nil then
            kfree(void(wctx^.HostFuncRegistry.Entries));

        { Free the context itself }
        kfree(void(wctx));
    end;

    { Free the file buffer }
    if shim^.FileBuffer <> nil then
        kfree(void(shim^.FileBuffer));

    { Free the shim }
    kfree(void(shim));
end;
```

**Important:** This cleanup must be kept in sync with `wasuro/`'s allocations. If upstream changes the context layout, this must be updated. We should **suggest upstream add `wasm_destroy()`** as an enhancement to make this unnecessary.

**Upstream suggestion:** Add `procedure wasm_destroy(ctx : PWASMProcessContext);` to `wasuro/wasm.pas` that recursively frees all allocations. This would replace our Asuro-side cleanup and be the "correct" API boundary.

## VTerminal Integration

### Modified Command Dispatch Flow

In `vterminal.processCommand`:

```
1. Parse command line → command name + params
2. Try stdio.findCommand(name)
3. If found → runCommand (existing flow, unchanged)
4. If NOT found → filedispatch.dispatch(name, params, stdin, stdout, stderr)
5. If dispatch returns true → ForegroundPID set by handler, terminal enters busy state
6. If dispatch returns false → "Unknown command or file: <name>"
```

This means typing `hello.wasm` at the terminal prompt will:
1. Fail command lookup (no registered command "hello.wasm")
2. Resolve to a file path (CWD + "hello.wasm")
3. filedispatch reads first 4 bytes → `$00 $61 $73 $6D` → WASM magic
4. Calls `wasmrunner.handler(path, params, ...)`
5. Handler loads, parses, creates process
6. Terminal shows output as the WASM program writes to stdout

## Exit Code Propagation

| Source | Process ExitCode | Description |
|---|---|---|
| WASM `proc_exit(N)` | N | Guest called `proc_exit` via WASI |
| Normal completion | `wctx^.ExitCode` (usually 0) | `_start` returned normally |
| `smTerminate` signal | 130 | Terminated by user (CTRL+C or TERMINATE command) |
| `smKill` signal | N/A (forced reap) | Process killed — no exit code, just reaped |
| Invalid binary | 1 | Parse or validation failure |
| `_start` not found | 1 | No entry point in the WASM module |
| VM fault (future) | 2 | Trapped (unreachable, div/0, OOB, etc.) |

## Implementation Phases

### Phase 6A: File Type Dispatcher
- [x] Create `src/filedispatch.pas` with handler registration + dispatch API
- [x] Static array of `TFileHandlerEntry` (max 16 handlers)
- [x] `dispatch()` reads first 8 bytes via VFS, matches magic, calls handler
- [x] Extension fallback path (stub for now)
- [x] Register `filedispatch.init()` in `progmanager.pas`
- [x] Integrate into `vterminal.processCommand` as fallback after command lookup fails
- [ ] Build + boot-test: no regressions, unrecognized files report "unknown command or file"

### Phase 6B: WASM Process Shim + IO Bridge
- [x] Create `src/prog/wasm/wasmshim.pas` — `TProcessWASMShim`, `TWASMFaultKind`
- [x] Create `src/prog/wasm/wasmio.pas` — WASI hook implementations bridging to POutBuf
- [x] `ActiveShim` pattern: set before tick batch, clear after
- [x] `asuro_fd_write`: fd 1→stdout, fd 2→stderr, else EBADF
- [x] `asuro_fd_read`: fd 0→stdin (non-blocking initially), else EBADF
- [x] `asuro_proc_exit`: set ExitCode, propagate to ProcessCtx
- [x] `asuro_clock_time_get`: use bios_data_area tick or RTC
- [x] `asuro_random_get`: use rand module
- [x] `asuro_args_sizes_get` / `asuro_args_get`: pass command-line params
- [x] Build + verify compilation

### Phase 6C: WASM Process Runner
- [x] Create `src/prog/wasm/wasmrunner.pas` — entry point + file handler
- [x] `wasm_entry()` — budgeted execution loop (1024 ticks), PendingMsg check, proc_yield
- [x] `wasm_file_handler()` — reads file, calls wasm_load, creates shim, wires hooks, creates process
- [x] Register WASM magic (`$00 $61 $73 $6D`) with filedispatch
- [x] Register in `progmanager.pas`
- [x] Build + verify compilation

### Phase 6D: WASM Context Cleanup
- [x] Create `src/prog/wasm/wasmcleanup.pas` — `wasm_cleanup()` procedure
- [x] Walk `PWASMProcessContext` fields, kfree all allocations
- [x] Registered via `processmanager.bindResource(proc, rkCustom, shim, @wasm_cleanup)`
- [ ] Test: create WASM process, kill it, verify no memory leaks via MEMINFO
- [x] Build + boot-test

### Phase 6E: Integration Testing
- [ ] Prepare a minimal WASM binary (hello world via fd_write) on the FAT32 image
- [ ] Boot, type filename at terminal, verify output appears
- [ ] Test CTRL+C → verify smTerminate → clean shutdown
- [ ] Test KILL → verify resource binding cleanup
- [ ] Test invalid WASM binary → verify error message
- [ ] Test non-existent file → verify error message
- [ ] Test multiple WASM processes simultaneously (background with `&`)
- [ ] Verify no memory leaks after process completion

### Phase 6F: Fault Diagnostics (stretch)
- [ ] Inspect `PWASMProcessContext` state after `wasm_tick` returns false to classify fault
- [ ] Report fault kind + IP to stderr
- [ ] Set process ExitCode = 2 for VM faults
- [ ] Consider: should we detect infinite loops (no progress after N ticks)?

## Files Created/Modified

| File | Changes |
|---|---|
| `src/filedispatch.pas` | **New** — file type dispatcher registry + dispatch API (returns PID) |
| `src/prog/wasm/wasmshim.pas` | **New** — `TProcessWASMShim`, `TWASMFaultKind` types |
| `src/prog/wasm/wasmio.pas` | **New** — WASI hook implementations bridging to POutBuf |
| `src/prog/wasm/wasmrunner.pas` | **New** — WASM process entry point + file handler |
| `src/prog/wasm/wasmcleanup.pas` | **New** — WASM context cleanup (Asuro-side teardown) |
| `src/driver/storage/ramdrive.pas` | **New** — RAM-backed VFS drive at `/disk/ram` |
| `src/driver/storage/vfs.pas` | **Modified** — implemented file handle table + OpenFile/ReadFile/WriteFile/CloseFile/FileSize routing to drive callbacks |
| `src/prog/vterminal.pas` | **Modified** — add filedispatch fallback in `processCommand` (fg + bg) |
| `src/progmanager.pas` | **Modified** — add `ramdrive.init`, `filedispatch.init`, `wasmrunner.init` |

## Risk Considerations

| Risk | Mitigation |
|---|---|
| WASM infinite loop | Budgeted ticks + preemptive scheduling means the loop doesn't block the system; user can CTRL+C or KILL |
| Cleanup out of sync with wasuro/ | Document dependency; suggest `wasm_destroy()` upstream |
| VFS file read failures | Defensive checks at every step; errors written to stderr before bailing |
| WASI hook re-entrancy | `ActiveShim` is set/cleared per tick batch; hooks only fire synchronously within `wasm_tick` |
| Large WASM binaries | File buffer is `kalloc`'d — limited by available kernel heap. Future: streaming parser |
| Stack overflow in WASM VM | VM uses its own operand/control stacks (heap-allocated), not the 8KB process stack |
| Multiple WASM processes | Each has its own `PProcessWASMShim` + `PWASMProcessContext`; no shared state |
| FAT32 8.3 filename limits | WASM files will have `.WAS` or similar 3-char extension; magic-based dispatch means extension doesn't matter |
