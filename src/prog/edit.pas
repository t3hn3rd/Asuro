{
    Prog->edit - Simple text editor

    @author(Aaron Hance <ah@aaronhance.me>)

    Controls:
        Arrow keys  - Move cursor
        Backspace   - Delete character before cursor
        Enter       - New line
        Tab         - Insert 4 spaces
        ESC         - Close editor
}
unit edit;

interface

uses
    console,
    keyboard,
    lmemorymanager,
    storagetypes,
    strings,
    terminal,
    tracer,
    util,
    vfs;

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
    Handle     : HWND = 0;
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
    fError  : storagetypes.TError;
    fHandle : vfs.TFileHandle;
    totalLen : uint32;
    buf      : pchar;
    pos      : uint32;
    i        : uint32;
begin
    tracer.push_trace('edit.SaveFile.enter');
    if FilePath = nil then begin
        console.writestringlnWND('No file path. Use: EDIT <path>', getTerminalHWND());
        exit;
    end;

    tracer.push_trace('edit.SaveFile.calcSize');
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
    tracer.push_trace('edit.SaveFile.openRW');
    fHandle := vfs.OpenFile(FilePath, omReadWrite, wmRewrite, false, @fError);
    if fHandle <> 0 then begin
        tracer.push_trace('edit.SaveFile.writeFile');
        vfs.WriteFile(fHandle, 0, puint8(buf), totalLen);
        tracer.push_trace('edit.SaveFile.closeFile');
        vfs.CloseFile(fHandle);
        Dirty := false;
        console.writestringlnWND('File saved.', getTerminalHWND());
    end else begin
        { Try write-only for new file }
        tracer.push_trace('edit.SaveFile.openWO');
        fHandle := vfs.OpenFile(FilePath, omWriteOnly, wmNew, false, @fError);
        if fHandle <> 0 then begin
            tracer.push_trace('edit.SaveFile.writeFileNew');
            vfs.WriteFile(fHandle, 0, puint8(buf), totalLen);
            tracer.push_trace('edit.SaveFile.closeFileNew');
            vfs.CloseFile(fHandle);
            Dirty := false;
            console.writestringlnWND('File saved.', getTerminalHWND());
        end else begin
            console.writestringlnWND('Error saving file.', getTerminalHWND());
        end;
    end;

    kfree(puint32(buf));
    tracer.push_trace('edit.SaveFile.exit');
end;

procedure LoadFile;
var
    fError   : storagetypes.TError;
    fHandle  : vfs.TFileHandle;
    fSize    : uint32;
    buf      : pchar;
    bytesRead: uint32;
    i        : uint32;
    lineStart: uint32;
    ch       : char;
