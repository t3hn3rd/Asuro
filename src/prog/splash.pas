unit splash;

interface

uses
    console, keyboard;

procedure init();

implementation

var
    Splash_Handle : HWND;
    Tick : uint32;
    Colors : uint32;
    Loops  : uint32 = 0;

procedure quit();
begin
    closeWindow(Splash_Handle);
    mouseEnabled(true);
end;

procedure keypress(info : TKeyInfo);
begin
    quit();
end;

procedure animate();
var
    Delta : uint32;

begin
    inc(Tick);
    Delta:= Tick div 100;
    Delta:= Delta mod 15;
    ClearWNDEx(Splash_Handle, Colors);
    if Delta > 1 then begin
        setCursorPosWND(45, 27, Splash_Handle);
        writestringExWND('       db           ', Colors, Splash_Handle);  
    end;
    if Delta > 2 then begin
        setCursorPosWND(45, 28, Splash_Handle);                                             
        writestringExWND('      d88b          ', Colors, Splash_Handle);
    end;
    if Delta > 3 then begin
        setCursorPosWND(45, 29, Splash_Handle);
        writestringExWND('     d8''`8b         ', Colors, Splash_Handle);
    end;
    if Delta > 4 then begin
        setCursorPosWND(45, 30, Splash_Handle);
        writestringExWND('    d8''  `8b      ,adPPYba,  88       88  8b,dPPYba,   ,adPPYba,', Colors, Splash_Handle);
    end;
    if Delta > 5 then begin
        setCursorPosWND(45, 31, Splash_Handle);
        writestringExWND('   d8YaaaaY8b     I8[    ""  88       88  88P''   "Y8  a8"     "8a', Colors, Splash_Handle);
    end;
    if Delta > 6 then begin
        setCursorPosWND(45, 32, Splash_Handle);
        writestringExWND('  d8""""""""8b     `"Y8ba,   88       88  88          8b       d8', Colors, Splash_Handle);  
    end;
    if Delta > 7 then begin
        setCursorPosWND(45, 33, Splash_Handle);
        writestringExWND(' d8''        `8b   aa    ]8I  "8a,   ,a88  88          "8a,   ,a8"', Colors, Splash_Handle);  
    end;
    if Delta > 8 then begin
        setCursorPosWND(45, 34, Splash_Handle);
        writestringExWND('d8''          `8b  `"YbbdP"''   `"YbbdP''Y8  88           `"YbbdP"''', Colors, Splash_Handle);
    end;
    if Tick > 2100 then begin 
        quit();
    end;
end;

procedure init();
begin
    Colors:= combineColors($FFFF, $5CDE);
    Splash_Handle:= newWindow(0, 0, 159, 63, 'SPLASH');
    SetShellWindow(Splash_Handle, false);
    BordersEnabled(Splash_Handle, false);
    registerEventHandler(Splash_Handle, EVENT_DRAW, void(@animate));
    registerEventHandler(Splash_Handle, EVENT_KEY_PRESSED, void(@keypress));
    mouseEnabled(false);
end;

end.