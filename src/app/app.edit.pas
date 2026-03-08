{
    Prog->app.edit - Simple text editor

    @author(Aaron Hance <ah@aaronhance.me>)

    Controls:
        Arrow keys  - Move cursor
        Backspace   - Delete character before cursor
        Enter       - New line
        Tab         - Insert 4 spaces
        ESC         - Close editor
}
unit app.edit;

interface

uses
    io.syslog,
    driver.hid.keyboard,
    memory.heap,
    driver.storage.types,
    core.strings,
    io.stdio,
    debug.tracer,
    core.util, arch.x86.util,
    driver.storage.vfs;

procedure init();

implementation

const
    ED_WIDTH   = 60;
    ED_HEIGHT  = 20;
    MAX_LINES  = 256;
    MAX_COLS   = 120;
    TEXT_ROWS  = 19;   { ED_HEIGHT - 1, last row is status bar }
    TAB_SIZE   = 4;

var
    Handle     : uint32 = 0;
    Colors     : uint32;
    ColorsHL   : uint32;
    ColorsST   : uint32;

    Lines      : array[0..255] of pchar;
    LineLen    : array[0..255] of uint32;
    NumLines   : uint32 = 0;

    CurX       : uint32 = 0;
    CurY       : uint32 = 0;
    ScrollY    : uint32 = 0;

    Dirty      : boolean = false;
    Active     : boolean = false;
    FilePath   : pchar = nil;

{ ------------------------------------------------------------------ }
{  Buffer management                                                  }
{ ------------------------------------------------------------------ }

procedure AllocLine(idx : uint32);
begin
    Lines[idx] := pchar(kalloc(MAX_COLS + 1));
    memset(uint32(Lines[idx]), 0, MAX_COLS + 1);
    LineLen[idx] := 0;
end;

procedure FreeLine(idx : uint32);
begin
    if Lines[idx] <> nil then begin
        kfree(puint32(Lines[idx]));
        Lines[idx] := nil;
    end;
    LineLen[idx] := 0;
end;

procedure ResetBuffer;
var
    i : uint32;
begin
    for i := 0 to MAX_LINES - 1 do begin
        if Lines[i] <> nil then FreeLine(i);
    end;
    AllocLine(0);
    NumLines := 1;
    CurX := 0;
    CurY := 0;
    ScrollY := 0;
    Dirty := false;
end;

procedure EnsureVisible;
begin
    if CurY < ScrollY then
        ScrollY := CurY;
    if CurY >= ScrollY + TEXT_ROWS then
        ScrollY := CurY - TEXT_ROWS + 1;
end;

procedure SaveFile;
var
    fError  : driver.storage.types.TError;
    fHandle : driver.storage.vfs.TFileHandle;
    totalLen : uint32;
    buf      : pchar;
    pos      : uint32;
    i        : uint32;
begin
    debug.tracer.push_trace('edit.SaveFile.enter');
    if FilePath = nil then begin
        io.syslog.writestringln('No file path. Use: EDIT <path>');
        exit;
    end;

    debug.tracer.push_trace('edit.SaveFile.calcSize');
    { Calculate total size: sum of line lengths + newlines }
    totalLen := 0;
    for i := 0 to NumLines - 1 do begin
        totalLen := totalLen + LineLen[i] + 1; { +1 for newline }
    end;
    if totalLen > 0 then dec(totalLen); { No trailing newline }

    buf := pchar(kalloc(totalLen + 1));
    memset(uint32(buf), 0, totalLen + 1);

    pos := 0;
    for i := 0 to NumLines - 1 do begin
        if LineLen[i] > 0 then begin
            memcpy(uint32(Lines[i]), uint32(@buf[pos]), LineLen[i]);
            pos := pos + LineLen[i];
        end;
        if i < NumLines - 1 then begin
            buf[pos] := char(10); { LF newline }
            pos := pos + 1;
        end;
    end;

    { Open for writing }
    debug.tracer.push_trace('edit.SaveFile.openRW');
    fHandle := driver.storage.vfs.OpenFile(FilePath, omReadWrite, wmRewrite, @fError);
    if fHandle <> 0 then begin
        debug.tracer.push_trace('edit.SaveFile.writeFile');
        driver.storage.vfs.WriteFile(fHandle, 0, puint8(buf), totalLen);
        debug.tracer.push_trace('edit.SaveFile.closeFile');
        driver.storage.vfs.CloseFile(fHandle);
        Dirty := false;
        io.syslog.writestringln('File saved.');
    end else begin
        { Try write-only for new file }
        debug.tracer.push_trace('edit.SaveFile.openWO');
        fHandle := driver.storage.vfs.OpenFile(FilePath, omWriteOnly, wmNew, @fError);
        if fHandle <> 0 then begin
            debug.tracer.push_trace('edit.SaveFile.writeFileNew');
            driver.storage.vfs.WriteFile(fHandle, 0, puint8(buf), totalLen);
            debug.tracer.push_trace('edit.SaveFile.closeFileNew');
            driver.storage.vfs.CloseFile(fHandle);
            Dirty := false;
            io.syslog.writestringln('File saved.');
        end else begin
            io.syslog.writestringln('Error saving file.');
        end;
    end;

    kfree(puint32(buf));
    debug.tracer.push_trace('edit.SaveFile.exit');
