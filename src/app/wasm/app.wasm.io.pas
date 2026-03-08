{
    Prog->WASM->WASMIO - WASI hook implementations bridging to POutBuf.

    Provides concrete WASI callback functions that route fd 0/1/2
    to the owning Asuro process's StdIn/StdOut/StdErr buffers.

    An ActiveShim module-level variable is set before each tick batch
    and cleared after.  Hooks only fire synchronously within wasm_tick
    so this is safe under preemptive scheduling.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit app.wasm.io;

interface

uses
    app.wasm.shim,
    wasm.types.builtin,
    wasm.types.context,
    wasm.types.values;

{ Set/clear the active shim — call before/after each tick batch }
procedure setActiveShim(shim : PProcessWASMShim);
procedure clearActiveShim;

{ WASI hook implementations — register via wasm_set_fd_write etc. }
function asuro_fd_write(fd : TWASMUInt32; buf : TWASMPUInt8; len : TWASMUInt32) : TWASMUInt32;
function asuro_fd_read(fd : TWASMUInt32; buf : TWASMPUInt8; len : TWASMUInt32) : TWASMUInt32;
procedure asuro_proc_exit(code : TWASMUInt32);
function asuro_clock_time_get(clock_id : TWASMUInt32; precision : TWASMUInt64; var time : TWASMUInt64) : TWASMUInt32;
function asuro_clock_res_get(clock_id : TWASMUInt32; var resolution : TWASMUInt64) : TWASMUInt32;
function asuro_random_get(buf : TWASMPUInt8; len : TWASMUInt32) : TWASMUInt32;
function asuro_args_sizes_get(var count : TWASMUInt32; var buf_size : TWASMUInt32) : TWASMUInt32;
function asuro_args_get(argv : TWASMPUInt32; argv_buf : TWASMPUInt8) : TWASMUInt32;
function asuro_environ_sizes_get(var count : TWASMUInt32; var buf_size : TWASMUInt32) : TWASMUInt32;
function asuro_environ_get(environ : TWASMPUInt32; environ_buf : TWASMPUInt8) : TWASMUInt32;

{ Direct host-function override for args_get (TWASMHostFunc signature).
  The wasuro preview1 glue for args_get is a stub that does not call
  the hook, so we register this as a host function to take its place. }
procedure asuro_wasi_args_get(Context : PWASMProcessContext);

implementation

uses
    io.stdio, proc.types,
    wasm.types.wasi, wasm.types.stack, wasm.types.heap,
    arch.x86.bda, core.rand, core.util, arch.x86.util;

var
    ActiveShimPtr : PProcessWASMShim;

procedure setActiveShim(shim : PProcessWASMShim);
begin
    ActiveShimPtr := shim;
end;

procedure clearActiveShim;
begin
    ActiveShimPtr := nil;
end;

{ ---- fd_write: fd 1 = stdout, fd 2 = stderr ---- }

function asuro_fd_write(fd : TWASMUInt32; buf : TWASMPUInt8; len : TWASMUInt32) : TWASMUInt32;
var
    outbuf : POutBuf;
    i      : TWASMUInt32;
begin
    asuro_fd_write := 0;
    if ActiveShimPtr = nil then exit;
    if ActiveShimPtr^.ProcessCtx = nil then exit;

    case fd of
        WASI_FD_STDOUT: outbuf := ActiveShimPtr^.ProcessCtx^.StdOut;
        WASI_FD_STDERR: outbuf := ActiveShimPtr^.ProcessCtx^.StdErr;
    else begin
        asuro_fd_write := 0;
        exit;
    end;
    end;

    if outbuf = nil then exit;

    { Write byte-by-byte into the POutBuf }
    for i := 0 to len - 1 do
        io.stdio.bufWriteChar(outbuf, char(buf[i]));

    asuro_fd_write := len;
end;

{ ---- fd_read: fd 0 = stdin (non-blocking for now) ---- }

function asuro_fd_read(fd : TWASMUInt32; buf : TWASMPUInt8; len : TWASMUInt32) : TWASMUInt32;
var
    inbuf    : POutBuf;
    avail    : uint32;
    copyLen  : uint32;
begin
    asuro_fd_read := 0;
    if ActiveShimPtr = nil then exit;
    if ActiveShimPtr^.ProcessCtx = nil then exit;

    if fd <> WASI_FD_STDIN then exit;

    inbuf := ActiveShimPtr^.ProcessCtx^.StdIn;
    if inbuf = nil then exit;

    { Non-blocking: return whatever is available, 0 if nothing }
    avail := inbuf^.len;
    if avail = 0 then exit;
    if len < avail then copyLen := len else copyLen := avail;
    memcpy(uint32(inbuf^.buf), uint32(buf), copyLen);
    asuro_fd_read := copyLen;
end;

{ ---- proc_exit: propagate exit code to process ---- }

procedure asuro_proc_exit(code : TWASMUInt32);
begin
    { The WASURO VM has already set Running := false and ExitCode.
      We just propagate to the Asuro process context. }
    if ActiveShimPtr = nil then exit;
    if ActiveShimPtr^.ProcessCtx = nil then exit;
    ActiveShimPtr^.ProcessCtx^.ExitCode := code;
end;

{ ---- clock_time_get: use BIOS tick counter ---- }

function asuro_clock_time_get(clock_id : TWASMUInt32; precision : TWASMUInt64;
                              var time : TWASMUInt64) : TWASMUInt32;
begin
    { Return time in nanoseconds based on BIOS 1024 Hz counter }
    time := TWASMUInt64(arch.x86.bda.Counters.c64) * 976562;
    asuro_clock_time_get := WASI_ESUCCESS;
end;

{ ---- clock_res_get: ~1ms resolution ---- }

function asuro_clock_res_get(clock_id : TWASMUInt32;
                             var resolution : TWASMUInt64) : TWASMUInt32;
begin
    resolution := 976562; { ~0.977ms in nanoseconds (1/1024 s) }
    asuro_clock_res_get := WASI_ESUCCESS;
end;

{ ---- random_get: fill buffer with random bytes ---- }

function asuro_random_get(buf : TWASMPUInt8; len : TWASMUInt32) : TWASMUInt32;
var
    i : TWASMUInt32;
    r : uint32;
begin
    i := 0;
    while i < len do begin
        r := core.rand.rand32;
        buf[i] := uint8(r and $FF);
        inc(i);
        if i < len then begin buf[i] := uint8((r shr 8) and $FF); inc(i); end;
        if i < len then begin buf[i] := uint8((r shr 16) and $FF); inc(i); end;
        if i < len then begin buf[i] := uint8((r shr 24) and $FF); inc(i); end;
    end;
    asuro_random_get := WASI_ESUCCESS;
end;

{ ---- args: pass through params from io.stdio ---- }

function asuro_args_sizes_get(var count : TWASMUInt32; var buf_size : TWASMUInt32) : TWASMUInt32;
begin
    if ActiveShimPtr = nil then begin
        count := 0;
        buf_size := 0;
    end else begin
        count := ActiveShimPtr^.ArgCount;
        buf_size := ActiveShimPtr^.ArgBufSize;
    end;
    asuro_args_sizes_get := WASI_ESUCCESS;
end;

function asuro_args_get(argv : TWASMPUInt32; argv_buf : TWASMPUInt8) : TWASMUInt32;
begin
    { This hook is not called by the wasuro preview1 glue;
      asuro_wasi_args_get handles args_get as a direct host function. }
    asuro_args_get := WASI_ESUCCESS;
end;

{ Direct host-function override for args_get.
  Pops argv_ptr and argv_buf_ptr from the operand stack,
  writes arg data into WASM linear memory, and pushes ESUCCESS. }
procedure asuro_wasi_args_get(Context : PWASMProcessContext);
var
    argv_ptr, argv_buf_ptr : TWASMUInt32;
    os   : PWASMStack;
    mem  : PWasmHeap;
    i, j : TWASMUInt32;
    off  : TWASMUInt32;
begin
    os  := Context^.ExecutionState.Operand_Stack;
    mem := Context^.ExecutionState.Memory;

    argv_buf_ptr := TWASMUInt32(wasm.types.stack.popi32(os));
    argv_ptr     := TWASMUInt32(wasm.types.stack.popi32(os));

    if (ActiveShimPtr = nil) or (ActiveShimPtr^.ArgCount = 0) then begin
        wasm.types.stack.pushi32(os, TWASMInt32(WASI_ESUCCESS));
        exit;
    end;

    { Walk the flat ArgBuf, writing each null-terminated string into
      WASM memory at argv_buf_ptr+offset, and recording the WASM-side
      pointer in the argv array. }
    off := 0;
    j := 0;
    for i := 0 to ActiveShimPtr^.ArgCount - 1 do begin
        { argv[i] = WASM offset of this string }
        wasm.types.heap.write_uint32(argv_ptr + (i * 4), mem, argv_buf_ptr + off);

        { Copy bytes including the null terminator }
        while (j < ActiveShimPtr^.ArgBufSize) do begin
            wasm.types.heap.write_uint8(argv_buf_ptr + off, mem,
                TWASMUInt8(byte(ActiveShimPtr^.ArgBuf[j])));
            inc(off);
            inc(j);
            if ActiveShimPtr^.ArgBuf[j - 1] = #0 then break;
        end;
    end;

    wasm.types.stack.pushi32(os, TWASMInt32(WASI_ESUCCESS));
end;

{ ---- environ: no environment variables ---- }

function asuro_environ_sizes_get(var count : TWASMUInt32; var buf_size : TWASMUInt32) : TWASMUInt32;
begin
    count := 0;
    buf_size := 0;
    asuro_environ_sizes_get := WASI_ESUCCESS;
end;

function asuro_environ_get(environ : TWASMPUInt32; environ_buf : TWASMPUInt8) : TWASMUInt32;
begin
    asuro_environ_get := WASI_ESUCCESS;
end;

end.
