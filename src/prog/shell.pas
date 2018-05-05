unit shell;

interface

uses
    Console, RTC, terminal, strings, asuro;

procedure init();

implementation

var
    TaskBarHandle : HWND = 0;
    DesktopHandle : HWND = 0;
    Takbar_Colors : uint32;
    Explore_Colors : uint32;
    Desktop_Colors : uint32;

procedure Draw();
var
    DateTime : TDateTime;
    i : uint32;
    s : pchar;

begin
     DateTime:= getDateTime;

     console.clearWNDEx(TaskBarHandle, Takbar_Colors);

     console.setCursorPosWND(0, 0, TaskBarHandle);
     console.writeStringExWND(' TERMINAL ', Explore_Colors, TaskBarHandle);
     console.writeCharExWND(#6, Takbar_Colors, TaskBarHandle);

     for i:=0 to 9 do begin
        s:= getWindowName(i);
        if s <> nil then begin
            console.writeStringExWND(s, Takbar_Colors, TaskBarHandle);
            console.writeCharExWND(' ', Takbar_Colors, TaskBarHandle);
            console.writeCharExWND(#6, Takbar_Colors, TaskBarHandle);
        end;
     end;

     console.setCursorPosWND(150, 0, TaskBarHandle);
     if DateTime.Hours < 10 then writeIntExWND(0, Takbar_Colors, TaskBarHandle);
     writeIntExWND(DateTime.Hours, Takbar_Colors, TaskBarHandle);
     writeStringExWND(':', Takbar_Colors, TaskBarHandle);
     if DateTime.Minutes < 10 then writeIntExWND(0, Takbar_Colors, TaskBarHandle);
     writeIntExWND(DateTime.Minutes, Takbar_Colors, TaskBarHandle);
     writeStringExWND(':', Takbar_Colors, TaskBarHandle);
     if DateTime.Seconds < 10 then writeIntExWND(0, Takbar_Colors, TaskBarHandle);
     writeIntExWND(DateTime.Seconds, Takbar_Colors, TaskBarHandle);
end;

procedure OnMouseClick(x : uint32; y : uint32; left : boolean);
begin
    //WriteIntLn(x);
    //WriteIntLn(y);
    if left then begin
        if (y = 0) and (x < 10) then begin
            terminal.run;
        end;
    end;
end;

procedure onBaseDraw();
var
    versionSize  : uint32;
    versionDrawX : uint32;
    releaseSize  : uint32;
    releaseDrawX : uint32;

begin
    clearWNDEx(DesktopHandle, Desktop_Colors);
    if not(StringEquals(asuro.RELEASE, 'r')) then begin
        versionSize:= StringSize(asuro.VERSION) + StringSize('Asuro v');
        versionDrawX:= 157 - versionSize;
        setCursorPosWND(versionDrawX, 60, DesktopHandle);
        writestringExWND('ASURO v', Desktop_Colors, DesktopHandle);
        writestringExWND(asuro.VERSION, Desktop_Colors, DesktopHandle);
        if StringEquals(asuro.RELEASE, 'rc') then begin
            releaseSize:= StringSize('RELEASE CANDIDATE');
            releaseDrawX:= 157 - (versionSize div 2) - (releaseSize div 2);
            setCursorPosWND(releaseDrawX, 61, DesktopHandle);
            writeStringExWND('RELEASE CANDIDATE', Desktop_Colors, DesktopHandle);
        end;
        if StringEquals(asuro.RELEASE, 'ia') then begin
            releaseSize:= StringSize('INTERNAL ALPHA');
            releaseDrawX:= 157 - (versionSize div 2) - (releaseSize div 2);
            setCursorPosWND(releaseDrawX, 61, DesktopHandle);
            writeStringExWND('INTERNAL ALPHA', Desktop_Colors, DesktopHandle);
        end;
        if StringEquals(asuro.RELEASE, 'a') then begin
            releaseSize:= StringSize('ALPHA');
            releaseDrawX:= 157 - (versionSize div 2) - (releaseSize div 2);
            setCursorPosWND(releaseDrawX, 61, DesktopHandle);
            writeStringExWND('ALPHA', Desktop_Colors, DesktopHandle);
        end;
        if StringEquals(asuro.RELEASE, 'b') then begin
            releaseSize:= StringSize('BETA');
            releaseDrawX:= 157 - (versionSize div 2) - (releaseSize div 2);
            setCursorPosWND(releaseDrawX, 61, DesktopHandle);
            writeStringExWND('BETA', Desktop_Colors, DesktopHandle);
        end;
    end;
end;

procedure Command_Colors(Params : PParamList);
var
    Command  : pchar;
    Fgs, Bgs : pchar;
    Fg, Bg   : uint32;
    exists   : boolean;

begin
    if ParamCount(Params) >= 3 then begin
        Command:= GetParam(0, Params);
        Fgs:= GetParam(1, Params);
        if (Fgs[0] = 'x') or (Fgs[0] = 'X') then Fg:= HexStringToInt(@Fgs[1]) else Fg:= StringToInt(Fgs);
        Bgs:= GetParam(2, Params);
        if (Bgs[0] = 'x') or (Bgs[0] = 'X') then Bg:= HexStringToInt(@Bgs[1]) else Bg:= StringToint(Bgs);
        exists:= false;
        if StringEquals(Command, 'background') then begin
            exists:= true;
            Desktop_Colors:= combinecolors(Fg, Bg);
        end;
        if StringEquals(Command, 'taskbar') then begin
            exists:= true;
            Takbar_Colors:= combinecolors(Fg, Bg);
        end;
        if StringEquals(Command, 'window') then begin
            exists:= true;
            setWindowColors(combinecolors(Fg, Bg));
        end;
        if StringEquals(Command, 'button') then begin
            exists:= true;
            Explore_Colors:= combinecolors(Fg, Bg);
        end;
        if exists then begin
            console.writestringWND('Component:', getTerminalHWND);
            console.writestringWND(Command, getTerminalHWND);
            console.writestringWND(' set to FG:', getTerminalHWND);
            console.writeHexWND(Fg, getTerminalHWND);
            console.writestringWND(' BG: ', getTerminalHWND);
            console.writehexlnWND(Bg, getTerminalHWND);
        end else begin
            console.writestringWND('Component: ', getTerminalHWND);
            console.writestringWND(Command, getTerminalHWND);
            console.writestringlnWND(' not found.', getTerminalHWND);
        end;
    end else begin
        console.writestringlnWND('Usage (Append "x" to a value to treat as Hex): ', getTerminalHWND);
        console.writestringlnWND('  colors background <foreground> <background>', getTerminalHWND);
        console.writestringlnWND('  colors taskbar <foreground> <background>', getTerminalHWND);
        console.writestringlnWND('  colors window <foreground> <background>', getTerminalHWND);
        console.writestringlnWND('  colors button  <foreground> <background>', getTerminalHWND);
    end;
end;

procedure Command_Background(Params : PParamList);
var
    p1 : PChar;

begin
    if ParamCount(Params) > 0 then begin
        p1:= GetParam(0, Params);
        if StringEquals(p1, 'show') then begin
            console.setWNDVisible(DesktopHandle, true);
            console.writestringlnWND('Background enabled.', getTerminalHWND);
        end else if StringEquals(p1, 'hide') then begin
            console.setWNDVisible(DesktopHandle, false);
            console.writestringlnWND('Background disabled.', getTerminalHWND);
        end else begin
            console.writestringlnWND('Invalid option.', getTerminalHWND);
        end;
    end else begin
        console.writestringlnWND('Invalid number of parameters.', getTerminalHWND);
    end;
end;

procedure init();
begin
    Takbar_Colors:= console.combinecolors($0000, $FFFF);
    Explore_Colors:= console.combinecolors($01C3, $07EE);
    Desktop_Colors:= console.combinecolors($FFFF, $34DB);

    DesktopHandle:= Console.newWindow(0, 0, 159, 63, 'DESKTOP');
    TaskBarHandle:= Console.newWindow(0, 63, 159, 1, 'SHELL');

    console.bordersEnabled(TaskBarHandle, false);
    console.setShellWindow(TaskBarHandle, false);

    console.bordersEnabled(DesktopHandle, false);
    console.setShellWindow(DesktopHandle, false);
    
    console.registerEventHandler(TaskBarHandle, EVENT_DRAW, void(@Draw));
    console.registerEventHandler(TaskBarHandle, EVENT_MOUSE_CLICK, void(@OnMouseClick));
    console.registerEventHandler(DesktopHandle, EVENT_DRAW, void(@onBaseDraw));

    terminal.registerCommand('BACKGROUND', @Command_Background, 'Hide/Show background - usage: BACKGROUND <hide/show>');
    terminal.registerCommand('COLORS', @Command_Colors, 'Set the desktop colors');
end;

end.