end;

procedure LoadFile;
var
    fError   : driver.storage.types.TError;
    fHandle  : driver.storage.vfs.TFileHandle;
    fSize    : uint32;
    buf      : pchar;
    bytesRead: uint32;
    i        : uint32;
    lineStart: uint32;
    ch       : char;
begin
    debug.tracer.push_trace('edit.LoadFile.enter');
    if FilePath = nil then exit;

    debug.tracer.push_trace('edit.LoadFile.openFile');
    fHandle := driver.storage.vfs.OpenFile(FilePath, omReadOnly, wmRewrite, @fError);
    debug.tracer.push_trace('edit.LoadFile.openFile.done');
    if (fHandle = 0) or (fError <> eNone) then begin
        io.syslog.writestringln('New file.');
        exit;
    end;

    debug.tracer.push_trace('edit.LoadFile.readData');
    { Get size from the open file entry (dataSize is already loaded) }
    fSize := 0;
    buf := pchar(kalloc(32768)); { 32KB max }
    memset(uint32(buf), 0, 32768);
    debug.tracer.push_trace('edit.LoadFile.readFile');
    bytesRead := driver.storage.vfs.ReadFile(fHandle, 0, puint8(buf), 32768);
    debug.tracer.push_trace('edit.LoadFile.closeFile');
    driver.storage.vfs.CloseFile(fHandle);

    if bytesRead = 0 then begin
        kfree(puint32(buf));
        io.syslog.writestringln('Empty file.');
        exit;
    end;

    { Parse buffer into lines, split on LF (10) or CR (13) }
    ResetBuffer;
    NumLines := 0;
    AllocLine(0);
    NumLines := 1;

    lineStart := 0;
    for i := 0 to bytesRead - 1 do begin
        ch := buf[i];
        if ch = char(13) then continue; { Skip CR }
        if ch = char(10) then begin
            { Start a new line }
            if NumLines < MAX_LINES then begin
                AllocLine(NumLines);
                NumLines := NumLines + 1;
            end;
        end else if ch = char(0) then begin
            break; { End of data }
        end else begin
            { Append char to current line }
            if LineLen[NumLines - 1] < MAX_COLS - 1 then begin
                Lines[NumLines - 1][LineLen[NumLines - 1]] := ch;
                LineLen[NumLines - 1] := LineLen[NumLines - 1] + 1;
                Lines[NumLines - 1][LineLen[NumLines - 1]] := char(0);
            end;
        end;
    end;

    kfree(puint32(buf));
    CurX := 0;
    CurY := 0;
    ScrollY := 0;
    Dirty := false;
    io.syslog.writestringln('File loaded.');
    debug.tracer.push_trace('edit.LoadFile.exit');
end;

{ ------------------------------------------------------------------ }
{  Drawing                                                            }
{ ------------------------------------------------------------------ }

procedure Draw;
var
    row, col  : uint32;
    lineIdx   : uint32;
    ch        : char;
    attr      : uint32;
    posStr    : pchar;
    i         : uint32;
    stCol     : uint32;
