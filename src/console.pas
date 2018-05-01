{ ************************************************
  * Asuro
  * Unit: console
  * Description: Basic Console Output
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit console;

interface

uses
     util, 
     bios_data_area,
     multiboot,
     fonts,
     tracer;

type
    TColor = ( Black   = $0,
               Blue    = $1,
               Green   = $2,
               Aqua    = $3,
               Red     = $4,
               Purple  = $5,
               Yellow  = $6,
               White   = $7,
               Gray    = $8,
               lBlue   = $9,
               lGreen  = $A,
               lAqua   = $B,
               lRed    = $C,
               lPurple = $D,
               lYellow = $E,
               lWhite  = $F );

    TEventType = ( EVENT_DRAW,
                   EVENT_MOUSE_CLICK,
                   EVENT_MOUSE_MOVE,
                   EVENT_MOUSE_DOWN,
                   EVENT_MOUSE_UP,
                   EVENT_KEY_PRESSED,
                   EVENT_CLOSE,
                   EVENT_MINIMIZE );

procedure init();
procedure clear();
procedure setdefaultattribute(attribute : uint32);

procedure disable_cursor;

procedure writechar(character : char);
procedure writecharln(character : char);
procedure writecharex(character : char; attributes: uint32);
procedure writecharlnex(character : char; attributes: uint32);

procedure Output(identifier : PChar; str : PChar);
procedure Outputln(identifier : PChar; str : PChar);

procedure writestring(str: PChar);
procedure writestringln(str: PChar);
procedure writestringex(str: PChar; attributes: uint32);
procedure writestringlnex(str: PChar; attributes: uint32);

procedure writeint(i: Integer);
procedure writeintln(i: Integer);
procedure writeintex(i: Integer; attributes: uint32);
procedure writeintlnex(i: Integer; attributes: uint32);

procedure writeword(i: DWORD);
procedure writewordln(i: DWORD);
procedure writewordex(i: DWORD; attributes: uint32);
procedure writewordlnex(i: DWORD; attributes: uint32);

procedure writehexpair(b : uint8);
procedure writehex(i: DWORD);
procedure writehexln(i: DWORD);
procedure writehexex(i : DWORD; attributes: uint32);
procedure writehexlnex(i: DWORD; attributes: uint32);

procedure writebin8(b : uint8);
procedure writebin8ln(b : uint8);
procedure writebin8ex(b : uint8; attributes: uint32);
procedure writebin8lnex(b : uint8; attributes: uint32);

procedure writebin16(b : uint16);
procedure writebin16ln(b : uint16);
procedure writebin16ex(b : uint16; attributes: uint32);
procedure writebin16lnex(b : uint16; attributes: uint32);

procedure writebin32(b : uint32);
procedure writebin32ln(b : uint32);
procedure writebin32ex(b : uint32; attributes: uint32);
procedure writebin32lnex(b : uint32; attributes: uint32);

procedure backspace;

function combinecolors(Foreground, Background : uint16) : uint32;

procedure _increment_x();
procedure _increment_y();
procedure _safeincrement_y();
procedure _safeincrement_x();
procedure _newline();

{ WND Specific }

procedure clearWND(WND : uint32);
procedure clearWNDEx(WND : uint32; attributes : uint32);

procedure writecharWND(character : char; WND : uint32);
procedure writecharlnWND(character : char; WND : uint32);
procedure writecharexWND(character : char; attributes: uint32; WND : uint32);
procedure writecharlnexWND(character : char; attributes: uint32; WND : uint32);

procedure OutputWND(identifier : PChar; str : PChar; WND : uint32);
procedure OutputlnWND(identifier : PChar; str : PChar; WND : uint32);

procedure writestringWND(str: PChar; WND : uint32);
procedure writestringlnWND(str: PChar; WND : uint32);
procedure writestringexWND(str: PChar; attributes: uint32; WND : uint32);
procedure writestringlnexWND(str: PChar; attributes: uint32; WND : uint32);

procedure writeintWND(i: Integer; WND : uint32);
procedure writeintlnWND(i: Integer; WND : uint32);
procedure writeintexWND(i: Integer; attributes: uint32; WND : uint32);
procedure writeintlnexWND(i: Integer; attributes: uint32; WND : uint32);

procedure writewordWND(i: DWORD; WND : uint32);
procedure writewordlnWND(i: DWORD; WND : uint32);
procedure writewordexWND(i: DWORD; attributes: uint32; WND : uint32);
procedure writewordlnexWND(i: DWORD; attributes: uint32; WND : uint32);

procedure writehexpairWND(b : uint8; WND : uint32);
procedure writehexWND(i: DWORD; WND : uint32);
procedure writehexlnWND(i: DWORD; WND : uint32);
procedure writehexexWND(i : DWORD; attributes: uint32; WND : uint32);
procedure writehexlnexWND(i: DWORD; attributes: uint32; WND : uint32);

procedure writebin8WND(b : uint8; WND : uint32);
procedure writebin8lnWND(b : uint8; WND : uint32);
procedure writebin8exWND(b : uint8; attributes: uint32; WND : uint32);
procedure writebin8lnexWND(b : uint8; attributes: uint32; WND : uint32);

procedure writebin16WND(b : uint16; WND : uint32);
procedure writebin16lnWND(b : uint16; WND : uint32);
procedure writebin16exWND(b : uint16; attributes: uint32; WND : uint32);
procedure writebin16lnexWND(b : uint16; attributes: uint32; WND : uint32);

procedure writebin32WND(b : uint32; WND : uint32);
procedure writebin32lnWND(b : uint32; WND : uint32);
procedure writebin32exWND(b : uint32; attributes: uint32; WND : uint32);
procedure writebin32lnexWND(b : uint32; attributes: uint32; WND : uint32);

procedure backspaceWND(WND : uint32);
procedure setCursorPosWND(x : uint32; y : uint32; WND : HWND);

procedure _increment_x_WND(WND : uint32);
procedure _increment_y_WND(WND : uint32);
procedure _safeincrement_y_WND(WND : uint32);
procedure _safeincrement_x_WND(WND : uint32);
procedure _newlineWND(WND : uint32);

{ Drawing }

procedure outputChar(c : char; x : uint8; y : uint8; fgcolor : uint16; bgcolor : uint16);
procedure outputCharToScreenSpace(c : char; x : uint32; y : uint32; fgcolor : uint16);
procedure outputCharTransparent(c : char; x : uint8; y : uint8; fgcolor : uint16);

function  getPixel(x : uint32; y : uint32) : uint16;
procedure drawPixel(x : uint32; y : uint32; color : uint16);
function  getPixel32(x : uint32; y : uint32) : uint32;
procedure drawPixel32(x : uint32; y : uint32; pixel : uint32);
function  getPixel64(x : uint32; y : uint32) : uint64;
procedure drawPixel64(x : uint32; y : uint32; pixel : uint64);

{ Windows Methods }

procedure setMousePosition(x : uint32; y : uint32);
procedure redrawWindows;
procedure toggleWNDVisible(WND : uint32);
procedure setWNDVisible(WND : uint32; visible : boolean);
procedure closeAllWindows;
function  newWindow(x : uint32; y : uint32; Width : uint32; Height : uint32; Title : PChar) : HWND;
function  registerEventHandler(WND : HWND; Event : TEventType; Handler : void) : boolean;
procedure forceQuitAll;
procedure closeWindow(WND : HWND);
procedure bordersEnabled(WND : HWND; enabled : boolean);
procedure SetShellWindow(WND : HWND; b : boolean);
function  getWindowName(WND : HWND) : pchar;

procedure _MouseDown();
procedure _MouseUp();
procedure _MouseClick(left : boolean);

implementation

uses
    lmemorymanager, strings, keyboard, serial, terminal;

const
    MAX_WINDOWS = 255;
    DefaultWND  = 0;

type
    TConsoleProperties = record
      Default_Attribute : uint32;
    end;

    TCharacter = bitpacked record
      Character  : Char;
      attributes : uint32;
      visible    : boolean;
    end;
    PCharacter = ^TCharacter;

    TVideoMemory = Array[0..1999] of TCharacter;
    PVideoMemory = ^TVideoMemory;

    TMask = Array[0..63] of Array[0..159] of uint32;

    T2DVideoMemory = Array[0..63] of Array[0..159] of TCharacter;
    P2DVideoMemory = ^T2DVideoMemory;

    TMouseCoord = record
        X : sint32;
        Y : sint32;
    end;

    TCoord = record
      X : Byte;
      Y : Byte;
    end;

    TDrawHook       = procedure();
    TMouseClickHook = procedure(x : uint32; y : uint32; left : boolean);
    TMouseMoveHook  = procedure(x : uint32; y : uint32);
    TMouseDownHook  = procedure(x : uint32; y : uint32);
    TMouseUpHook    = procedure(x : uint32; y : uint32);
    TKeyPressedHook = procedure(info : TKeyInfo);
    TCloseHook      = procedure();
    TMinimizeHook   = procedure();

    THooks = record
        OnDraw       : TDrawHook;
        OnMouseClick : TMouseClickHook;
        OnMouseMove  : TMouseMoveHook;
        OnMouseDown  : TMouseDownHook;
        OnMouseUp    : TMouseUpHook;
        OnKeyPressed : TKeyPressedHook;
        OnClose      : TCloseHook;
        OnMinimize   : TMinimizeHook;
    end;

    TWindow = record
        visible     : boolean;
        buffer      : T2DVideoMemory;
        row_dirty   : Array[0..63] of Boolean;
        WND_X       : uint32;
        WND_Y       : uint32;
        WND_W       : uint32;
        WND_H       : uint32;
        Cursor      : TCoord;
        WND_NAME    : PChar;
        Hooks       : THooks;
        Closed      : boolean;
        Border      : boolean;
        ShellWND    : boolean;
    end;
    PWindow = ^TWindow;

    TWindows = Array[0..MAX_WINDOWS-1] of PWindow;

    TWindowManager = record
        Windows     : TWindows;
        MousePos    : TMouseCoord;
        MousePrev   : TMouseCoord;
    end;

    TMouseDirt = record
        TopLeft     : TMouseCoord;
        BottomRight : TMouseCoord;
    end;

var
   Console_Properties : TConsoleProperties; //Generic Properties
   Console_Real       : T2DVideoMemory;     //The real state of the Console/TUI
   Console_Matrix     : T2DVideoMemory;     //The next buffer to be written
   Console_Cursor     : TCoord;             //The text cursor position
   WindowManager      : TWindowManager;     //Window Manager
   Ready              : Boolean = false;    //Is the unit ready for use?
   MouseDrawActive    : Boolean = false;    //Is the Mouse currently being updated?
   mouse_dirt         : TMouseDirt;         //Character Cell(s) the mouse occupies, these need to be rewritten on mouse move.
   Window_Border      : TCharacter;
   Default_Char       : TCharacter;
   WindowTitleMask    : TMask;
   WindowMask         : TMask;
   MouseDown          : Boolean;
   WindowMovePos      : TMouseCoord;
   MovingWindow       : uint32;


procedure _MouseDown();
begin
    MouseDown:= true;
end;

procedure _MouseUp();
begin
    MouseDown:= false;
end;

procedure _MouseClick(left : boolean);
begin

end;

function getWindowName(WND : HWND) : pchar;
var
    Window : PWindow;

begin
    getWindowName:= nil;
    Window:= WindowManager.Windows[WND];
    if Window <> nil then begin
        if Window^.ShellWND then begin
            getWindowName:= Window^.WND_NAME;
        end;
    end;
end;

procedure SetShellWindow(WND : HWND; b : boolean);
var
    Window : PWindow;

begin
    Window:= WindowManager.Windows[WND];
    if Window <> nil then begin
        Window^.ShellWND:= b;
    end;
end;

procedure bordersEnabled(WND : HWND; enabled : boolean);
var
    Window : PWindow;

begin
    Window:= WindowManager.Windows[WND];
    if Window <> nil then begin
        Window^.Border:= enabled;
    end;
end;

procedure setCursorPosWND(x : uint32; y : uint32; WND : HWND);
var
    Window : PWindow;

begin
     Window:= WindowManager.Windows[WND];
     if Window <> nil then begin
        while x > 159 do dec(x);
        while y > 63 do dec(y);
        Window^.Cursor.x:= x;
        Window^.Cursor.y:= y;
     end;
end;

procedure setWindowPosition(WND : HWND; x, y : sint32);
var
    Window : PWindow;
    nx, ny : sint32;

begin
    Window:= WindowManager.Windows[WND];
    If Window <> nil then begin
        nx:= x;
        ny:= y;
        if Window^.Border then begin
            if nx < 2 then nx:= 2;
            if ny < 1 then ny:= 1;
            while (nx + Window^.WND_W + 2) > 159 do begin
                dec(nx);
            end;
            while (ny + Window^.WND_H + 1) > 63 do begin
                dec(ny);
            end;
        end else begin
            if nx < 0 then nx:= 0;
            if ny < 0 then ny:= 0;
            while (nx + Window^.WND_W) > 159 do begin
                dec(nx);
            end;
            while (ny + Window^.WND_H) > 63 do begin
                dec(ny);
            end;
        end;
        Window^.WND_X:= nx;
        Window^.WND_Y:= ny;
    end;
end;

function registerEventHandler(WND : HWND; Event : TEventType; Handler : void) : boolean;
begin
    registerEventHandler:= true;
    if WindowManager.Windows[WND] <> nil then begin
        case Event of
            EVENT_DRAW        : WindowManager.Windows[WND]^.Hooks.OnDraw:=       TDrawHook(Handler);
            EVENT_MOUSE_CLICK : WindowManager.Windows[WND]^.Hooks.OnMouseClick:= TMouseClickHook(Handler);
            EVENT_MOUSE_MOVE  : WindowManager.Windows[WND]^.Hooks.OnMouseMove:=  TMouseMoveHook(Handler);
            EVENT_MOUSE_DOWN  : WindowManager.Windows[WND]^.Hooks.OnMouseDown:=  TMouseDownHook(Handler);
            EVENT_MOUSE_UP    : WindowManager.Windows[WND]^.Hooks.OnMouseUp:=    TMouseUpHook(Handler);
            EVENT_KEY_PRESSED : WindowManager.Windows[WND]^.Hooks.OnKeyPressed:= TKeyPressedHook(Handler);
            EVENT_CLOSE       : WindowManager.Windows[WND]^.Hooks.OnClose:=      TCloseHook(Handler);
            EVENT_MINIMIZE    : WindowManager.Windows[WND]^.Hooks.OnMinimize:=   TMinimizeHook(Handler);
            else registerEventHandler:= false;
        end;
    end else begin
        registerEventHandler:= false;
    end;
end;

function newWindow(x : uint32; y : uint32; Width : uint32; Height : uint32; Title : PChar) : HWND;
var
    idx : uint32;
    WND : PWindow;

begin
    newWindow:= 0;
    for idx:=1 to MAX_WINDOWS-1 do begin
        if WindowManager.Windows[idx] = nil then begin
            newWindow:= idx;
            break;
        end;
    end;
    if newWindow <> 0 then begin
        WND:= PWindow(kalloc(sizeof(TWindow)));
        WND^.WND_NAME:= StringCopy(Title);
        WND^.WND_X:= x;
        WND^.WND_Y:= y;
        WND^.WND_W:= Width;
        WND^.WND_H:= Height;
        WND^.Cursor.x:= 0;
        WND^.Cursor.y:= 0;
        WND^.visible:= true;
        WND^.Closed:= false;
        WND^.Border:= true;
        WND^.ShellWND:= true;
        WND^.Hooks.OnDraw       := nil;
        WND^.Hooks.OnMouseClick := nil;
        WND^.Hooks.OnMouseMove  := nil;
        WND^.Hooks.OnMouseDown  := nil;
        WND^.Hooks.OnMouseUp    := nil;
        WND^.Hooks.OnKeyPressed := nil;
        WND^.Hooks.OnClose      := nil;
        WND^.Hooks.OnMinimize   := nil;
        WindowManager.Windows[newWindow]:= WND;
    end;
end;

procedure forceQuitAll;
var
    i : uint32;
    WND : PWindow;

begin
    for i:=1 to MAX_WINDOWS-1 do begin
        if WindowManager.Windows[i] <> nil then begin
            WND:= WindowManager.Windows[i];
            WindowManager.Windows[i]:= nil;
            kfree(void(WND^.WND_NAME));
            kfree(void(WND));
        end;
    end;
end;


procedure _closeWindow(WND : HWND);
var
    WNDCopy : PWindow;

begin
    if WindowManager.Windows[WND] <> nil then begin
        WNDCopy:= WindowManager.Windows[WND];
        WindowManager.Windows[WND]:= nil;
        if WNDCopy^.Hooks.OnClose <> nil then WNDCopy^.Hooks.OnClose();
        kfree(void(WNDCopy^.WND_NAME));
        kfree(void(WNDCopy));
    end;
end;

procedure closeWindow(WND : HWND);
begin
    if WindowManager.Windows[WND] <> nil then begin
        WindowManager.Windows[WND]^.Closed:= True;
    end;
end;

procedure closeAllWindows;
var
    i : uint32;

begin
    for i:=1 to MAX_WINDOWS-1 do begin
        setWNDVisible(i, false);
    end;
end;

procedure setWNDVisible(WND : uint32; visible : boolean);
begin
    if WindowManager.Windows[WND] <> nil then begin
        WindowManager.Windows[WND]^.visible:= visible;
    end;
end;

procedure toggleWNDVisible(WND : uint32);
begin
    if WindowManager.Windows[DefaultWND] <> nil then begin
        WindowManager.Windows[WND]^.visible:= not WindowManager.Windows[WND]^.visible;
    end;
end;

function MouseYToTile(Y : uint32) : uint32;
begin
    MouseYToTile:= Y div 16;
end;

function MouseXToTile(X : uint32) : uint32;
begin
    MouseXToTile:= X div 8;
end;

procedure drawMouse;
var
    x, y       : uint32;
    MX, MY     : uint32;

begin
    MouseDrawActive:= true;
    MX:= WindowManager.MousePos.X;
    MY:= WindowManager.MousePos.Y;
    WindowManager.MousePrev.x:= MX;
    WindowManager.MousePrev.y:= MY;
    mouse_dirt.TopLeft.x:= (MX div 8) - 2;
    mouse_dirt.TopLeft.y:= (MY div 16) - 2;
    mouse_dirt.BottomRight.x:= (MX div 8) + 2;
    mouse_dirt.BottomRight.y:= (MY div 16) + 2;
    if mouse_dirt.TopLeft.x < 0 then mouse_dirt.TopLeft.x:= 0;
    if mouse_dirt.TopLeft.y < 0 then mouse_dirt.TopLeft.y:= 0;
    if mouse_dirt.BottomRight.x > 159 then mouse_dirt.BottomRight.x:= 159;
    if mouse_dirt.BottomRight.y > 63 then mouse_dirt.BottomRight.y:= 63;
    MouseDrawActive:= false;
end;

procedure redrawMatrix;
var
    x, y, w: uint32;

begin
    if (WindowManager.MousePos.x <> WindowManager.MousePrev.x) OR (WindowManager.MousePos.y <> WindowManager.MousePrev.y) then begin
        for y:=mouse_dirt.TopLeft.y to mouse_dirt.BottomRight.y do begin
            for x:=mouse_dirt.TopLeft.x to mouse_dirt.BottomRight.x do begin
                Console_Real[y][x].character:= char(1);
            end; 
        end;
        drawMouse;
    end;
    for y:=0 to 63 do begin
        for x:=0 to 159 do begin
            if (Console_Matrix[y][x].character <> Console_Real[y][x].character) or (Console_Matrix[y][x].attributes <> Console_Real[y][x].attributes) then begin
                OutputChar(Console_Matrix[y][x].Character, x, y, Console_Matrix[y][x].Attributes SHR 16, Console_Matrix[y][x].Attributes AND $FFFF);
                Console_Real[y][x]:= Console_Matrix[y][x];
            end;
        end;
    end;
    outputCharToScreenSpace(char(0), WindowManager.MousePrev.x, WindowManager.MousePrev.y, $FFFF);
end;

procedure setMousePosition(x : uint32; y : uint32);
begin
    if MouseDrawActive then exit;
    WindowManager.MousePos.X:= x;
    WindowManager.MousePos.Y:= y;
end;

procedure redrawWindows;
var
    x, y, w : uint32;
    WXL, WYL : sint32;
    WXR, WYR : sint32;
    STRC : uint32;
    MIDP, STARTP : uint32;
    deltax, deltay : sint32;

begin
    for y:=0 to 63 do begin
        for x:=0 to 159 do begin
            Console_Matrix[y][x]:= Default_Char;
        end;
    end;
    if MouseDown then begin
        if MovingWindow = 0 then begin
            MovingWindow:= WindowTitleMask[MouseYToTile(WindowManager.MousePrev.Y)][MouseXToTile(WindowManager.MousePrev.X)];
            if MovingWindow <> 0 then begin
                WindowMovePos.x:= MouseXToTile(WindowManager.MousePrev.X);
                WindowMovePos.y:= MouseYToTile(WindowManager.MousePrev.Y);
            end;
        end;
        if MovingWindow <> 0 then begin
            if WindowManager.Windows[MovingWindow] <> nil then begin
                deltax:= WindowMovePos.x - MouseXToTile(WindowManager.MousePrev.X);
                deltay:= WindowMovePos.y - MouseYToTile(WindowManager.MousePrev.Y);
                WindowMovePos.x:= MouseXToTile(WindowManager.MousePrev.X);
                WindowMovePos.y:= MouseYToTile(WindowManager.MousePrev.Y);
                setWindowPosition(MovingWindow, WindowManager.Windows[MovingWindow]^.WND_X - deltax, WindowManager.Windows[MovingWindow]^.WND_Y - deltay);
                //WindowManager.Windows[MovingWindow]^.WND_X:= WindowManager.Windows[MovingWindow]^.WND_X - deltax;
                //WindowManager.Windows[MovingWindow]^.WND_Y:= WindowManager.Windows[MovingWindow]^.WND_Y - deltay;
            end;
        end;
    end else begin
        MovingWindow:= 0;
    end;
    for w:=0 to MAX_WINDOWS-1 do begin
        if WindowManager.Windows[w] <> nil then begin
            if w <> 0 then begin
                if WindowManager.Windows[w]^.Hooks.OnDraw <> nil then WindowManager.Windows[w]^.Hooks.OnDraw();
            end;
            If WindowManager.Windows[w]^.visible then begin
                if WindowManager.Windows[w]^.Border then begin
                    WXL:= WindowManager.Windows[w]^.WND_X - 1;
                    WYL:= WindowManager.Windows[w]^.WND_Y - 1;
                    WXR:= WindowManager.Windows[w]^.WND_X + WindowManager.Windows[w]^.WND_W + 1;
                    WYR:= WindowManager.Windows[w]^.WND_Y + WindowManager.Windows[w]^.WND_H + 1;
                    for y:=WYL to WYR do begin
                        Console_Matrix[y][WXL]:= Window_Border;
                        Console_Matrix[y][WXL-1]:= Window_Border;
                        Console_Matrix[y][WXR]:= Window_Border;
                        Console_Matrix[y][WXR+1]:= Window_Border;
                        Console_Real[y][WXL].Character:= char(3);
                        Console_Real[y][WXL-1].Character:= char(3);
                        Console_Real[y][WXR].Character:= char(3);
                        Console_Real[y][WXR+1].Character:= char(3);
                    end;
                    STRC:= 0;
                    MIDP:= (WXR + WXL) div 2;
                    STARTP:= MIDP - (StringSize(WindowManager.Windows[w]^.WND_NAME) div 2) - 1;
                    for x:=WXL to WXR do begin
                        Console_Matrix[WYL][x]:= Window_Border;
                        WindowTitleMask[WYL][x]:= w;
                        if (x >= STARTP) and (STRC < StringSize(WindowManager.Windows[w]^.WND_NAME)) then begin
                            Console_Matrix[WYL][x].character:= WindowManager.Windows[w]^.WND_NAME[STRC];
                            inc(STRC);
                        end;
                        if x = WXR then begin
                            Console_Matrix[WYL][x].character:= 'x';
                        end;
                        Console_Matrix[WYR][x]:= Window_Border;
                        Console_Real[WYL][x].Character:= char(3);
                        Console_Real[WYR][x].Character:= char(3);
                    end;
                end;
                for y:=WindowManager.Windows[w]^.WND_Y to WindowManager.Windows[w]^.WND_Y + WindowManager.Windows[w]^.WND_H do begin
                    if y > 63 then break;
                    for x:=WindowManager.Windows[w]^.WND_X to WindowManager.Windows[w]^.WND_X + WindowManager.Windows[w]^.WND_W do begin
                        if x > 159 then break;
                        Console_Matrix[y][x]:= WindowManager.Windows[w]^.buffer[y - WindowManager.Windows[w]^.WND_Y][x - WindowManager.Windows[w]^.WND_X];
                        WindowTitleMask[y][x]:= 0;
                        WindowMask[y][x]:= w;
                    end;
                end;
            end;
            if WindowManager.Windows[w]^.Closed then _closeWindow(w);
        end;
    end;
    redrawMatrix;
end;

procedure initWindows;
var
    x, y, w : uint32;
    WND : PWindow;

begin
    Default_Char.Character:= ' ';
    Default_Char.attributes:= Console_Properties.Default_Attribute;
    Default_Char.visible:= true;

    Window_Border.Character:= ' ';
    Window_Border.Attributes:= $0000FFFF;
    Window_Border.visible:= true;

    For w:=0 to MAX_WINDOWS-1 do begin
        WindowManager.Windows[w]:= nil;
    end;

    WND:= PWindow(kalloc(sizeof(TWindow)));
    WND^.WND_NAME:= 'Asuro';
    WND^.WND_X:= 0;
    WND^.WND_Y:= 0;
    WND^.WND_W:= 159;
    WND^.WND_H:= 63;
    WND^.Cursor.x:= 0;
    WND^.Cursor.y:= 0;
    WND^.visible:= true;
    WND^.Closed:= false;
    WND^.Border:= false;
    WND^.ShellWND:= false;
    WindowManager.Windows[0]:= WND;
end;

function getPixel(x : uint32; y : uint32) : uint16;
var
    dest : puint16;

begin
    if not ready then exit;
    dest:= puint16(multibootinfo^.framebuffer_addr);
    dest:= dest + (y * 1280) + x;
    getPixel:= dest^;
end;

procedure drawPixel(x : uint32; y : uint32; color : uint16);
var
    dest : puint16;

begin
    if not ready then exit;
    dest:= puint16(multibootinfo^.framebuffer_addr);
    dest:= dest + (y * 1280) + x;
    dest^:= color;
end;

function getPixel32(x : uint32; y : uint32) : uint32;
var
    dest : puint16;
    dest32 : puint32;

begin
    if not ready then exit;
    dest:= puint16(multibootinfo^.framebuffer_addr);
    dest:= dest + (y * 1280) + x;
    dest32:= puint32(dest);
    getPixel32:= dest32[0];
end;

procedure drawPixel32(x : uint32; y : uint32; pixel : uint32);
var
    dest : puint16;
    dest32 : puint32;

begin
    if not ready then exit;
    dest:= puint16(multibootinfo^.framebuffer_addr);
    dest:= dest + (y * 1280) + x;
    dest32:= puint32(dest);
    dest32[0]:= pixel;
end;

function getPixel64(x : uint32; y : uint32) : uint64;
var
    dest : puint16;
    dest64 : puint64;

begin
    if not ready then exit;
    dest:= puint16(multibootinfo^.framebuffer_addr);
    dest:= dest + (y * 1280) + x;
    dest64:= puint64(dest);
    getPixel64:= dest64^;
end;

procedure drawPixel64(x : uint32; y : uint32; pixel : uint64);
var
    dest : puint16;
    dest64 : puint64;

begin
    if not ready then exit;
    dest:= puint16(multibootinfo^.framebuffer_addr);
    dest:= dest + (y * 1280) + x;
    dest64:= puint64(dest);
    dest64^:= pixel;
end;

procedure outputCharToScreenSpace(c : char; x : uint32; y : uint32; fgcolor : uint16);
var
    dest : puint16;
    dest32 : puint32;
    fgcolor32, bgcolor32 : uint32;
    mask : puint32;
    i : uint32;

begin
    if not ready then exit;
    fgcolor32:= fgcolor OR (fgcolor SHL 16);
    mask:= puint32(@Std_Mask[uint32(c) * (16 * 8)]);
    dest:= puint16(multibootinfo^.framebuffer_addr);
    //dest:= puint16(windowmanager.getBuffer(0));
    dest:= dest + (y * 1280) + x;
    dest32:= puint32(dest);
    for i:=0 to 15 do begin
        dest32[(i*640)+0]:= (dest32[(i*640)+0] AND NOT(mask[(i*4)+0])) OR (fgcolor32 AND mask[(i*4)+0]);
        dest32[(i*640)+1]:= (dest32[(i*640)+1] AND NOT(mask[(i*4)+1])) OR (fgcolor32 AND mask[(i*4)+1]);
        dest32[(i*640)+2]:= (dest32[(i*640)+2] AND NOT(mask[(i*4)+2])) OR (fgcolor32 AND mask[(i*4)+2]);
        dest32[(i*640)+3]:= (dest32[(i*640)+3] AND NOT(mask[(i*4)+3])) OR (fgcolor32 AND mask[(i*4)+3]);
    end;
    //windowmanager.redraw;
end;

procedure outputCharTransparent(c : char; x : uint8; y : uint8; fgcolor : uint16);
var
    dest : puint16;
    dest32 : puint32;
    fgcolor32, bgcolor32 : uint32;
    mask : puint32;
    i : uint32;

begin
    if not ready then exit;
    fgcolor32:= fgcolor OR (fgcolor SHL 16);
    mask:= puint32(@Std_Mask[uint32(c) * (16 * 8)]);
    dest:= puint16(multibootinfo^.framebuffer_addr);
    //dest:= puint16(windowmanager.getBuffer(0));
    dest:= dest + (y*(1280 * 16)) + (x * 8);
    dest32:= puint32(dest);
    for i:=0 to 15 do begin
        dest32[(i*640)+0]:= (dest32[(i*640)+0] AND NOT(mask[(i*4)+0])) OR (fgcolor32 AND mask[(i*4)+0]);
        dest32[(i*640)+1]:= (dest32[(i*640)+1] AND NOT(mask[(i*4)+1])) OR (fgcolor32 AND mask[(i*4)+1]);
        dest32[(i*640)+2]:= (dest32[(i*640)+2] AND NOT(mask[(i*4)+2])) OR (fgcolor32 AND mask[(i*4)+2]);
        dest32[(i*640)+3]:= (dest32[(i*640)+3] AND NOT(mask[(i*4)+3])) OR (fgcolor32 AND mask[(i*4)+3]);
    end;
    //windowmanager.redraw;
end;

procedure outputChar(c : char; x : uint8; y : uint8; fgcolor : uint16; bgcolor : uint16);
var
    dest : puint16;
    dest32 : puint32;
    fgcolor32, bgcolor32 : uint32;
    mask : puint32;
    i : uint32;

begin
    if not ready then exit;
    fgcolor32:= fgcolor OR (fgcolor SHL 16);
    bgcolor32:= bgcolor OR (bgcolor SHL 16);
    mask:= puint32(@Std_Mask[uint32(c) * (16 * 8)]);
    dest:= puint16(multibootinfo^.framebuffer_addr);
    //dest:= puint16(windowmanager.getBuffer(0));
    dest:= dest + (y*(1280 * 16)) + (x * 8);
    dest32:= puint32(dest);
    for i:=0 to 15 do begin
        dest32[(i*640)+0]:= (bgcolor32 AND NOT(mask[(i*4)+0])) OR (fgcolor32 AND mask[(i*4)+0]);
        dest32[(i*640)+1]:= (bgcolor32 AND NOT(mask[(i*4)+1])) OR (fgcolor32 AND mask[(i*4)+1]);
        dest32[(i*640)+2]:= (bgcolor32 AND NOT(mask[(i*4)+2])) OR (fgcolor32 AND mask[(i*4)+2]);
        dest32[(i*640)+3]:= (bgcolor32 AND NOT(mask[(i*4)+3])) OR (fgcolor32 AND mask[(i*4)+3]);
    end;
    //windowmanager.redraw;
end;

procedure disable_cursor;
begin
     outb($3D4, $0A);
     outb($3D5, $20);
end;

procedure init(); [public, alias: 'console_init'];
var
   fb: puint32;

Begin
     fb:= puint32(uint32(multibootinfo^.framebuffer_addr));
     kpalloc(uint32(fb));
     initWindows;
     Console_Properties.Default_Attribute:= console.combinecolors($FFFF, $0000);
     console.clear();
     Ready:= True;
end;

{ Default Console Write Functions }

procedure clear(); [public, alias: 'console_clear'];
var
   x,y: Byte;

begin
     if WindowManager.Windows[DefaultWND] <> nil then begin
        for y:=0 to 63 do begin
            for x:=0 to 159 do begin
                WindowManager.Windows[DefaultWND]^.Buffer[y][x].Character:= ' ';
                WindowManager.Windows[DefaultWND]^.Buffer[y][x].Attributes:= Console_Properties.Default_Attribute;
                WindowManager.Windows[DefaultWND]^.row_dirty[y]:= true;
                //Console_Matrix[y][x].Character:= ' ';
                //Console_Matrix[y][x].Attributes:= Console_Properties.Default_Attribute;
                //OutputChar(Console_Matrix[y][x].Character, x, y, Console_Matrix[y][x].Attributes SHR 16, Console_Matrix[y][x].Attributes AND $FFFF);
            end;
        end;
        WindowManager.Windows[DefaultWND]^.Cursor.X:= 0;
        WindowManager.Windows[DefaultWND]^.Cursor.Y:= 0;
        //redrawWindows;
     end;
     //Console_Cursor.X:= 0;
     //Console_Cursor.Y:= 0;
end;

procedure writebin8ex(b : uint8; attributes: uint32);
var
   Mask : PMask;
   i    : uint8;

begin
     Mask:= PMask(@b);
     for i:=0 to 7 do begin
        If Mask^[7-i] then writecharex('1', attributes) else writecharex('0', attributes);
     end;
end;

procedure writebin16ex(b : uint16; attributes: uint32);
var
   Mask : PMask;
   i,j  : uint8;

begin
     for j:=1 downto 0 do begin
        Mask:= PMask(uint32(@b) + (1 * j));
        for i:=0 to 7 do begin
                If Mask^[7-i] then writecharex('1', attributes) else writecharex('0', attributes);
        end;
     end;
end;

procedure writebin32ex(b : uint32; attributes: uint32);
var
   Mask : PMask;
   i,j  : uint8;

begin
     for j:=3 downto 0 do begin
        Mask:= PMask(uint32(@b) + (1 * j));
        for i:=0 to 7 do begin
                If Mask^[7-i] then writecharex('1', attributes) else writecharex('0', attributes);
        end;
     end;
end;

procedure writebin8(b : uint8);
begin
     writebin8ex(b, Console_Properties.Default_Attribute);
end;

procedure writebin16(b : uint16);
begin
     writebin16ex(b, Console_Properties.Default_Attribute);
end;

procedure writebin32(b : uint32);
begin
     writebin32ex(b, Console_Properties.Default_Attribute);
end;

procedure writebin8lnex(b : uint8; attributes: uint32);
begin
     writebin8ex(b, attributes);
     console._safeincrement_y();
end;

procedure writebin16lnex(b : uint16; attributes: uint32);
begin
     writebin16ex(b, attributes);
     console._safeincrement_y();
end;

procedure writebin32lnex(b : uint32; attributes: uint32);
begin
     writebin32ex(b, attributes);
     console._safeincrement_y();
end;

procedure writebin8ln(b : uint8);
begin
     writebin8lnex(b, Console_Properties.Default_Attribute);
end;

procedure writebin16ln(b : uint16);
begin
     writebin16lnex(b, Console_Properties.Default_Attribute);
end;

procedure writebin32ln(b : uint32);
begin
     writebin32lnex(b, Console_Properties.Default_Attribute);
end;

procedure setdefaultattribute(attribute: uint32); [public, alias: 'console_setdefaultattribute'];
begin
     Console_Properties.Default_Attribute:= attribute;
end;

procedure writechar(character: char); [public, alias: 'console_writechar'];
begin
     console.writecharex(character, Console_Properties.Default_Attribute);
end;

procedure writestring(str: PChar); [public, alias: 'console_writestring'];
begin
     console.writestringex(str, Console_Properties.Default_Attribute);
end;

procedure writeint(i: Integer); [public, alias: 'console_writeint'];
begin
     console.writeintex(i, Console_Properties.Default_Attribute);
end;

procedure writeword(i: DWORD); [public, alias: 'console_writeword'];
begin
     console.writewordex(i, Console_Properties.Default_Attribute);
end;

procedure writecharln(character: char); [public, alias: 'console_writecharln'];
begin
     console.writecharlnex(character, Console_Properties.Default_Attribute);
end;

procedure writestringln(str: PChar); [public, alias: 'console_writestringln'];
begin
     console.writestringlnex(str, Console_Properties.Default_Attribute);
end;

procedure writeintln(i: Integer); [public, alias: 'console_writeintln'];
begin
     console.writeintlnex(i, Console_Properties.Default_Attribute);
end;

procedure writewordln(i: DWORD); [public, alias: 'console_writewordln'];
begin
     console.writewordlnex(i, Console_Properties.Default_Attribute);
end;

procedure writecharex(character: char; attributes: uint32); [public, alias: 'console_writecharex'];
begin
    if WindowManager.Windows[DefaultWND] <> nil then begin
        WindowManager.Windows[DefaultWND]^.Buffer[WindowManager.Windows[DefaultWND]^.Cursor.Y][WindowManager.Windows[DefaultWND]^.Cursor.X].Character:= character;
        WindowManager.Windows[DefaultWND]^.Buffer[WindowManager.Windows[DefaultWND]^.Cursor.Y][WindowManager.Windows[DefaultWND]^.Cursor.X].Attributes:= attributes;
        //outputChar(character, Console_Cursor.X, Console_Cursor.Y, attributes SHR 16, attributes AND $FFFF);
        //Console_Matrix[Console_Cursor.Y][Console_Cursor.X].Character:= character;
        //Console_Matrix[Console_Cursor.Y][Console_Cursor.X].Attributes:= attributes;
        WindowManager.Windows[DefaultWND]^.row_dirty[WindowManager.Windows[DefaultWND]^.Cursor.Y]:= true;
        console._safeincrement_x();
    end;
end;

procedure writehexpair(b : uint8);
var
    bn : Array[0..1] of uint8;
    i  : uint8;

begin
    bn[0]:= b SHR 4;
    bn[1]:= b AND $0F;
    for i:=0 to 1 do begin
        case bn[i] of
            0:writestring('0');
            1:writestring('1');
            2:writestring('2');
            3:writestring('3');
            4:writestring('4');
            5:writestring('5');
            6:writestring('6');
            7:writestring('7');
            8:writestring('8');
            9:writestring('9');
            10:writestring('A');
            11:writestring('B');
            12:writestring('C');
            13:writestring('D');
            14:writestring('E');
            15:writestring('F');
        end;
    end;
end;

procedure writehexex(i : dword; attributes: uint32); [public, alias: 'console_writehexex'];
var
   Hex : Array[0..7] of Byte;
   Res : DWORD;
   Rem : DWORD;
   c   : Integer;
   
begin
     for c:=0 to 7 do begin
          Hex[c]:= 0;
     end;
     c:=0;
     Res:= i;
     Rem:= Res mod 16;
     while Res > 0 do begin
          Hex[c]:= Rem;
          Res:= Res div 16;
          Rem:= Res mod 16;
          c:=c+1;
     end;
     writestringex('0x', attributes);
     for c:=7 downto 0 do begin
          if Hex[c] <> 255 then begin
               case Hex[c] of
                    0:writecharex('0', attributes);
                    1:writecharex('1', attributes);
                    2:writecharex('2', attributes);
                    3:writecharex('3', attributes);
                    4:writecharex('4', attributes);
                    5:writecharex('5', attributes);
                    6:writecharex('6', attributes);
                    7:writecharex('7', attributes);
                    8:writecharex('8', attributes);
                    9:writecharex('9', attributes);
                    10:writecharex('A', attributes);
                    11:writecharex('B', attributes);
                    12:writecharex('C', attributes);
                    13:writecharex('D', attributes);
                    14:writecharex('E', attributes);
                    15:writecharex('F', attributes);
                    else writecharex('?', attributes);
               end;
          end;
     end;
end;

procedure writehex(i : dword); [public, alias: 'console_writehex'];
begin
     console.writehexex(i, Console_Properties.Default_Attribute);
end;

procedure writehexlnex(i : dword; attributes: uint32);
begin
     console.writehexex(i, attributes);
     console._safeincrement_y();
end;

procedure writehexln(i : dword);
begin
     writehexlnex(i, Console_Properties.Default_Attribute);
end;

procedure Output(identifier : PChar; str : PChar);
begin
     writestring('[');
     writestring(identifier);
     writestring('] ');
     writestring(str);
end;

procedure Outputln(identifier : PChar; str : PChar);
begin
     Output(identifier, str);
     writestringln(' ');
end;

procedure writestringex(str: PChar; attributes: uint32); [public, alias: 'console_writestringex'];
var
   i : integer;

begin
     i:= 0;
     while (str[i] <> #0) do begin
           console.writecharex(str[i], attributes);
           i:=i+1;
     end;
end;

procedure writeintex(i: Integer; attributes: uint32); [public, alias: 'console_writeintex'];
var
        buffer: array [0..11] of Char;
        str: PChar;
        digit: DWORD;
        minus: Boolean;
begin
        str := @buffer[11];
        str^ := #0;
        if (i < 0) then begin
                digit := -i;
                minus := True;
        end else begin
                digit := i;
                minus := False;
        end;
        repeat
                Dec(str);
                str^ := Char((digit mod 10) + Byte('0'));
                digit := digit div 10;
        until (digit = 0);
        if (minus) then begin
                Dec(str);
                str^ := '-';
        end;
        console.writestringex(str, attributes);
end;
 
procedure writewordex(i: DWORD; attributes: uint32); [public, alias: 'console_writedwordex'];
var
        buffer: array [0..11] of Char;
        str: PChar;
        digit: DWORD;
begin
        for digit := 0 to 10 do buffer[digit] := '0';
        str := @buffer[11];
        str^ := #0;
        digit := i;
        repeat
                Dec(str);
                str^ := Char((digit mod 10) + Byte('0'));
                digit := digit div 10;
        until (digit = 0);
        console.writestringex(@Buffer[0], attributes);
end;

procedure writecharlnex(character: char; attributes: uint32); [public, alias: 'console_writecharlnex'];
begin
     console.writecharex(character, attributes);
     console._safeincrement_y();
end;

procedure writestringlnex(str: PChar; attributes: uint32); [public, alias: 'console_writestringlnex'];
begin
     console.writestringex(str, attributes);
     console._safeincrement_y();
end;

procedure writeintlnex(i: Integer; attributes: uint32); [public, alias: 'console_writeintlnex'];
begin
     console.writeintex(i, attributes);
     console._safeincrement_y();
end;

procedure writewordlnex(i: DWORD; attributes: uint32); [public, alias: 'console_writewordlnex'];
begin
     console.writewordex(i, attributes);
     console._safeincrement_y();
end;

function combinecolors(Foreground, Background: uint16): uint32; 
begin
     combinecolors:= (uint32(Foreground) SHL 16) OR Background;
end;

procedure _update_cursor(); [public, alias: '_console_update_cursor'];
var
   pos : word;
   b   : byte;
   
begin
     //pos:= (Console_Cursor.Y * 80) + Console_Cursor.X;
     //outb($3D4, $0F);
     //b:= pos and $00FF;
     //outb($3D5, b);
     //outb($3D4, $0E);
     //b:= pos shr 8;
     //outb($3D5, b);
     if CONSOLE_SLOW_REDRAW then redrawWindows;
     //sleep(1);
end;

procedure backspace;
begin
     if WindowManager.Windows[DefaultWND] <> nil then begin
        Dec(WindowManager.Windows[DefaultWND]^.Cursor.X);
        writechar(' ');
        Dec(WindowManager.Windows[DefaultWND]^.Cursor.X);
        _update_cursor();
     end;
end;

procedure _increment_x(); [public, alias: '_console_increment_x'];
begin
     if WindowManager.Windows[DefaultWND] <> nil then begin
        WindowManager.Windows[DefaultWND]^.Cursor.X:= WindowManager.Windows[DefaultWND]^.Cursor.X+1;
        If WindowManager.Windows[DefaultWND]^.Cursor.X > WindowManager.Windows[DefaultWND]^.WND_W-1 then WindowManager.Windows[DefaultWND]^.Cursor.X:= 0;
        console._update_cursor;
     end;
     //Console_Cursor.X:= Console_Cursor.X+1;
     //If Console_Cursor.X > 159 then Console_Cursor.X:= 0;
     //console._update_cursor;
end;

procedure _increment_y(); [public, alias: '_console_increment_y'];
begin
     if WindowManager.Windows[DefaultWND] <> nil then begin
        WindowManager.Windows[DefaultWND]^.Cursor.Y:= WindowManager.Windows[DefaultWND]^.Cursor.Y+1;
        If WindowManager.Windows[DefaultWND]^.Cursor.Y > WindowManager.Windows[DefaultWND]^.WND_H-1 then begin
            console._newline();
            WindowManager.Windows[DefaultWND]^.Cursor.Y:= WindowManager.Windows[DefaultWND]^.WND_H-1;
        end;
        console._update_cursor;
     end;
     //Console_Cursor.Y:= Console_Cursor.Y+1;
     //If Console_Cursor.Y > 63 then begin
     //        console._newline();
     //        Console_Cursor.Y:= 63;
     //end;
     //console._update_cursor;
end;

procedure _safeincrement_x(); [public, alias: '_console_safeincrement_x'];
begin
     if WindowManager.Windows[DefaultWND] <> nil then begin
        WindowManager.Windows[DefaultWND]^.Cursor.X:= WindowManager.Windows[DefaultWND]^.Cursor.X+1;
        if WindowManager.Windows[DefaultWND]^.Cursor.X > WindowManager.Windows[DefaultWND]^.WND_W-1 then begin
            console._safeincrement_y();
        end;
        console._update_cursor;
     end;
     //Console_Cursor.X:= Console_Cursor.X+1;
     //If Console_Cursor.X > 159 then begin
     //   console._safeincrement_y();
     //end;
     //console._update_cursor;
end;

procedure _safeincrement_y(); [public, alias: '_console_safeincrement_y'];
begin
     if WindowManager.Windows[DefaultWND] <> nil then begin
        WindowManager.Windows[DefaultWND]^.Cursor.Y:= WindowManager.Windows[DefaultWND]^.Cursor.Y+1;
        if WindowManager.Windows[DefaultWND]^.Cursor.Y > WindowManager.Windows[DefaultWND]^.WND_H-1 then begin
            console._newline();
            WindowManager.Windows[DefaultWND]^.Cursor.Y:= WindowManager.Windows[DefaultWND]^.WND_H-1;
        end;
        WindowManager.Windows[DefaultWND]^.Cursor.X:= 0;
        console._update_cursor;
     end;
     //Console_Cursor.Y:= Console_Cursor.Y+1;
     //If Console_Cursor.Y > 63 then begin
     //        console._newline();
     //        Console_Cursor.Y:= 63;
     //end;
     //Console_Cursor.X:= 0;
     //console._update_cursor;
end;

procedure _newline(); [public, alias: '_console_newline'];
var
   x, y : byte;

begin
     if WindowManager.Windows[DefaultWND] <> nil then begin
        if WindowManager.Windows[DefaultWND]^.WND_W = 0 then exit;
        if WindowManager.Windows[DefaultWND]^.WND_H = 0 then exit;
        for x:=0 to WindowManager.Windows[DefaultWND]^.WND_W do begin
            for y:=0 to WindowManager.Windows[DefaultWND]^.WND_H-1 do begin
                WindowManager.Windows[DefaultWND]^.buffer[y][x]:= WindowManager.Windows[DefaultWND]^.buffer[y+1][x];
                WindowManager.Windows[DefaultWND]^.row_dirty[y]:= true;
                //Console_Matrix[y][x]:= Console_Matrix[y+1][x];
            end;
        end;
        for x:=0 to WindowManager.Windows[DefaultWND]^.WND_W do begin
            WindowManager.Windows[DefaultWND]^.buffer[WindowManager.Windows[DefaultWND]^.WND_H-1][x].Character:= ' ';
            WindowManager.Windows[DefaultWND]^.buffer[WindowManager.Windows[DefaultWND]^.WND_H-1][x].Attributes:= $FFFF0000;
            //Console_Matrix[63][x].Character:= ' ';
            //Console_Matrix[63][x].Attributes:= $FFFF0000;
        end;
        //for y:=0 to 63 do begin
        //   for x:=0 to 159 do begin
        //       OutputChar(Console_Matrix[y][x].Character, x, y, Console_Matrix[y][x].Attributes SHR 16, Console_Matrix[y][x].Attributes AND $FFFF);
        //   end;
        //end;
        console._update_cursor;
     end;
end;

{ WND Specific Console Draw Functions }

procedure clearWND(WND : uint32);
var
   x,y: Byte;

begin
     if WindowManager.Windows[WND] <> nil then begin
        for y:=0 to 63 do begin
            for x:=0 to 159 do begin
                WindowManager.Windows[WND]^.Buffer[y][x].Character:= ' ';
                WindowManager.Windows[WND]^.Buffer[y][x].Attributes:= Console_Properties.Default_Attribute;
                WindowManager.Windows[WND]^.row_dirty[y]:= true;
                //Console_Matrix[y][x].Character:= ' ';
                //Console_Matrix[y][x].Attributes:= Console_Properties.Default_Attribute;
                //OutputChar(Console_Matrix[y][x].Character, x, y, Console_Matrix[y][x].Attributes SHR 16, Console_Matrix[y][x].Attributes AND $FFFF);
            end;
        end;
        WindowManager.Windows[WND]^.Cursor.X:= 0;
        WindowManager.Windows[WND]^.Cursor.Y:= 0;
        //redrawWindows;
     end;
     //Console_Cursor.X:= 0;
     //Console_Cursor.Y:= 0;
end;

procedure clearWNDEx(WND : uint32; attributes : uint32);
var
   x,y: Byte;

begin
     if WindowManager.Windows[WND] <> nil then begin
        for y:=0 to 63 do begin
            for x:=0 to 159 do begin
                WindowManager.Windows[WND]^.Buffer[y][x].Character:= ' ';
                WindowManager.Windows[WND]^.Buffer[y][x].Attributes:= attributes;
                WindowManager.Windows[WND]^.row_dirty[y]:= true;
            end;
        end;
        WindowManager.Windows[WND]^.Cursor.X:= 0;
        WindowManager.Windows[WND]^.Cursor.Y:= 0;
     end;
end;

procedure writebin8exWND(b : uint8; attributes: uint32; WND : uint32);
var
   Mask : PMask;
   i    : uint8;

begin
     Mask:= PMask(@b);
     for i:=0 to 7 do begin
        If Mask^[7-i] then writecharexWND('1', attributes, WND) else writecharexWND('0', attributes, WND);
     end;
end;

procedure writebin16exWND(b : uint16; attributes: uint32; WND : uint32);
var
   Mask : PMask;
   i,j  : uint8;

begin
     for j:=1 downto 0 do begin
        Mask:= PMask(uint32(@b) + (1 * j));
        for i:=0 to 7 do begin
                If Mask^[7-i] then writecharexWND('1', attributes, WND) else writecharexWND('0', attributes, WND);
        end;
     end;
end;

procedure writebin32exWND(b : uint32; attributes: uint32; WND : uint32);
var
   Mask : PMask;
   i,j  : uint8;

begin
     for j:=3 downto 0 do begin
        Mask:= PMask(uint32(@b) + (1 * j));
        for i:=0 to 7 do begin
                If Mask^[7-i] then writecharexWND('1', attributes, WND) else writecharexWND('0', attributes, WND);
        end;
     end;
end;

procedure writebin8WND(b : uint8; WND : uint32);
begin
     writebin8exWND(b, Console_Properties.Default_Attribute, WND);
end;

procedure writebin16WND(b : uint16; WND : uint32);
begin
     writebin16exWND(b, Console_Properties.Default_Attribute, WND);
end;

procedure writebin32WND(b : uint32; WND : uint32);
begin
     writebin32exWND(b, Console_Properties.Default_Attribute, WND);
end;

procedure writebin8lnexWND(b : uint8; attributes: uint32; WND : uint32);
begin
     writebin8exWND(b, attributes, WND);
     console._safeincrement_y_WND(WND);
end;

procedure writebin16lnexWND(b : uint16; attributes: uint32; WND : uint32);
begin
     writebin16exWND(b, attributes, WND);
     console._safeincrement_y_WND(WND);
end;

procedure writebin32lnexWND(b : uint32; attributes: uint32; WND : uint32);
begin
     writebin32exWND(b, attributes, WND);
     console._safeincrement_y_WND(WND);
end;

procedure writebin8lnWND(b : uint8; WND : uint32);
begin
     writebin8lnexWND(b, Console_Properties.Default_Attribute, WND);
end;

procedure writebin16lnWND(b : uint16; WND : uint32);
begin
     writebin16lnexWND(b, Console_Properties.Default_Attribute, WND);
end;

procedure writebin32lnWND(b : uint32; WND : uint32);
begin
     writebin32lnexWND(b, Console_Properties.Default_Attribute, WND);
end;

{procedure setdefaultattribute(attribute: uint32); [public, alias: 'console_setdefaultattribute'];
begin
     Console_Properties.Default_Attribute:= attribute;
end;}

procedure writecharWND(character: char; WND : uint32);
begin
     console.writecharexWND(character, Console_Properties.Default_Attribute, WND);
end;

procedure writestringWND(str: PChar; WND : uint32);
begin
     console.writestringexWND(str, Console_Properties.Default_Attribute, WND);
end;

procedure writeintWND(i: Integer; WND : uint32);
begin
     console.writeintexWND(i, Console_Properties.Default_Attribute, WND);
end;

procedure writewordWND(i: DWORD; WND : uint32);
begin
     console.writewordexWND(i, Console_Properties.Default_Attribute, WND);
end;

procedure writecharlnWND(character: char; WND : uint32);
begin
     console.writecharlnexWND(character, Console_Properties.Default_Attribute, WND);
end;

procedure writestringlnWND(str: PChar; WND : uint32);
begin
     console.writestringlnexWND(str, Console_Properties.Default_Attribute, WND);
end;

procedure writeintlnWND(i: Integer; WND : uint32); 
begin
     console.writeintlnexWND(i, Console_Properties.Default_Attribute, WND);
end;

procedure writewordlnWND(i: DWORD; WND : uint32);
begin
     console.writewordlnexWND(i, Console_Properties.Default_Attribute, WND);
end;

procedure writecharexWND(character: char; attributes: uint32; WND : uint32); 
begin
    if WindowManager.Windows[WND] <> nil then begin
        WindowManager.Windows[WND]^.Buffer[WindowManager.Windows[WND]^.Cursor.Y][WindowManager.Windows[WND]^.Cursor.X].Character:= character;
        WindowManager.Windows[WND]^.Buffer[WindowManager.Windows[WND]^.Cursor.Y][WindowManager.Windows[WND]^.Cursor.X].Attributes:= attributes;
        //outputChar(character, Console_Cursor.X, Console_Cursor.Y, attributes SHR 16, attributes AND $FFFF);
        //Console_Matrix[Console_Cursor.Y][Console_Cursor.X].Character:= character;
        //Console_Matrix[Console_Cursor.Y][Console_Cursor.X].Attributes:= attributes;
        WindowManager.Windows[WND]^.row_dirty[WindowManager.Windows[WND]^.Cursor.Y]:= true;
        console._safeincrement_x_WND(WND);
    end;
end;

procedure writehexpairWND(b : uint8; WND : uint32);
var
    bn : Array[0..1] of uint8;
    i  : uint8;

begin
    bn[0]:= b SHR 4;
    bn[1]:= b AND $0F;
    for i:=0 to 1 do begin
        case bn[i] of
            0 :writestringWND('0', WND);
            1 :writestringWND('1', WND);
            2 :writestringWND('2', WND);
            3 :writestringWND('3', WND);
            4 :writestringWND('4', WND);
            5 :writestringWND('5', WND);
            6 :writestringWND('6', WND);
            7 :writestringWND('7', WND);
            8 :writestringWND('8', WND);
            9 :writestringWND('9', WND);
            10:writestringWND('A', WND);
            11:writestringWND('B', WND);
            12:writestringWND('C', WND);
            13:writestringWND('D', WND);
            14:writestringWND('E', WND);
            15:writestringWND('F', WND);
        end;
    end;
end;

procedure writehexexWND(i : dword; attributes: uint32; WND : uint32);
var
   Hex : Array[0..7] of Byte;
   Res : DWORD;
   Rem : DWORD;
   c   : Integer;
   
begin
     for c:=0 to 7 do begin
          Hex[c]:= 0;
     end;
     c:=0;
     Res:= i;
     Rem:= Res mod 16;
     while Res > 0 do begin
          Hex[c]:= Rem;
          Res:= Res div 16;
          Rem:= Res mod 16;
          c:=c+1;
     end;
     writestringexWND('0x', attributes, WND);
     for c:=7 downto 0 do begin
          if Hex[c] <> 255 then begin
               case Hex[c] of
                    0:writecharexWND('0', attributes, WND);
                    1:writecharexWND('1', attributes, WND);
                    2:writecharexWND('2', attributes, WND);
                    3:writecharexWND('3', attributes, WND);
                    4:writecharexWND('4', attributes, WND);
                    5:writecharexWND('5', attributes, WND);
                    6:writecharexWND('6', attributes, WND);
                    7:writecharexWND('7', attributes, WND);
                    8:writecharexWND('8', attributes, WND);
                    9:writecharexWND('9', attributes, WND);
                    10:writecharexWND('A', attributes, WND);
                    11:writecharexWND('B', attributes, WND);
                    12:writecharexWND('C', attributes, WND);
                    13:writecharexWND('D', attributes, WND);
                    14:writecharexWND('E', attributes, WND);
                    15:writecharexWND('F', attributes, WND);
                    else writecharexWND('?', attributes, WND);
               end;
          end;
     end;
end;

procedure writehexWND(i : dword; WND : uint32);
begin
     console.writehexexWND(i, Console_Properties.Default_Attribute, WND);
end;

procedure writehexlnexWND(i : dword; attributes: uint32; WND : uint32);
begin
     console.writehexexWND(i, attributes, WND);
     console._safeincrement_y_WND(WND);
end;

procedure writehexlnWND(i : dword; WND : uint32);
begin
     writehexlnexWND(i, Console_Properties.Default_Attribute, WND);
end;

procedure OutputWND(identifier : PChar; str : PChar; WND : uint32);
begin
     writestringWND('[', WND);
     writestringWND(identifier, WND);
     writestringWND('] ', WND);
     writestringWND(str, WND);
end;

procedure OutputlnWND(identifier : PChar; str : PChar; WND : uint32);
begin
     OutputWND(identifier, str, WND);
     writestringlnWND(' ', WND);
end;

procedure writestringexWND(str: PChar; attributes: uint32; WND : uint32);
var
   i : integer;

begin
     i:= 0;
     while (str[i] <> #0) do begin
           console.writecharexWND(str[i], attributes, WND);
           i:=i+1;
     end;
end;

procedure writeintexWND(i: Integer; attributes: uint32; WND : uint32); 
var
        buffer: array [0..11] of Char;
        str: PChar;
        digit: DWORD;
        minus: Boolean;
begin
        str := @buffer[11];
        str^ := #0;
        if (i < 0) then begin
                digit := -i;
                minus := True;
        end else begin
                digit := i;
                minus := False;
        end;
        repeat
                Dec(str);
                str^ := Char((digit mod 10) + Byte('0'));
                digit := digit div 10;
        until (digit = 0);
        if (minus) then begin
                Dec(str);
                str^ := '-';
        end;
        console.writestringexWND(str, attributes, WND);
end;
 
procedure writewordexWND(i: DWORD; attributes: uint32; WND : uint32);
var
        buffer: array [0..11] of Char;
        str: PChar;
        digit: DWORD;
begin
        for digit := 0 to 10 do buffer[digit] := '0';
        str := @buffer[11];
        str^ := #0;
        digit := i;
        repeat
                Dec(str);
                str^ := Char((digit mod 10) + Byte('0'));
                digit := digit div 10;
        until (digit = 0);
        console.writestringexWND(@Buffer[0], attributes, WND);
end;

procedure writecharlnexWND(character: char; attributes: uint32; WND : uint32);
begin
     console.writecharexWND(character, attributes, WND);
     console._safeincrement_y_WND(WND);
end;

procedure writestringlnexWND(str: PChar; attributes: uint32; WND : uint32);
begin
     console.writestringexWND(str, attributes, WND);
     console._safeincrement_y_WND(WND);
end;

procedure writeintlnexWND(i: Integer; attributes: uint32; WND : uint32);
begin
     console.writeintexWND(i, attributes, WND);
     console._safeincrement_y_WND(WND);
end;

procedure writewordlnexWND(i: DWORD; attributes: uint32; WND : uint32);
begin
     console.writewordexWND(i, attributes, WND);
     console._safeincrement_y_WND(WND);
end;

procedure backspaceWND(WND : uint32);
begin
     if WindowManager.Windows[WND] <> nil then begin
        Dec(WindowManager.Windows[WND]^.Cursor.X);
        writecharWND(' ', WND);
        Dec(WindowManager.Windows[WND]^.Cursor.X);
        _update_cursor();
     end;
end;

procedure _increment_x_WND(WND : uint32);
begin
     if WindowManager.Windows[WND] <> nil then begin
        WindowManager.Windows[WND]^.Cursor.X:= WindowManager.Windows[WND]^.Cursor.X+1;
        If WindowManager.Windows[WND]^.Cursor.X > WindowManager.Windows[WND]^.WND_W-1 then WindowManager.Windows[WND]^.Cursor.X:= 0;
        console._update_cursor;
     end;
     //Console_Cursor.X:= Console_Cursor.X+1;
     //If Console_Cursor.X > 159 then Console_Cursor.X:= 0;
     //console._update_cursor;
end;

procedure _increment_y_WND(WND : uint32);
begin
     if WindowManager.Windows[WND] <> nil then begin
        WindowManager.Windows[WND]^.Cursor.Y:= WindowManager.Windows[WND]^.Cursor.Y+1;
        If WindowManager.Windows[WND]^.Cursor.Y > WindowManager.Windows[WND]^.WND_H-1 then begin
            console._newlineWND(WND);
            WindowManager.Windows[WND]^.Cursor.Y:= WindowManager.Windows[WND]^.WND_H-1;
        end;
        console._update_cursor;
     end;
     //Console_Cursor.Y:= Console_Cursor.Y+1;
     //If Console_Cursor.Y > 63 then begin
     //        console._newline();
     //        Console_Cursor.Y:= 63;
     //end;
     //console._update_cursor;
end;

procedure _safeincrement_x_WND(WND : uint32);
begin
     if WindowManager.Windows[WND] <> nil then begin
        WindowManager.Windows[WND]^.Cursor.X:= WindowManager.Windows[WND]^.Cursor.X+1;
        if WindowManager.Windows[WND]^.Cursor.X > WindowManager.Windows[WND]^.WND_W-1 then begin
            console._safeincrement_y_WND(WND);
        end;
        console._update_cursor;
     end;
     //Console_Cursor.X:= Console_Cursor.X+1;
     //If Console_Cursor.X > 159 then begin
     //   console._safeincrement_y();
     //end;
     //console._update_cursor;
end;

procedure _safeincrement_y_WND(WND : uint32);
begin
     if WindowManager.Windows[WND] <> nil then begin
        WindowManager.Windows[WND]^.Cursor.Y:= WindowManager.Windows[WND]^.Cursor.Y+1;
        if WindowManager.Windows[WND]^.Cursor.Y > WindowManager.Windows[WND]^.WND_H-1 then begin
            console._newlineWND(WND);
            WindowManager.Windows[WND]^.Cursor.Y:= WindowManager.Windows[WND]^.WND_H-1;
        end;
        WindowManager.Windows[WND]^.Cursor.X:= 0;
        console._update_cursor;
     end;
     //Console_Cursor.Y:= Console_Cursor.Y+1;
     //If Console_Cursor.Y > 63 then begin
     //        console._newline();
     //        Console_Cursor.Y:= 63;
     //end;
     //Console_Cursor.X:= 0;
     //console._update_cursor;
end;

procedure _newlineWND(WND : uint32);
var
   x, y : byte;

begin
     if WindowManager.Windows[WND] <> nil then begin
        if WindowManager.Windows[WND]^.WND_W = 0 then exit;
        if WindowManager.Windows[WND]^.WND_H = 0 then exit;
        for x:=0 to WindowManager.Windows[WND]^.WND_W do begin
            for y:=0 to WindowManager.Windows[WND]^.WND_H-1 do begin
                WindowManager.Windows[WND]^.buffer[y][x]:= WindowManager.Windows[WND]^.buffer[y+1][x];
                WindowManager.Windows[WND]^.row_dirty[y]:= true;
                //Console_Matrix[y][x]:= Console_Matrix[y+1][x];
            end;
        end;
        for x:=0 to WindowManager.Windows[WND]^.WND_W do begin
            WindowManager.Windows[WND]^.buffer[WindowManager.Windows[WND]^.WND_H-1][x].Character:= ' ';
            WindowManager.Windows[WND]^.buffer[WindowManager.Windows[WND]^.WND_H-1][x].Attributes:= $FFFF0000;
            //Console_Matrix[63][x].Character:= ' ';
            //Console_Matrix[63][x].Attributes:= $FFFF0000;
        end;
        //for y:=0 to 63 do begin
        //   for x:=0 to 159 do begin
        //       OutputChar(Console_Matrix[y][x].Character, x, y, Console_Matrix[y][x].Attributes SHR 16, Console_Matrix[y][x].Attributes AND $FFFF);
        //   end;
        //end;
        console._update_cursor;
     end;
end;

end.
