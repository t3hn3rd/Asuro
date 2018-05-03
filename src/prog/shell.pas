unit shell;

interface

uses
    Console, RTC, terminal, strings;

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
begin
    clearWNDEx(DesktopHandle, Desktop_Colors);
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
    Desktop_Colors:= console.combinecolors($01C3, $34DB);

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
end;

end.