begin
    tracer.push_trace('edit.LoadFile.enter');
    if FilePath = nil then exit;

    tracer.push_trace('edit.LoadFile.openFile');
    fHandle := vfs.OpenFile(FilePath, omReadOnly, wmRewrite, false, @fError);
    tracer.push_trace('edit.LoadFile.openFile.done');
    if (fHandle = 0) or (fError <> eNone) then begin
        console.writestringlnWND('New file.', getTerminalHWND());
        exit;
    end;

    tracer.push_trace('edit.LoadFile.readData');
    { Get size from the open file entry (dataSize is already loaded) }
    fSize := 0;
    buf := pchar(kalloc(32768)); { 32KB max }
    memset(uint32(buf), 0, 32768);
    tracer.push_trace('edit.LoadFile.readFile');
    bytesRead := vfs.ReadFile(fHandle, 0, puint8(buf), 32768);
    tracer.push_trace('edit.LoadFile.closeFile');
    vfs.CloseFile(fHandle);

    if bytesRead = 0 then begin
        kfree(puint32(buf));
        console.writestringlnWND('Empty file.', getTerminalHWND());
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
    console.writestringlnWND('File loaded.', getTerminalHWND());
    tracer.push_trace('edit.LoadFile.exit');
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

    clearWNDEx(Handle, Colors);

    { Draw text area }
    for row := 0 to TEXT_ROWS - 1 do begin
        lineIdx := ScrollY + row;
        setCursorPosWND(0, row, Handle);

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

                writecharexWND(ch, attr, Handle);
            end;
        end else begin
            { Past end of file }
            writecharexWND('~', Colors, Handle);
        end;
    end;

    { Draw status bar — limit to ED_WIDTH-1 chars so the cursor
      never advances past WND_W on the last row, which would
      trigger _newlineWND and scroll the entire buffer up. }
    setCursorPosWND(0, TEXT_ROWS, Handle);
    stCol := 0;

    { ' ESC:Exit ^S:Save' }
    if stCol < ED_WIDTH - 1 then begin writecharexWND(' ', ColorsST, Handle); inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin writecharexWND('E', ColorsST, Handle); inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin writecharexWND('S', ColorsST, Handle); inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin writecharexWND('C', ColorsST, Handle); inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin writecharexWND(':', ColorsST, Handle); inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin writecharexWND('E', ColorsST, Handle); inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin writecharexWND('x', ColorsST, Handle); inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin writecharexWND('i', ColorsST, Handle); inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin writecharexWND('t', ColorsST, Handle); inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin writecharexWND(' ', ColorsST, Handle); inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin writecharexWND('^', ColorsST, Handle); inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin writecharexWND('S', ColorsST, Handle); inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin writecharexWND(':', ColorsST, Handle); inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin writecharexWND('S', ColorsST, Handle); inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin writecharexWND('a', ColorsST, Handle); inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin writecharexWND('v', ColorsST, Handle); inc(stCol); end;
    if stCol < ED_WIDTH - 1 then begin writecharexWND('e', ColorsST, Handle); inc(stCol); end;

    { Dirty flag }
    if Dirty then begin
        if stCol < ED_WIDTH - 1 then begin writecharexWND(' ', ColorsST, Handle); inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin writecharexWND('[', ColorsST, Handle); inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin writecharexWND('+', ColorsST, Handle); inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin writecharexWND(']', ColorsST, Handle); inc(stCol); end;
    end else begin
        if stCol < ED_WIDTH - 1 then begin writecharexWND(' ', ColorsST, Handle); inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin writecharexWND(' ', ColorsST, Handle); inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin writecharexWND(' ', ColorsST, Handle); inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin writecharexWND(' ', ColorsST, Handle); inc(stCol); end;
    end;

    { File path (truncated if needed) }
    if (FilePath <> nil) and (stCol < ED_WIDTH - 1) then begin
        writecharexWND(' ', ColorsST, Handle); inc(stCol);
        i := 0;
        while (stCol < ED_WIDTH - 1) and (FilePath[i] <> char(0)) do begin
            writecharexWND(FilePath[i], ColorsST, Handle);
            inc(stCol);
            inc(i);
        end;
    end;

    { Position info }
    posStr := intToString(CurY + 1);
    if (posStr <> nil) and (stCol < ED_WIDTH - 1) then begin
        if stCol < ED_WIDTH - 1 then begin writecharexWND(' ', ColorsST, Handle); inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin writecharexWND('L', ColorsST, Handle); inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin writecharexWND(':', ColorsST, Handle); inc(stCol); end;
        i := 0;
        while (stCol < ED_WIDTH - 1) and (posStr[i] <> char(0)) do begin
            writecharexWND(posStr[i], ColorsST, Handle);
            inc(stCol);
            inc(i);
        end;
    end;
    if posStr <> nil then kfree(puint32(posStr));

    posStr := intToString(CurX + 1);
    if (posStr <> nil) and (stCol < ED_WIDTH - 1) then begin
        if stCol < ED_WIDTH - 1 then begin writecharexWND(' ', ColorsST, Handle); inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin writecharexWND('C', ColorsST, Handle); inc(stCol); end;
        if stCol < ED_WIDTH - 1 then begin writecharexWND(':', ColorsST, Handle); inc(stCol); end;
        i := 0;
        while (stCol < ED_WIDTH - 1) and (posStr[i] <> char(0)) do begin
            writecharexWND(posStr[i], ColorsST, Handle);
            inc(stCol);
            inc(i);
        end;
    end;
    if posStr <> nil then kfree(puint32(posStr));

    { Pad remainder — stop 1 short of ED_WIDTH }
    while stCol < ED_WIDTH - 1 do begin
        writecharexWND(' ', ColorsST, Handle);
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
    savedHandle : HWND;
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
        console.closeWindow(savedHandle);
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

procedure Run(Params : PParamList);
begin
    tracer.push_trace('edit.run');

    if Handle <> 0 then begin
        console.writestringlnWND('Editor is already open.', getTerminalHWND());
        exit;
    end;

    { Store file path if provided — convert to absolute path now so it
      reflects the working directory at the time the command is issued }
    if FilePath <> nil then begin
        kfree(void(FilePath));
        FilePath := nil;
    end;
    if paramCount(Params) > 0 then begin
        FilePath := vfs.MakeAbsolutePath(getParam(0, Params));
    end;

    { Initialise a fresh buffer }
    ResetBuffer; //todo also ai is freeing random memory in here

    { If a file path was given, try to load it }
    if FilePath <> nil then begin
        LoadFile;
    end;

    { Open editor window }
    Handle := console.newWindow(20, 10, ED_WIDTH, ED_HEIGHT, 'Edit');
    console.registerEventHandler(Handle, EVENT_DRAW, void(@Draw));
    console.registerEventHandler(Handle, EVENT_CLOSE, void(@OnClose));
    console.registerEventHandler(Handle, EVENT_KEY_PRESSED, void(@OnKeyPressed));

    Active := true;

    console.writestringlnWND('Editor opened. ^S to save, ESC to close.', getTerminalHWND());
end;

{ ------------------------------------------------------------------ }
{  Initialisation                                                     }
{ ------------------------------------------------------------------ }

procedure init;
begin
    tracer.push_trace('edit.init');
    Colors   := combineColors($FFFF, $0000);  { white on black }
    ColorsHL := combineColors($0000, $FFFF);  { black on white - cursor }
    ColorsST := combineColors($0000, $07E0);  { black on green - status bar }
    terminal.registerCommand('EDIT', @Run, 'Simple text editor');
end;

end.
