{
    Prog->WASM->WASMRunner - WASM process entry point & file handler.

    wasmrunner registers a file-type handler for WASM binaries with
    filedispatch.  When a .wasm file is executed from the terminal,
    the handler reads the file via VFS, parses it, wires WASI hooks,
    and creates a preemptive process whose entry point drives the VM
    with budgeted ticks.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit wasmrunner;

interface

uses
    stdio, tracer;

procedure init;

implementation

uses
    vfs, lmemorymanager, strings, syslog, util,
    processmanager, proctypes, filedispatch,
    wasmshim, wasmio, wasmcleanup,
    wasm, wasm.types.builtin, wasm.types.context, wasm.types.constants;

const
    WASM_TICK_BUDGET = 1024;  { opcodes per yield iteration }
    WASI_MODULE      = 'wasi_snapshot_preview1';

{ ---- Param serialization ---- }

{ Serialize a PParamList into a flat null-terminated buffer stored
  in the shim.  Each param becomes a null-terminated string packed
  consecutively.  Sets shim^.ArgCount, ArgBuf, ArgBufSize. }
procedure serializeParams(shim : PProcessWASMShim; params : PParamList);
var
    p       : PParamList;
    total   : uint32;
    count   : uint32;
    slen    : uint32;
    dest    : uint32;
begin
    { First pass: count params and total buffer size }
    count := 0;
    total := 0;
    p := params;
    while p <> nil do begin
        if p^.Param <> nil then begin
            slen := strings.stringSize(p^.Param);
            total := total + slen + 1; { string + null terminator }
            inc(count);
        end;
        p := p^.Next;
    end;

    shim^.ArgCount := count;
    shim^.ArgBufSize := total;

    if (count = 0) or (total = 0) then begin
        shim^.ArgBuf := nil;
        exit;
    end;

    { Allocate and fill }
    shim^.ArgBuf := pchar(kalloc(total));
    memset(uint32(shim^.ArgBuf), 0, total);
    dest := 0;
    p := params;
    while p <> nil do begin
        if p^.Param <> nil then begin
            slen := strings.stringSize(p^.Param);
            memcpy(uint32(p^.Param), uint32(shim^.ArgBuf) + dest, slen);
            dest := dest + slen;
            shim^.ArgBuf[dest] := #0; { null terminator }
            inc(dest);
        end;
        p := p^.Next;
    end;
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
        stdio.bufWriteStrLn(ctx^.StdErr, 'WASM: _start export not found');
        shim^.FaultKind := wfNoStartExport;
        ctx^.ExitCode := 1;
        exit;
    end;

    { Budgeted execution loop }
    while wctx^.ExecutionState.Running do begin

        { Check for termination request }
        if ctx^.PendingMsg = smTerminate then begin
            stdio.bufWriteStrLn(ctx^.StdErr, 'WASM: terminated by signal');
            ctx^.ExitCode := 130;
            exit;
        end;
        if ctx^.PendingMsg = smKill then
            exit;

        { Execute a batch of opcodes }
        wasmio.setActiveShim(shim);
        for i := 1 to WASM_TICK_BUDGET do begin
            alive := wasm_tick(wctx);
            if not alive then break;
        end;
        wasmio.clearActiveShim;

        { Yield to scheduler after each batch }
        processmanager.proc_yield;
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

{ ---- File handler (called by filedispatch) ---- }

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
    errb     : uint8;
    bytesRead : uint32;
    proc     : PProcessContext;
begin
    tracer.push_trace('wasmrunner.handler');
    wasm_file_handler := 0;

    { 1. Get file size }
    errb := 0;
    fsize := vfs.FileSize(path, @errb);
    if (fsize = 0) or (errb <> 0) then begin
        stdio.bufWriteStrLn(stderr_buf, 'WASM: cannot determine file size');
        exit;
    end;

    { 2. Allocate buffer and read file }
    buf := puint8(kalloc(fsize));
    if buf = nil then begin
        stdio.bufWriteStrLn(stderr_buf, 'WASM: out of memory');
        exit;
    end;

    err := eNone;
    fh := vfs.OpenFile(path, omReadOnly, wmRewrite, false, @err);
    if fh = 0 then begin
        kfree(void(buf));
        stdio.bufWriteStrLn(stderr_buf, 'WASM: cannot open file');
        exit;
    end;

    bytesRead := vfs.ReadFile(fh, 0, buf, fsize);
    vfs.CloseFile(fh);

    if bytesRead = 0 then begin
        kfree(void(buf));
        stdio.bufWriteStrLn(stderr_buf, 'WASM: file read failed');
        exit;
    end;

    { 3. Parse the WASM binary }
    wctx := wasm_load(buf, TWASMPUInt8(uint32(buf) + bytesRead));
    if (wctx = nil) or (not wctx^.ValidBinary) then begin
        kfree(void(buf));
        stdio.bufWriteStrLn(stderr_buf, 'WASM: invalid binary');
        exit;
    end;

    { 4. Create the shim }
    shim := PProcessWASMShim(kalloc(SizeOf(TProcessWASMShim)));
    if shim = nil then begin
        kfree(void(buf));
        stdio.bufWriteStrLn(stderr_buf, 'WASM: out of memory (shim)');
        exit;
    end;
    memset(uint32(shim), 0, SizeOf(TProcessWASMShim));
    shim^.WASMCtx := wctx;
    shim^.FileBuffer := buf;
    shim^.FileSize := bytesRead;
    shim^.FaultKind := wfNone;

    { 5. Serialize command-line params into the shim }
    serializeParams(shim, params);

    { 6. Wire up WASI hooks to our IO bridge }
    wasm_set_fd_write(wctx, @wasmio.asuro_fd_write);
    wasm_set_fd_read(wctx, @wasmio.asuro_fd_read);
    wasm_set_proc_exit(wctx, @wasmio.asuro_proc_exit);
    wasm_set_clock_time_get(wctx, @wasmio.asuro_clock_time_get);
    wasm_set_clock_res_get(wctx, @wasmio.asuro_clock_res_get);
    wasm_set_random_get(wctx, @wasmio.asuro_random_get);
    wasm_set_args_sizes_get(wctx, @wasmio.asuro_args_sizes_get);
    wasm_set_args_get(wctx, @wasmio.asuro_args_get);
    wasm_set_environ_sizes_get(wctx, @wasmio.asuro_environ_sizes_get);
    wasm_set_environ_get(wctx, @wasmio.asuro_environ_get);

    { Register our direct host-function override for args_get BEFORE
      the WASI preview1 bulk registration so it takes priority in
      the first-match registry lookup. }
    wasm_register_host_func(wctx, WASI_MODULE, 'args_get',
                            @wasmio.asuro_wasi_args_get);
    wasm_register_wasi_preview1(wctx);

    { 7. Create the process }
    proc := processmanager.create('WASM', @wasm_entry, void(shim), 5);
    if proc = nil then begin
        kfree(void(buf));
        if shim^.ArgBuf <> nil then kfree(void(shim^.ArgBuf));
        kfree(void(shim));
        stdio.bufWriteStrLn(stderr_buf, 'WASM: failed to create process');
        exit;
    end;

    { 8. Attach StdIO }
    proc^.StdIn := stdin_buf;
    proc^.StdOut := stdout_buf;
    proc^.StdErr := stderr_buf;

    { 9. Complete the shim }
    shim^.ProcessCtx := proc;

    { 10. Register cleanup for kill-safety }
    processmanager.bindResource(proc, rkCustom, void(shim), @wasmcleanup.wasm_resource_cleanup);

    wasm_file_handler := proc^.ProcessID;
end;

{ ---- Initialisation ---- }

procedure init;
var
    magic : array[0..3] of uint8;
begin
    tracer.push_trace('wasmrunner.init');
    syslog.logln('WASMRUNNER', 'INIT BEGIN.');

    { One-time WASURO VM initialisation }
    wasm_init;

    { Register WASM magic ($00 $61 $73 $6D = "\0asm") with file dispatcher }
    magic[0] := $00;
    magic[1] := $61;
    magic[2] := $73;
    magic[3] := $6D;
    filedispatch.registerHandler(@magic[0], 4, 'WASM', @wasm_file_handler);

    syslog.logln('WASMRUNNER', 'INIT END.');
end;

end.
