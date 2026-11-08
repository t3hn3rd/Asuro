{
    Prog->WASM->WASMRunner - WASM process entry point & file handler.

    app.wasm.runner registers a file-type handler for WASM binaries with
    filedispatch.  When a .wasm file is executed from the terminal,
    the handler reads the file via VFS, parses it, wires WASI hooks,
    and creates a preemptive process whose entry point drives the VM
    with budgeted ticks.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit app.wasm.runner;

interface

uses
    io.stdio, debug.tracer;

procedure init;
procedure UnitTest;

implementation

uses
    driver.storage.vfs, driver.storage.types, memory.heap, core.strings, io.syslog, core.util, arch.platform.cpu,
    proc.mgr, proc.types, driver.storage.filedispatch,
    app.wasm, app.wasm.shim, app.wasm.io, app.wasm.cleanup,
    arch.platform.memory, wasm.types.stack, wasm.types.values,
    wasm, wasm.types.builtin, wasm.types.context, wasm.types.constants;

const
    WASM_TICK_BUDGET = 1024;  { opcodes per yield iteration }
    WASI_MODULE      = 'wasi_snapshot_preview1';

function memoryAvailable: boolean;
begin
    { Wasuro allocates two fixed-capacity stacks before parsing. Include heap
      region rounding and working space; reject low-memory launches up front. }
    memoryAvailable := arch.platform.memory.freePhysicalBytes >
        uint64(2) * DEFAULT_STACK_SIZE * sizeof(TWASMStackEntry) +
        uint64(4) * PAGE_SIZE_LMM;
end;

{ ---- Param serialization ---- }

{ Serialize a PParamList into a flat null-terminated buffer stored
  in the shim.  Each param becomes a null-terminated string packed
  consecutively.  Sets shim^.ArgCount, ArgBuf, ArgBufSize. }
function serializeParams(shim : PProcessWASMShim; params : PParamList): boolean;
var
    p       : PParamList;
    total   : uint32;
    count   : uint32;
    slen    : uint32;
    dest    : uint32;
begin
    serializeParams := false;
    { First pass: count params and total buffer size }
    count := 0;
    total := 0;
    p := params;
    while p <> nil do begin
        if p^.Param <> nil then begin
            slen := core.strings.stringSize(p^.Param);
            if (slen = High(uint32)) or (total > High(uint32) - slen - 1) then
                exit;
            total := total + slen + 1; { string + null terminator }
            inc(count);
        end;
        p := p^.Next;
    end;

    shim^.ArgCount := count;
    shim^.ArgBufSize := total;

    if (count = 0) or (total = 0) then begin
        shim^.ArgBuf := nil;
        serializeParams := true;
        exit;
    end;

    { Allocate and fill }
    shim^.ArgBuf := pchar(kalloc(total));
    if shim^.ArgBuf = nil then exit;
    dest := 0;
    p := params;
    while p <> nil do begin
        if p^.Param <> nil then begin
            slen := core.strings.stringSize(p^.Param);
            memcpy(PtrUInt(p^.Param), PtrUInt(shim^.ArgBuf) + dest, slen);
            dest := dest + slen;
            shim^.ArgBuf[dest] := #0; { null terminator }
            inc(dest);
        end;
        p := p^.Next;
    end;
    serializeParams := true;
end;

{ ---- Process entry point ---- }

procedure wasm_entry(ctx : PProcessContext);
var
    shim  : PProcessWASMShim;
    wctx  : PWASMProcessContext;
    i     : uint32;
    alive : boolean;
begin
    shim := PProcessWASMShim(ctx^.Local);
    wctx := shim^.WASMCtx;

    { Prepare the _start call frame }
    if not wasm_prepare_start(wctx) then begin
        io.stdio.bufWriteStrLn(ctx^.StdErr, 'WASM: _start export not found');
        shim^.FaultKind := wfNoStartExport;
        ctx^.ExitCode := 1;
        exit;
    end;

    { Budgeted execution loop }
    while wctx^.ExecutionState.Running do begin

        { Check for termination request }
        if ctx^.PendingMsg = smTerminate then begin
            io.stdio.bufWriteStrLn(ctx^.StdErr, 'WASM: terminated by signal');
            ctx^.ExitCode := 130;
            exit;
        end;
        if ctx^.PendingMsg = smKill then
            exit;

        { Execute a batch of opcodes }

        for i := 1 to WASM_TICK_BUDGET do begin
            alive := wasm_tick(wctx);
            if not alive then break;
        end;


        { Yield to scheduler after each batch }
        proc.mgr.proc_yield;
    end;

    { Propagate exit code from VM }
    ctx^.ExitCode := wctx^.ExitCode;

    { Classify any fault }
    if wctx^.ExitCode = 0 then begin
        if wctx^.ExecutionState.IP >= wctx^.ExecutionState.Limit then
            shim^.FaultKind := wfNone  { normal end-of-code }
        else
            shim^.FaultKind := wfNone; { normal proc_exit }
    end else begin
        shim^.FaultKind := wfUnexpectedHalt;
        shim^.FaultIP := wctx^.ExecutionState.IP;
    end;
end;

{ ---- File handler (called by driver.storage.filedispatch) ---- }

function wasm_file_handler(path : pchar;
                           params : PParamList;
                           stdin_buf, stdout_buf, stderr_buf : POutBuf) : uint32;
var
    shim     : PProcessWASMShim;
    wctx     : PWASMProcessContext;
    buf      : puint8;
    fh       : TFileHandle;
    err      : TError;
    fsize    : uint32;
    bytesRead : uint32;
    processCtx : PProcessContext;
begin
    debug.tracer.push_trace('wasmrunner.handler');
    wasm_file_handler := 0;

    if not memoryAvailable then begin
        io.stdio.bufWriteStrLn(stderr_buf, 'WASM: insufficient memory for VM stacks');
        exit;
    end;

    { 1. Open file once — omRead pre-loads the data and gives us the size }
    err := eNone;
    fh := driver.storage.vfs.OpenFile(path, omRead, @err);
    if (fh = 0) or (err <> eNone) then begin
        io.stdio.bufWriteStrLn(stderr_buf, 'WASM: cannot open file');
        exit;
    end;

    fsize := driver.storage.vfs.FileSizeFromHandle(fh);
    if fsize = 0 then begin
        driver.storage.vfs.CloseFile(fh);
        io.stdio.bufWriteStrLn(stderr_buf, 'WASM: file is empty or cannot determine size');
        exit;
    end;

    { 2. Allocate buffer and read file }
    buf := puint8(kalloc(fsize));
    if buf = nil then begin
        driver.storage.vfs.CloseFile(fh);
        io.stdio.bufWriteStrLn(stderr_buf, 'WASM: out of memory');
        exit;
    end;

    bytesRead := driver.storage.vfs.ReadFile(fh, 0, buf, fsize);
    driver.storage.vfs.CloseFile(fh);

    if bytesRead <> fsize then begin
        kfree(void(buf));
        io.stdio.bufWriteStrLn(stderr_buf, 'WASM: file read failed');
        exit;
    end;

    { Establish ownership before parsing so every failure uses one cleanup. }
    shim := PProcessWASMShim(kalloc(SizeOf(TProcessWASMShim)));
    if shim = nil then begin
        kfree(void(buf));
        io.stdio.bufWriteStrLn(stderr_buf, 'WASM: out of memory (shim)');
        exit;
    end;
    shim^.FileBuffer := buf;
    shim^.FileSize := bytesRead;
    shim^.FaultKind := wfNone;
    wctx := wasm_load(buf, TWASMPUInt8(PtrUInt(buf) + bytesRead));
    shim^.WASMCtx := wctx;
    if (wctx = nil) or (not wctx^.ValidBinary) then begin
        app.wasm.cleanup.wasm_resource_cleanup(void(shim));
        io.stdio.bufWriteStrLn(stderr_buf, 'WASM: invalid binary');
        exit;
    end;

    { 5. Serialize command-line params into the shim }
    if not serializeParams(shim, params) then begin
        app.wasm.cleanup.wasm_resource_cleanup(void(shim));
        io.stdio.bufWriteStrLn(stderr_buf, 'WASM: cannot allocate arguments');
        exit;
    end;

    { 6. Wire up WASI hooks to our IO bridge }
    wasm_set_fd_write(wctx, @app.wasm.io.asuro_fd_write);
    wasm_set_fd_read(wctx, @app.wasm.io.asuro_fd_read);
    wasm_set_proc_exit(wctx, @app.wasm.io.asuro_proc_exit);
    wasm_set_clock_time_get(wctx, @app.wasm.io.asuro_clock_time_get);
    wasm_set_clock_res_get(wctx, @app.wasm.io.asuro_clock_res_get);
    wasm_set_random_get(wctx, @app.wasm.io.asuro_random_get);
    wasm_set_args_sizes_get(wctx, @app.wasm.io.asuro_args_sizes_get);
    wasm_set_args_get(wctx, @app.wasm.io.asuro_args_get);
    wasm_set_environ_sizes_get(wctx, @app.wasm.io.asuro_environ_sizes_get);
    wasm_set_environ_get(wctx, @app.wasm.io.asuro_environ_get);

    { Register our direct host-function override for args_get BEFORE
      the WASI preview1 bulk registration so it takes priority in
      the first-match registry lookup. }
    wasm_register_host_func(wctx, WASI_MODULE, 'args_get',
                            @app.wasm.io.asuro_wasi_args_get);
    wasm_register_wasi_preview1(wctx);

    { 7. Create the process }
    processCtx := proc.mgr.createSuspended('WASM', @wasm_entry, void(shim), 5);
    if processCtx = nil then begin
        app.wasm.cleanup.wasm_resource_cleanup(void(shim));
        io.stdio.bufWriteStrLn(stderr_buf, 'WASM: failed to create process');
        exit;
    end;

    { 8. Attach StdIO }
    processCtx^.StdIn := stdin_buf;
    processCtx^.StdOut := stdout_buf;
    processCtx^.StdErr := stderr_buf;

    { 9. Complete the shim }
    shim^.ProcessCtx := processCtx;

    { 10. Register cleanup for kill-safety }
    proc.mgr.bindResource(processCtx, rkCustom, void(shim), @app.wasm.cleanup.wasm_resource_cleanup);

    wasm_file_handler := processCtx^.ProcessID;
    processCtx^.State := psReady;
end;

{ ---- Initialisation ---- }

procedure UnitTest;
const
    { (module (import "wasi_snapshot_preview1" "proc_exit" (func (param i32)))
      (func (export "_start") i32.const 42 call 0)) }
    binary: array[0..81] of uint8 = (
        $00,$61,$73,$6D,$01,$00,$00,$00,
        $01,$08,$02,$60,$01,$7F,$00,$60,$00,$00,
        $02,$24,$01,$16,
        $77,$61,$73,$69,$5F,$73,$6E,$61,$70,$73,$68,$6F,$74,$5F,$70,$72,$65,$76,$69,$65,$77,$31,
        $09,$70,$72,$6F,$63,$5F,$65,$78,$69,$74,$00,$00,
        $03,$02,$01,$01,
        $07,$0A,$01,$06,$5F,$73,$74,$61,$72,$74,$00,$01,
        $0A,$08,$01,$06,$00,$41,$2A,$10,$00,$0B);
var
    shim: PProcessWASMShim;
    previousLocal: void;
    previousExit, steps: uint32;
    ok: boolean;
begin
    if not memoryAvailable then begin
        io.syslog.logln('WASM', 'SKIP: insufficient memory for native WASM execution test');
        exit;
    end;
    shim := PProcessWASMShim(kalloc(sizeof(TProcessWASMShim)));
    if shim = nil then exit;
    shim^.FileBuffer := puint8(kalloc(sizeof(binary)));
    if shim^.FileBuffer = nil then begin
        kfree(void(shim));
        exit;
    end;
    memcpy(PtrUInt(@binary[0]), PtrUInt(shim^.FileBuffer), sizeof(binary));
    shim^.WASMCtx := wasm_load(shim^.FileBuffer,
        TWASMPUInt8(PtrUInt(shim^.FileBuffer) + sizeof(binary)));
    ok := shim^.WASMCtx <> nil;
    if ok then ok := shim^.WASMCtx^.ValidBinary;
    if ok then begin
        previousLocal := proc.mgr.CurrentProcess^.Local;
        previousExit := proc.mgr.CurrentProcess^.ExitCode;
        shim^.ProcessCtx := proc.mgr.CurrentProcess;
        proc.mgr.CurrentProcess^.Local := void(shim);
        wasm_set_proc_exit(shim^.WASMCtx, @app.wasm.io.asuro_proc_exit);
        wasm_register_wasi_preview1(shim^.WASMCtx);
        ok := wasm_prepare_start(shim^.WASMCtx);
        steps := 0;
        while ok and shim^.WASMCtx^.ExecutionState.Running and (steps < 16) do begin
            wasm_tick(shim^.WASMCtx);
            inc(steps);
        end;
        ok := ok and (not shim^.WASMCtx^.ExecutionState.Running) and
            (shim^.WASMCtx^.ExitCode = 42) and
            (proc.mgr.CurrentProcess^.ExitCode = 42);
        proc.mgr.CurrentProcess^.Local := previousLocal;
        proc.mgr.CurrentProcess^.ExitCode := previousExit;
    end;
    app.wasm.cleanup.wasm_resource_cleanup(void(shim));
    if ok then
        io.syslog.logln('WASM', 'PASS: native WASM executes WASI proc_exit and releases its context')
    else
        io.syslog.logln('WASM', 'FAIL: native WASM execution');
end;

procedure init;
var
    magic : array[0..3] of uint8;
begin
    debug.tracer.push_trace('wasmrunner.init');
    io.syslog.logln('WASMRUNNER', 'INIT BEGIN.');

    { One-time WASURO VM initialisation }
    app.wasm.init;

    { Register WASM magic ($00 $61 $73 $6D = "\0asm") with file dispatcher }
    magic[0] := $00;
    magic[1] := $61;
    magic[2] := $73;
    magic[3] := $6D;
    driver.storage.filedispatch.registerHandler(@magic[0], 4, 'WASM', @wasm_file_handler);

    io.syslog.logln('WASMRUNNER', 'INIT END.');
end;

end.
