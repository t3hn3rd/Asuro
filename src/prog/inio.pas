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
    syslog,
    lmemorymanager,
    storagetypes,
    strings,
    stdio,
    tracer,
    util,
    vfs;

procedure init();

implementation

procedure Run(Params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
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
        syslog.writestringln('Usage: inio <file> < | inio <file> > text');
        exit;
    end;

    filePath := getParam(0, Params);
    op       := getParam(1, Params);

    if filePath = nil then begin
        syslog.writestringln('Error: no file specified.');
        exit;
    end;
    if op = nil then begin
        syslog.writestringln('Error: no operation specified.');
        exit;
    end;

    absPath := vfs.MakeAbsolutePath(filePath);

    { ---- READ ---- }
    if op[0] = '<' then begin
        fHandle := vfs.OpenFile(absPath, omReadOnly, wmRewrite, @fError);
        if (fHandle = 0) or (fError <> eNone) then begin
            syslog.writestringln('Error: cannot open file for reading.');
            kfree(void(absPath));
            exit;
        end;
        buf := pchar(kalloc(32768));
        memset(uint32(buf), 0, 32768);
        bytesRead := vfs.ReadFile(fHandle, 0, puint8(buf), 32767);
        vfs.CloseFile(fHandle);

        if bytesRead > 0 then begin
            buf[bytesRead] := char(0);
            syslog.writestring(buf);
            syslog.writestringln(' ');
        end else begin
            syslog.writestringln('(0 bytes read)');
        end;
        kfree(puint32(buf));
    end

    { ---- WRITE ---- }
    else if op[0] = '>' then begin
        if pCount < 3 then begin
            syslog.writestringln('Error: no content to write.');
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
        fHandle := vfs.OpenFile(absPath, omReadWrite, wmRewrite, @fError);
        if (fHandle = 0) or (fError <> eNone) then begin
            { Try creating new file }
            fHandle := vfs.OpenFile(absPath, omWriteOnly, wmNew, @fError);
        end;

        if (fHandle = 0) or (fError <> eNone) then begin
            syslog.writestringln('Error: cannot open file for writing.');
            kfree(void(content));
            kfree(void(absPath));
            exit;
        end;

        vfs.WriteFile(fHandle, 0, puint8(content), contentLen);
        vfs.CloseFile(fHandle);
        syslog.writestringln('Written.');
        kfree(void(content));
    end else begin
        syslog.writestringln('Error: operation must be < or >.');
    end;

    kfree(void(absPath));
end;

procedure init();
begin
    tracer.push_trace('inio.init');
    stdio.registerCommand('INIO', @Run, 'Inline IO: inio <file> < | inio <file> > text');
end;

end.
