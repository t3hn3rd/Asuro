{
    Prog->inio - Inline IO

    Usage:
        inio <file> <       Read file contents to terminal
        inio <file> > text  Write text to file

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit inio;

interface

uses
    console,
    lmemorymanager,
    storagetypes,
    strings,
    terminal,
    tracer,
    util,
    vfs;

procedure init();

implementation

procedure Run(Params : PParamList);
var
    filePath   : pchar;
    absPath    : pchar;
    op         : pchar;
    fError     : storagetypes.TError;
    fHandle    : vfs.TFileHandle;
    buf        : pchar;
    bytesRead  : uint32;
    content    : pchar;
    part       : pchar;
    tmp        : pchar;
    i          : uint32;
    pCount     : uint32;
    contentLen : uint32;
begin
    tracer.push_trace('inio.run');

    pCount := paramCount(Params);
    if pCount < 2 then begin
        console.writestringlnWND('Usage: inio <file> < | inio <file> > text', getTerminalHWND());
        exit;
    end;

    filePath := getParam(0, Params);
    op       := getParam(1, Params);

    if filePath = nil then begin
        console.writestringlnWND('Error: no file specified.', getTerminalHWND());
        exit;
    end;
    if op = nil then begin
        console.writestringlnWND('Error: no operation specified.', getTerminalHWND());
        exit;
    end;

    absPath := vfs.MakeAbsolutePath(filePath);

    { ---- READ ---- }
    if op[0] = '<' then begin
        fHandle := vfs.OpenFile(absPath, omReadOnly, wmRewrite, false, @fError);
        if (fHandle = 0) or (fError <> eNone) then begin
            console.writestringlnWND('Error: cannot open file for reading.', getTerminalHWND());
            kfree(void(absPath));
            exit;
        end;
        buf := pchar(kalloc(32768));
        memset(uint32(buf), 0, 32768);
        bytesRead := vfs.ReadFile(fHandle, 0, puint8(buf), 32767);
        vfs.CloseFile(fHandle);

        if bytesRead > 0 then begin
            buf[bytesRead] := char(0);
            console.writestringWND(buf, getTerminalHWND());
            console.writestringlnWND(' ', getTerminalHWND());
        end else begin
            console.writestringlnWND('(0 bytes read)', getTerminalHWND());
        end;
        kfree(puint32(buf));
    end

    { ---- WRITE ---- }
    else if op[0] = '>' then begin
        if pCount < 3 then begin
            console.writestringlnWND('Error: no content to write.', getTerminalHWND());
            kfree(void(absPath));
            exit;
        end;

        { Build content string by joining params 2..N with spaces }
        content := stringCopy(getParam(2, Params));
        i := 3;
        while i < pCount do begin
            part := getParam(i, Params);
            if part <> nil then begin
                { content + ' ' + part }
                tmp := stringConcat(content, ' ');
                kfree(void(content));
                content := stringConcat(tmp, part);
                kfree(void(tmp));
            end;
            i := i + 1;
        end;

        contentLen := stringSize(content);

        { Try read-write rewrite first (existing file) }
        fHandle := vfs.OpenFile(absPath, omReadWrite, wmRewrite, false, @fError);
        if (fHandle = 0) or (fError <> eNone) then begin
            { Try creating new file }
            fHandle := vfs.OpenFile(absPath, omWriteOnly, wmNew, false, @fError);
        end;

        if (fHandle = 0) or (fError <> eNone) then begin
            console.writestringlnWND('Error: cannot open file for writing.', getTerminalHWND());
            kfree(void(content));
            kfree(void(absPath));
            exit;
        end;

        vfs.WriteFile(fHandle, 0, puint8(content), contentLen);
        vfs.CloseFile(fHandle);
        console.writestringlnWND('Written.', getTerminalHWND());
        kfree(void(content));
    end else begin
        console.writestringlnWND('Error: operation must be < or >.', getTerminalHWND());
    end;

    kfree(void(absPath));
end;

procedure init();
begin
    tracer.push_trace('inio.init');
    terminal.registerCommand('INIO', @Run, 'Inline IO: inio <file> < | inio <file> > text');
end;

end.
