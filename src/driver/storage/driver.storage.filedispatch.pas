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
    MAX_HANDLERS   = 32;
    MAX_EXT_LIST   = 128;  { max chars for the comma-separated ext list }

type
    { Handler callback — receives the resolved absolute path,
      the command-line parameters, and the per-process IO buffers.
      Returns the PID of the created process, or 0 on failure. }
    TFileHandler = function(path : pchar;
                            params : PParamList;
                            stdin_buf, stdout_buf, stderr_buf : POutBuf) : uint32;

    THandlerKind = (hkMagic, hkExtension);

{ Register a magic-byte handler.
  magic    — pointer to the magic byte sequence to match.
  magicLen — length of the magic (1..MAX_MAGIC_LEN).
  name     — human-readable label (e.g. 'WASM').
  handler  — callback invoked when a file matches. }
procedure registerHandler(magic : puint8; magicLen : uint8;
                          name : pchar; handler : TFileHandler);

{ Register an extension-based handler.
  extList  — comma-separated extensions WITH dots, e.g. '.txt,.md,.log'
  name     — human-readable label (e.g. 'Text').
  handler  — callback invoked when a file's extension matches. }
procedure registerExtHandler(extList : pchar; name : pchar;
                             handler : TFileHandler);

{ Try to dispatch a path to a registered handler.
  absPath must be a fully-resolved absolute VFS path.
  Tries magic-byte handlers first, then extension-based handlers.
  Returns the PID of the launched process, or 0 if no handler matched. }
function dispatch(absPath : pchar;
                  params : PParamList;
                  stdin_buf, stdout_buf, stderr_buf : POutBuf) : uint32;

procedure init;

implementation

uses
    driver.storage.vfs, driver.storage.types, memory.heap, core.strings,
    core.strings.helpers, debug.tracer, io.syslog, core.util, arch.x86.util;

type
    THandlerEntry = record
        Name    : array[0..15] of char;
        Handler : TFileHandler;
        Used    : boolean;
        case Kind : THandlerKind of
            hkMagic: (
                Magic    : array[0..MAX_MAGIC_LEN-1] of uint8;
                MagicLen : uint8;
            );
            hkExtension: (
                ExtList  : array[0..MAX_EXT_LIST-1] of char;
            );
    end;

var
    Handlers     : array[0..MAX_HANDLERS-1] of THandlerEntry;
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

function matchMagic(fileBytes : puint8; entry : THandlerEntry) : boolean;
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
            Handlers[i].Kind := hkMagic;
            Handlers[i].MagicLen := magicLen;
            memcpy(uint32(magic), uint32(@Handlers[i].Magic[0]), magicLen);
            copyName(@Handlers[i].Name[0], name, 16);
            Handlers[i].Handler := handler;
            inc(HandlerCount);
            exit;
        end;
    end;
end;

procedure registerExtHandler(extList : pchar; name : pchar;
                             handler : TFileHandler);
var
    i   : uint32;
    len : uint32;
begin
    debug.tracer.push_trace('driver.storage.filedispatch.registerExtHandler');
    if (extList = nil) or (handler = nil) then exit;
    if HandlerCount >= MAX_HANDLERS then exit;
    len := stringSize(extList);
    if (len = 0) or (len >= MAX_EXT_LIST) then exit;

    for i := 0 to MAX_HANDLERS - 1 do begin
        if not Handlers[i].Used then begin
            Handlers[i].Used := true;
            Handlers[i].Kind := hkExtension;
            memcpy(uint32(extList), uint32(@Handlers[i].ExtList[0]), len);
            Handlers[i].ExtList[len] := #0;
            copyName(@Handlers[i].Name[0], name, 16);
            Handlers[i].Handler := handler;
            inc(HandlerCount);
            exit;
        end;
    end;
end;

{ matchExt — check if fileExt appears in the comma-separated extList.
  fileExt is e.g. '.txt', extList is e.g. '.txt,.md,.log'.
  Comparison is case-insensitive. }
function matchExt(fileExt : pchar; extList : pchar) : boolean;
var
    i, start, eLen, fLen : uint32;
    listLen : uint32;
    match   : boolean;
    j       : uint32;
begin
    matchExt := false;
    if (fileExt = nil) or (extList = nil) then exit;
    fLen    := stringSize(fileExt);
    listLen := stringSize(extList);
    if (fLen = 0) or (listLen = 0) then exit;

    start := 0;
    i := 0;
    while i <= listLen do begin
        if (i = listLen) or (extList[i] = ',') then begin
            eLen := i - start;
            if eLen = fLen then begin
                match := true;
                for j := 0 to eLen - 1 do begin
                    if charToLower(fileExt[j]) <> charToLower(extList[start + j]) then begin
                        match := false;
                        break;
                    end;
                end;
                if match then begin
                    matchExt := true;
                    exit;
                end;
            end;
            start := i + 1;
        end;
        inc(i);
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
    ext       : pchar;
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

    { 3. Match against registered magic-byte handlers }
    if bytesRead > 0 then begin
        for i := 0 to MAX_HANDLERS - 1 do begin
            if Handlers[i].Used and (Handlers[i].Kind = hkMagic) then begin
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
    end;

    { 4. Extension-based fallback — extract the file extension and match }
    ext := getFileExtension(absPath);
    if ext <> nil then begin
        for i := 0 to MAX_HANDLERS - 1 do begin
            if Handlers[i].Used and (Handlers[i].Kind = hkExtension) then begin
                if matchExt(ext, @Handlers[i].ExtList[0]) then begin
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