begin
    if Handle = 0 then exit;
    if not Active then exit;

    { stub: clearWNDEx };

    { Draw text area }
    for row := 0 to TEXT_ROWS - 1 do begin
        lineIdx := ScrollY + row;
        { stub: setCursorPosWND };

        if lineIdx < NumLines then begin
            for col := 0 to ED_WIDTH - 1 do begin
                if col < LineLen[lineIdx] then
                    ch := Lines[lineIdx][col]
                else
                    ch := ' ';

                if (lineIdx = CurY) and (col = CurX) then
                    attr := ColorsHL
                else
                    attr := Colors;

                { stub: writecharexWND };
            end;
        end else begin
            { Past end of file }
            { stub: writecharexWND };
        end;
    end;

    { Draw status bar — limit to ED_WIDTH-1 chars so the cursor
      never advances past WND_W on the last row, which would
      trigger _newlineWND and scroll the entire buffer up. }
    { stub: setCursorPosWND };
    stCol := 0;

    { ' ESC:Exit ^S:Save' }
    if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;

    { Dirty flag }
    if Dirty then begin
        if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
    end else begin
        if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
    end;

    { File path (truncated if needed) }
    if (FilePath <> nil) and (stCol < ED_WIDTH - 1) then begin
        { stub: writecharexWND }; inc(stCol);
        i := 0;
        while (stCol < ED_WIDTH - 1) and (FilePath[i] <> char(0)) do begin
            { stub: writecharexWND };
            inc(stCol);
            inc(i);
        end;
    end;

    { Position info }
    posStr := intToString(CurY + 1);
    if (posStr <> nil) and (stCol < ED_WIDTH - 1) then begin
        if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
        i := 0;
        while (stCol < ED_WIDTH - 1) and (posStr[i] <> char(0)) do begin
            { stub: writecharexWND };
            inc(stCol);
            inc(i);
        end;
    end;
    if posStr <> nil then kfree(puint32(posStr));

    posStr := intToString(CurX + 1);
    if (posStr <> nil) and (stCol < ED_WIDTH - 1) then begin
        if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin { stub: writecharexWND }; inc(stCol); end;
        i := 0;
        while (stCol < ED_WIDTH - 1) and (posStr[i] <> char(0)) do begin
            { stub: writecharexWND };
            inc(stCol);
            inc(i);
        end;
    end;
    if posStr <> nil then kfree(puint32(posStr));

    { Pad remainder — stop 1 short of ED_WIDTH }
    while stCol < ED_WIDTH - 1 do begin
        { stub: writecharexWND };
        inc(stCol);
    end;
end;

{ ------------------------------------------------------------------ }
{  Text editing operations                                            }
{ ------------------------------------------------------------------ }

procedure InsertChar(ch : char);
var
    i : uint32;
begin
    if LineLen[CurY] >= MAX_COLS - 1 then exit;

    { Shift characters right from end to CurX }
    i := LineLen[CurY];
    while i > CurX do begin
        Lines[CurY][i] := Lines[CurY][i - 1];
        dec(i);
    end;

    Lines[CurY][CurX] := ch;
    LineLen[CurY] := LineLen[CurY] + 1;
    Lines[CurY][LineLen[CurY]] := char(0);
    CurX := CurX + 1;
    Dirty := true;
end;

procedure InsertNewLine;
var
    tailLen : uint32;
    i       : uint32;
begin
    if NumLines >= MAX_LINES - 1 then exit;

    { Shift all lines below CurY down by one }
    i := NumLines;
    while i > CurY + 1 do begin
        Lines[i] := Lines[i - 1];
        LineLen[i] := LineLen[i - 1];
        dec(i);
    end;

    { Allocate the new line }
    AllocLine(CurY + 1);

    { Copy text after cursor to new line }
    tailLen := LineLen[CurY] - CurX;
    if tailLen > 0 then begin
        memcpy(uint32(@Lines[CurY][CurX]), uint32(Lines[CurY + 1]), tailLen);
        LineLen[CurY + 1] := tailLen;
        Lines[CurY + 1][tailLen] := char(0);
    end;

    { Truncate current line at cursor }
    LineLen[CurY] := CurX;
    Lines[CurY][CurX] := char(0);

    NumLines := NumLines + 1;
    CurX := 0;
    CurY := CurY + 1;
    Dirty := true;
    EnsureVisible;
end;

procedure DeleteBack;
var
    i       : uint32;
    prevLen : uint32;
begin
    if (CurX = 0) and (CurY = 0) then exit;

    if CurX > 0 then begin
        { Delete character before cursor on this line }
        i := CurX - 1;
        while i < LineLen[CurY] - 1 do begin
            Lines[CurY][i] := Lines[CurY][i + 1];
            i := i + 1;
        end;
        LineLen[CurY] := LineLen[CurY] - 1;
        Lines[CurY][LineLen[CurY]] := char(0);
        CurX := CurX - 1;
        Dirty := true;
    end else begin
        { At column 0: merge this line into previous }
        prevLen := LineLen[CurY - 1];

        if LineLen[CurY] > 0 then begin
            if prevLen + LineLen[CurY] < MAX_COLS then begin
                memcpy(uint32(Lines[CurY]), uint32(@Lines[CurY - 1][prevLen]), LineLen[CurY]);
                LineLen[CurY - 1] := prevLen + LineLen[CurY];
                Lines[CurY - 1][LineLen[CurY - 1]] := char(0);
            end;
        end;

        { Free merged line }
        FreeLine(CurY);

        { Shift remaining lines up }
        i := CurY;
        while i < NumLines - 1 do begin
            Lines[i] := Lines[i + 1];
            LineLen[i] := LineLen[i + 1];
            i := i + 1;
        end;
        Lines[NumLines - 1] := nil;
        LineLen[NumLines - 1] := 0;

        NumLines := NumLines - 1;
        CurY := CurY - 1;
        CurX := prevLen;
        Dirty := true;
        EnsureVisible;
    end;
