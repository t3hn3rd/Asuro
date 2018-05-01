unit shell;

interface

uses
    Console, RTC, terminal;

procedure init();

implementation

var
    Handle : HWND = 0;
    Colors : uint32;
    Explore_Colors : uint32;

procedure Draw();
var
    DateTime : TDateTime;
    i : uint32;
    s : pchar;

begin
     DateTime:= getDateTime;

     console.clearWNDEx(Handle, colors);

     console.setCursorPosWND(0, 0, Handle);
     console.writeStringExWND(' TERMINAL ', Explore_Colors, Handle);
     console.writeCharExWND(#6, Colors, Handle);

     for i:=0 to 9 do begin
        s:= getWindowName(i);
        if s <> nil then begin
            console.writeStringExWND(s, Colors, Handle);
            console.writeCharExWND(' ', Colors, Handle);
            console.writeCharExWND(#6, Colors, Handle);
        end;
     end;

     console.setCursorPosWND(150, 0, Handle);
     if DateTime.Hours < 10 then writeIntExWND(0, Colors, Handle);
     writeIntExWND(DateTime.Hours, Colors, Handle);
     writeStringExWND(':', Colors, Handle);
     if DateTime.Minutes < 10 then writeIntExWND(0, Colors, Handle);
     writeIntExWND(DateTime.Minutes, Colors, Handle);
     writeStringExWND(':', Colors, Handle);
     if DateTime.Seconds < 10 then writeIntExWND(0, Colors, Handle);
     writeIntExWND(DateTime.Seconds, Colors, Handle);
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
    clearWNDEx(0, console.combinecolors($01C3, $A55F));
end;

procedure init();
begin
    colors:= console.combinecolors($0000, $FFFF);
    Explore_Colors:= console.combinecolors($01C3, $07EE);
    Handle:= Console.newWindow(0, 63, 159, 1, 'SHELL');
    console.bordersEnabled(Handle, false);
    //console.clearWNDEx(Handle, colors);
    console.setShellWindow(Handle, false);
    console.registerEventHandler(Handle, EVENT_DRAW, void(@Draw));
    console.registerEventHandler(Handle, EVENT_MOUSE_CLICK, void(@OnMouseClick));
    console.registerEventHandler(0, EVENT_DRAW, void(@onBaseDraw));
end;

end.