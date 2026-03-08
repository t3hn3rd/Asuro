{
    FileDispatch - File-type based dispatch registry.

    When the terminal encounters a token that is not a registered
    command, it asks the file dispatcher to identify the file by its
    magic header bytes and route it to the appropriate handler.

    Handlers register (magic bytes, handler function) tuples.  The
    dispatcher reads the first bytes of the file via VFS and matches
    against all registered magics.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.storage.filedispatch;

interface

uses
    io.stdio;

const
    MAX_MAGIC_LEN  = 8;
    MAX_HANDLERS   = 16;

type
    { Handler callback — receives the resolved absolute path,
      the command-line parameters, and the per-process IO buffers.
      Returns the PID of the created process, or 0 on failure. }
    TFileHandler = function(path : pchar;
                            params : PParamList;
                            stdin_buf, stdout_buf, stderr_buf : POutBuf) : uint32;

{ Register a file-type handler.
  magic    — pointer to the magic byte sequence to match.
  magicLen — length of the magic (1..MAX_MAGIC_LEN).
  name     — human-readable label (e.g. 'WASM').
  handler  — callback invoked when a file matches. }
procedure registerHandler(magic : puint8; magicLen : uint8;
                          name : pchar; handler : TFileHandler);

{ Try to dispatch a path to a registered handler.
  absPath must be a fully-resolved absolute VFS path.
  Returns the PID of the launched process, or 0 if no handler matched. }
function dispatch(absPath : pchar;
                  params : PParamList;
                  stdin_buf, stdout_buf, stderr_buf : POutBuf) : uint32;

procedure init;

implementation

uses
    driver.storage.vfs, driver.storage.types, memory.heap, core.strings, debug.tracer, io.syslog, core.util, arch.x86.util;

type
    TFileHandlerEntry = record
        Magic    : array[0..MAX_MAGIC_LEN-1] of uint8;
        MagicLen : uint8;
        Name     : array[0..15] of char;
        Handler  : TFileHandler;
        Used     : boolean;
    end;

var
    Handlers     : array[0..MAX_HANDLERS-1] of TFileHandlerEntry;
    HandlerCount : uint32;

{ ---- Internal ---- }

procedure copyName(dest : pchar; src : pchar; maxLen : uint32);
var i : uint32;
begin
    i := 0;
    while (i < maxLen - 1) and (src[i] <> #0) do begin
        dest[i] := src[i];
        inc(i);
    end;
    dest[i] := #0;
end;

function matchMagic(fileBytes : puint8; entry : TFileHandlerEntry) : boolean;
var i : uint8;
begin
    matchMagic := true;
    for i := 0 to entry.MagicLen - 1 do begin
        if fileBytes[i] <> entry.Magic[i] then begin
            matchMagic := false;
            exit;
        end;
    end;
end;

{ ---- Public API ---- }

procedure registerHandler(magic : puint8; magicLen : uint8;
                          name : pchar; handler : TFileHandler);
var
    i : uint32;
begin
    debug.tracer.push_trace('driver.storage.filedispatch.registerHandler');
    if (magicLen = 0) or (magicLen > MAX_MAGIC_LEN) then exit;
    if HandlerCount >= MAX_HANDLERS then exit;

    for i := 0 to MAX_HANDLERS - 1 do begin
        if not Handlers[i].Used then begin
            Handlers[i].Used := true;
            Handlers[i].MagicLen := magicLen;
            memcpy(uint32(magic), uint32(@Handlers[i].Magic[0]), magicLen);
            copyName(@Handlers[i].Name[0], name, 16);
            Handlers[i].Handler := handler;
            inc(HandlerCount);
            exit;
        end;
    end;
end;

function dispatch(absPath : pchar;
                  params : PParamList;
                  stdin_buf, stdout_buf, stderr_buf : POutBuf) : uint32;
var
    validity  : TIsPathValid;
    fh        : TFileHandle;
    err       : TError;
    headerBuf : array[0..MAX_MAGIC_LEN-1] of uint8;
    bytesRead : uint32;
    i         : uint32;
    pid       : uint32;
begin
    debug.tracer.push_trace('driver.storage.filedispatch.dispatch');
    dispatch := 0;

    { 1. Check that the path is a valid file }
    validity := driver.storage.vfs.PathValid(absPath);
    if validity <> pvFile then exit;

    { 2. Open the file in stream mode — only reads the bytes we ask for,
         avoids pre-loading the entire file just to check a few magic bytes. }
    err := eNone;
    fh := driver.storage.vfs.OpenFile(absPath, omStream, @err);
    if fh = 0 then exit;

    memset(uint32(@headerBuf[0]), 0, MAX_MAGIC_LEN);
    bytesRead := driver.storage.vfs.ReadFile(fh, 0, @headerBuf[0], MAX_MAGIC_LEN);
    driver.storage.vfs.CloseFile(fh);

    if bytesRead = 0 then exit;

    { 3. Match against registered handlers (longest magic first
         is not needed — we just iterate and take first match) }
    for i := 0 to MAX_HANDLERS - 1 do begin
        if Handlers[i].Used then begin
            if Handlers[i].MagicLen <= bytesRead then begin
                if matchMagic(@headerBuf[0], Handlers[i]) then begin
                    pid := Handlers[i].Handler(absPath, params,
                                               stdin_buf, stdout_buf, stderr_buf);
                    if pid > 0 then begin
                        dispatch := pid;
                        exit;
                    end;
                end;
            end;
        end;
    end;

    { 4. No handler matched — future: try extension-based fallback }
end;

procedure init;
var i : uint32;
begin
    debug.tracer.push_trace('driver.storage.filedispatch.init');
    io.syslog.logln('FILEDISPATCH', 'INIT BEGIN.');
    for i := 0 to MAX_HANDLERS - 1 do
        Handlers[i].Used := false;
    HandlerCount := 0;
    io.syslog.logln('FILEDISPATCH', 'INIT END.');
end;

end.