end;

{ ------------------------------------------------------------------ }
{  Event handlers                                                     }
{ ------------------------------------------------------------------ }

procedure OnKeyPressed(info : TKeyInfo);
var
    i : uint32;
    savedHandle : uint32;
begin
    if not Active then exit;
    if Handle = 0 then exit;

    { Ctrl+S: save file }
    if info.CTRL_DOWN and (info.key_code = uint8('s')) then begin
        SaveFile;
        exit;
    end;

    { Escape: close editor }
    if info.key_code = $1B then begin
        Active := false;
        ResetBuffer;
        if FilePath <> nil then begin
            kfree(void(FilePath));
            FilePath := nil;
        end;
        savedHandle := Handle;
        Handle := 0;
        { TODO: closeWindow };
        exit;
    end;

    { Tab: insert spaces }
    if info.key_code = $09 then begin
        for i := 0 to TAB_SIZE - 1 do begin
            InsertChar(' ');
        end;
        exit;
    end;

    { Backspace }
    if info.key_code = $08 then begin
        DeleteBack;
        exit;
    end;

    { Enter }
    if info.key_code = $0D then begin
        InsertNewLine;
        exit;
    end;

    { Arrow Up }
    if info.key_code = $10 then begin
        if CurY > 0 then begin
            CurY := CurY - 1;
            if CurX > LineLen[CurY] then CurX := LineLen[CurY];
            EnsureVisible;
        end;
        exit;
    end;

    { Arrow Down }
    if info.key_code = $12 then begin
        if CurY < NumLines - 1 then begin
            CurY := CurY + 1;
            if CurX > LineLen[CurY] then CurX := LineLen[CurY];
            EnsureVisible;
        end;
        exit;
    end;

    { Arrow Left }
    if info.key_code = $13 then begin
        if CurX > 0 then begin
            CurX := CurX - 1;
        end else if CurY > 0 then begin
            CurY := CurY - 1;
            CurX := LineLen[CurY];
            EnsureVisible;
        end;
        exit;
    end;

    { Arrow Right }
    if info.key_code = $14 then begin
        if CurX < LineLen[CurY] then begin
            CurX := CurX + 1;
        end else if CurY < NumLines - 1 then begin
            CurY := CurY + 1;
            CurX := 0;
            EnsureVisible;
        end;
        exit;
    end;

    { Printable characters (space through tilde) }
    if (info.key_code >= 32) and (info.key_code <= 126) then begin
        InsertChar(char(info.key_code));
    end;
end;

procedure OnClose;
begin
    Active := false;
    Handle := 0;
    ResetBuffer;
end;

{ ------------------------------------------------------------------ }
{  Command entry point                                                }
{ ------------------------------------------------------------------ }

procedure Run(Params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
begin
    debug.tracer.push_trace('edit.run');

    if Handle <> 0 then begin
        io.syslog.writestringln('Editor is already open.');
        exit;
    end;

    { Store file path if provided — convert to absolute path now so it
      reflects the working directory at the time the command is issued }
    if FilePath <> nil then begin
        kfree(void(FilePath));
        FilePath := nil;
    end;
    if paramCount(Params) > 0 then begin
        FilePath := driver.storage.vfs.MakeAbsolutePath(getParam(0, Params));
    end;

    { Initialise a fresh buffer }
    ResetBuffer; //todo also ai is freeing random memory in here

    { If a file path was given, try to load it }
    if FilePath <> nil then begin
        LoadFile;
    end;

    { Open editor window }
    Handle := 0 { TODO: newWindow };
    { TODO: registerEventHandler }
    { TODO: registerEventHandler }
    { TODO: registerEventHandler }

    Active := true;

    io.syslog.writestringln('Editor opened. ^S to save, ESC to close.');
end;

{ ------------------------------------------------------------------ }
{  Initialisation                                                     }
{ ------------------------------------------------------------------ }

procedure init;
begin
    debug.tracer.push_trace('edit.init');
    Colors   := $FFFF0000;  { white on black }
    ColorsHL := $0000FFFF;  { black on white - cursor }
    ColorsST := $000007E0;  { black on green - status bar }
    io.stdio.registerCommand('EDIT', @Run, 'Simple text editor');
end;

end.
