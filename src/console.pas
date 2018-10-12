{ 
	Console - Provides Screen/Window management & drawing.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit console;

interface

uses
     util, 
     bios_data_area,
     multiboot,
     fonts,
     tracer;

type
	{ 4-bit nibble representing a color. }
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

	{ Window Manager Events. }
    TEventType = ( EVENT_DRAW,
                   EVENT_MOUSE_CLICK,
                   EVENT_MOUSE_MOVE,
                   EVENT_MOUSE_DOWN,
                   EVENT_MOUSE_UP,
                   EVENT_KEY_PRESSED,
                   EVENT_CLOSE,
                   EVENT_MINIMIZE,
                   EVENT_FOCUS,
                   EVENT_LOSE_FOCUS );




{ Default Buffer Specific }

{ 
	Initialize the Frame Buffer & Window Manager ready for use.
}
procedure init();

{ 
	Clear the Frame Buffer. 
}
procedure clear();

{ 
	Set the default set of attributes to be used when drawing to the screen.
	@param(attribute A 32-bit value representing the Foreground & Background colors.) 
}
procedure setdefaultattribute(attribute : uint32);

{
	@bold(Text mode only!) - Disable the cursor/text-caret. 
	@deprecated
}
procedure disable_cursor;

{ 
	Write a single 8-bit character to the screen.
	@param(character An 8-bit value representing an ASCII character.) 
}
procedure writechar(character : char);

{ 
	Write a single 8-bit character to the screen, followed by starting a new line.
	@param(character An 8-bit value representing an ASCII character.) 
}
procedure writecharln(character : char);

{ 
	Write a single 8-bit character to the screen, specifying custom color attributes.
	@param(character An 8-bit value representing an ASCII character.)
	@param(attributes A 32-bit value representing the colors for the background and foreground.)
}
procedure writecharex(character : char; attributes: uint32);

{ 
	Write a single 8-bit character to the screen, followed by starting a new line, specifying custom color attributes.
	@param(character An 8-bit value representing an ASCII character.)
	@param(attributes A 32-bit value representing the colors for the background and foreground.)
}
procedure writecharlnex(character : char; attributes: uint32);

{ 
	Simple console write for debugging.
	@param(identifier A NULL terminated string with the name of the module printing the output.)
	@param(str A NULL terminated string with the debug message.)
}
procedure Output(identifier : PChar; str : PChar);

{ 
	Simple console writeln for debugging.
	@param(identifier A NULL terminated string with the name of the module printing the output.)
	@param(str A NULL terminated string with the debug message.)
}
procedure Outputln(identifier : PChar; str : PChar);

{ 
	Write a NULL terminated string to the console.
	@param(str A NULL terminated string with the debug message.)
}
procedure writestring(str: PChar);

{ 
	Write a NULL terminated string to the console, followed by a new-line.
	@param(str A NULL terminated string with the debug message.)
}
procedure writestringln(str: PChar);

{ 
	Write a NULL terminated string to the console, with the specified attributes.
	@param(str A NULL terminated string with the debug message.)
	@param(attributes A 32-bit representation of the background/foreground colors.)
}
procedure writestringex(str: PChar; attributes: uint32);

{ 
	Write a NULL terminated string + new-line to the console, with the specified attributes.
	@param(str A NULL terminated string with the debug message.)
	@param(attributes A 32-bit representation of the background/foreground colors.)
}
procedure writestringlnex(str: PChar; attributes: uint32);

{ 
	Write a 32-bit value to the console.
	@param(i A 32-bit value.)
}
procedure writeint(i: Integer);

{ 
	Write a 32-bit value to the console followed by a new-line.
	@param(i A 32-bit value.)
}
procedure writeintln(i: Integer);

{ 
	Write a 32-bit value to the console, with the specified attributes.
	@param(i A 32-bit value.)
	@param(attributes A 32-bit representation of the background/foreground colors.)
}
procedure writeintex(i: Integer; attributes: uint32);

{ 
	Write a 32-bit value + new-line to the console, with the specified attributes.
	@param(i A 32-bit value.)
	@param(attributes A 32-bit representation of the background/foreground colors.)
}
procedure writeintlnex(i: Integer; attributes: uint32);

{ 
	Write an 8-bit Hex Pair to the console.
	@param(b An 8-bit value.)
}
procedure writehexpair(b : uint8);

{ 
	Write a 32-bit value as Hex Pairs to the console.
	@param(i A 32-bit value.)
}
procedure writehex(i: DWORD);

{ 
	Write a 32-bit value as Hex Pairs to the console, followed by a new-line.
	@param(i A 32-bit value.)
}
procedure writehexln(i: DWORD);

{ 
	Write a 32-bit value as Hex Pairs to the console, with the specified attributes.
	@param(b A 32-bit value.)
	@param(attributes A 32-bit representation of the background/foreground colors.)
}
procedure writehexex(i : DWORD; attributes: uint32);

{ 
	Write a 32-bit value as Hex Pairs + new-line to the console, with the specified attributes.
	@param(b A 32-bit value.)
	@param(attributes A 32-bit representation of the background/foreground colors.)
}
procedure writehexlnex(i: DWORD; attributes: uint32);

{ 
	Write an 8-bit value as binary to the console.
	@param(b An 8-bit value.)
}
procedure writebin8(b : uint8);

{ 
	Write an 8-bit value as binary to the console, followed by a new-line.
	@param(b An 8-bit value.)
}
procedure writebin8ln(b : uint8);

{ 
	Write an 8-bit value as binary to the console, with the specified attributes.
	@param(b An 8-bit value.)
	@param(attributes A 32-bit representation of the background/foreground colors.)
}
procedure writebin8ex(b : uint8; attributes: uint32);

{ 
	Write an 8-bit value as binary + new-line to the console, with the specified attributes.
	@param(b An 8-bit value.)
	@param(attributes A 32-bit representation of the background/foreground colors.)
}
procedure writebin8lnex(b : uint8; attributes: uint32);

{ 
	Write a 16-bit value as binary to the console.
	@param(b A 16-bit value.)
}
procedure writebin16(b : uint16);

{ 
	Write an 16-bit value as binary to the console, followed by a new-line.
	@param(b A 16-bit value.)
}
procedure writebin16ln(b : uint16);

{
	Write a 16-bit value as binary to the console, with the specified attributes.
	@param(b A 16-bit value.)
	@param(attributes A 32-bit representation of the background/foreground colors.)
}
procedure writebin16ex(b : uint16; attributes: uint32);

{
	Write a 16-bit value as binary + new-line to the console, with the specified attributes.
	@param(b A 16-bit value.)
	@param(attributes A 32-bit representation of the background/foreground colors.)
}
procedure writebin16lnex(b : uint16; attributes: uint32);

{ 
	Write a 32-bit value as binary to the console.
	@param(b A 32-bit value.)
}
procedure writebin32(b : uint32);

{ 
	Write an 32-bit value as binary to the console, followed by a new-line.
	@param(b A 32-bit value.)
}
procedure writebin32ln(b : uint32);

{
	Write a 32-bit value as binary to the console, with the specified attributes.
	@param(b A 32-bit value.)
	@param(attributes A 32-bit representation of the background/foreground colors.)
}
procedure writebin32ex(b : uint32; attributes: uint32);

{
	Write a 32-bit value as binary + new-line to the console, with the specified attributes.
	@param(b A 32-bit value.)
	@param(attributes A 32-bit representation of the background/foreground colors.)
}
procedure writebin32lnex(b : uint32; attributes: uint32);

{ 
	Move the caret back 1 position and remove the character within the cell the caret occupies.
}
procedure backspace;

{
	Combine two 16-bit values representing Foreground and Background respectively, into a 32-bit value representing an attribute. 
	@param(Foreground A 16-bit value representing the foreground color.)
	@param(Background A 16-bit value representing the background color.)
	@returns(A 32-bit value representing an attribute set. (uint32) )
}
function combinecolors(Foreground, Background : uint16) : uint32;

{ Increment the cursor one cell to the right (x+1). }
procedure _increment_x();

{ Increment the cursor one cell down (y+1). }
procedure _increment_y();

{ Increment the cursor one cell to the right (x+1), wrapping to the next line and performing a Y-Axis scroll when when needed. }
procedure _safeincrement_x();

{ Increment the cursor one cell down (y+1), performing a Y-Axis roll when when needed. }
procedure _safeincrement_y();

{ Increment the cursor one cell down and reposition it at the first X Cell (y+1, x=0),performing a Y-Axis scroll when needed. }
procedure _newline();





{ Window Specific }


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

procedure writehexpairWND(b : uint8; WND : uint32);
procedure writehexpairExWND(b : uint8; Attributes : uint32; WND : uint32);
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

procedure mouseEnabled(b : boolean);

procedure _MouseDown();
procedure _MouseUp();
procedure _MouseClick(left : boolean);

procedure setWindowColors(colors : uint32);
function getWindowColorPtr : puint32;

const
	MAX_WINDOWS = 255; //<Maximum number of Windows open.
    DefaultWND  = 0;   //<The Window assigned for output when no Window is specified. (Default).

implementation

type
	{ Properties pertaining to the raw screen matrix.}
    TConsoleProperties = record
      Default_Attribute : uint32; //Attribute (Colors) to use when no override defined.
    end;

	{ Unrasterized representation of a character.}
    TCharacter = bitpacked record
      Character  : Char;
      attributes : uint32;
      visible    : boolean;
    end;
    PCharacter = ^TCharacter;

	{ Unrasterized screen matrix. }
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
    TFocusHook      = procedure();
    TLoseFocusHook  = procedure();

    THooks = record
        OnDraw       : TDrawHook;       //Implemented
        OnMouseClick : TMouseClickHook; //Implemented
        OnMouseMove  : TMouseMoveHook;  
        OnMouseDown  : TMouseDownHook;  
        OnMouseUp    : TMouseUpHook;    
        OnKeyPressed : TKeyPressedHook; //Implemented
        OnClose      : TCloseHook;      //Implemented
        OnMinimize   : TMinimizeHook;   
        OnFocus      : TFocusHook;      //Implemented
        OnLoseFocus  : TLoseFocusHook;  //Implemented
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

    TWindows    = Array[0..MAX_WINDOWS-1] of PWindow;
    TZOrder     = Array[0..MAX_WINDOWS-1] of uint32;
    TBackOrder  = Array[0..MAX_WINDOWS-1] of uint32;
    TFrontOrder = Array[0..MAX_WINDOWS-1] of uint32;

    TWindowManager = record
        Windows     : TWindows;
        Z_Order     : TZOrder;
        Back_Order  : TBackOrder;
        Front_Order : TFrontOrder;
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
   ExitMask           : TMask;
   MouseDown          : Boolean;
   WindowMovePos      : TMouseCoord;
   MovingWindow       : uint32;
   UnhandledClick     : Boolean = false;
   UnhandledClickLeft : Boolean = false;
   MouseCursorEnabled : Boolean = true;
   OpenTerminal       : Boolean = false;

uses
    lmemorymanager, strings, keyboard, serial, terminal;

function getWindowColorPtr : puint32;
begin
    getWindowColorPtr:= @Window_Border.Attributes;
end;

procedure setWindowColors(colors : uint32);
begin
    Window_Border.Attributes:= colors;
end;

procedure mouseEnabled(b : boolean);
begin
    MouseCursorEnabled:= b;
end;

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
    if not UnhandledClick then begin
        UnhandledClick:= true;
        UnhandledClickLeft:= left;
    end;
end;

procedure AddToZOrder(WND : HWND);
var
    idx : uint32;
    i : uint32;
    Window : PWindow;

begin
    idx:= MAX_WINDOWS;
    for i:=0 to MAX_WINDOWS-1 do begin
        if WindowManager.Z_Order[i] = WND then begin
            break;
        end;
        if WindowManager.Z_Order[i] = MAX_WINDOWS then begin
            idx:= i;
            break;
        end;
    end;
    if idx <> MAX_WINDOWS then begin
        WindowManager.Z_Order[idx]:= WND;
    end;
end;

procedure RemoveFromZOrder(WND : HWND);
var
    i : uint32;
    idx : uint32;

begin
    idx:= MAX_WINDOWS;
    for i:=0 to MAX_WINDOWS-1 do begin
        if WindowManager.Z_Order[i] = WND then begin
            WindowManager.Z_Order[i]:= MAX_WINDOWS;
            idx:= i;
            break;
        end;
    end;
    if idx <> MAX_WINDOWS then begin
        for i:=idx to MAX_WINDOWS-2 do begin
            WindowManager.Z_Order[i]:= WindowManager.Z_Order[i+1];
        end;
        WindowManager.Z_Order[MAX_WINDOWS-1]:= MAX_WINDOWS;
    end;
end;

procedure FocusZOrder(WND : HWND);
var
    i : uint32;
    idx : uint32;
    old, new : HWND;
    wold, wnew : PWindow;

begin
    idx:= MAX_WINDOWS;
    for i:=0 to MAX_WINDOWS-1 do begin
        if WindowManager.Z_Order[i] = WND then begin
            idx:= i;
            break;
        end;
    end;
    if idx <> MAX_WINDOWS then begin
        old:= WindowManager.Z_Order[0];
        new:= WND;
        for i:=idx downto 1 do begin
            WindowManager.Z_Order[i]:= WindowManager.Z_Order[i-1];
        end;
        WindowManager.Z_Order[0]:= WND;
        if old <> new then begin
            wold:= WindowManager.Windows[old];
            wnew:= WindowManager.Windows[new];
            if wold <> nil then begin
                if wold^.Hooks.OnLoseFocus <> nil then wold^.Hooks.OnLoseFocus();
            end;
            if wnew <> nil then begin
                if wnew^.Hooks.OnFocus <> nil then wnew^.Hooks.OnFocus();
            end;
        end;
    end;
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
            EVENT_FOCUS       : WindowManager.Windows[WND]^.Hooks.OnFocus:=      TFocusHook(Handler);
            EVENT_LOSE_FOCUS  : WindowManager.Windows[WND]^.Hooks.OnLoseFocus:=  TLoseFocusHook(Handler);
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
    tracer.push_trace('console.newWindow');
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
        WND^.Hooks.OnFocus      := nil;
        WND^.Hooks.OnLoseFocus  := nil;
        WindowManager.Windows[newWindow]:= WND;
        AddToZOrder(newWindow);
        FocusZOrder(newWindow);
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
        RemoveFromZOrder(WND);
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
    if MouseCursorEnabled then outputCharToScreenSpace(char(0), WindowManager.MousePrev.x, WindowManager.MousePrev.y, $FFFF);
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
    SelectedWindow : uint32;

begin
    if OpenTerminal then begin
        terminal.run;
        OpenTerminal:= false;
    end;

    { Clear the Console_Matrix }
    for y:=0 to 63 do begin
        for x:=0 to 159 do begin
            Console_Matrix[y][x]:= Default_Char;
        end;
    end;

    { Redraw all of the Windows to the Matrix taking into account Z_Order and borders }
    for w:=MAX_WINDOWS-1 downto 0 do begin
        if WindowManager.Z_Order[w] = MAX_WINDOWS then continue;
        if WindowManager.Windows[WindowManager.Z_Order[w]] <> nil then begin
            if WindowManager.Windows[WindowManager.Z_Order[w]]^.Hooks.OnDraw <> nil then WindowManager.Windows[WindowManager.Z_Order[w]]^.Hooks.OnDraw();
            If WindowManager.Windows[WindowManager.Z_Order[w]]^.visible then begin
                if WindowManager.Windows[WindowManager.Z_Order[w]]^.Border then begin
                    WXL:= WindowManager.Windows[WindowManager.Z_Order[w]]^.WND_X - 1;
                    WYL:= WindowManager.Windows[WindowManager.Z_Order[w]]^.WND_Y - 1;
                    WXR:= WindowManager.Windows[WindowManager.Z_Order[w]]^.WND_X + WindowManager.Windows[WindowManager.Z_Order[w]]^.WND_W + 1;
                    WYR:= WindowManager.Windows[WindowManager.Z_Order[w]]^.WND_Y + WindowManager.Windows[WindowManager.Z_Order[w]]^.WND_H + 1;
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
                    STARTP:= MIDP - (StringSize(WindowManager.Windows[WindowManager.Z_Order[w]]^.WND_NAME) div 2) - 1;
                    for x:=WXL to WXR do begin
                        Console_Matrix[WYL][x]:= Window_Border;
                        WindowTitleMask[WYL][x]:= WindowManager.Z_Order[w];
                        if (STRC = StringSize(WindowManager.Windows[WindowManager.Z_Order[w]]^.WND_NAME)) and (w = 0) then begin
                            console_Matrix[WYL][x].character:= '*';
                            inc(STRC);
                        end;
                        if (x >= STARTP) and (STRC < StringSize(WindowManager.Windows[WindowManager.Z_Order[w]]^.WND_NAME)) then begin
                            Console_Matrix[WYL][x].character:= WindowManager.Windows[WindowManager.Z_Order[w]]^.WND_NAME[STRC];
                            inc(STRC);
                        end;
                        if x = WXR then begin
                            Console_Matrix[WYL][x].character:= 'x';
                            ExitMask[WYL][x]:= WindowManager.Z_Order[w];
                        end;
                        Console_Matrix[WYR][x]:= Window_Border;
                        Console_Real[WYL][x].Character:= char(3);
                        Console_Real[WYR][x].Character:= char(3);
                    end;
                end;
                for y:=WindowManager.Windows[WindowManager.Z_Order[w]]^.WND_Y to WindowManager.Windows[WindowManager.Z_Order[w]]^.WND_Y + WindowManager.Windows[WindowManager.Z_Order[w]]^.WND_H do begin
                    if y > 63 then break;
                    for x:=WindowManager.Windows[WindowManager.Z_Order[w]]^.WND_X to WindowManager.Windows[WindowManager.Z_Order[w]]^.WND_X + WindowManager.Windows[WindowManager.Z_Order[w]]^.WND_W do begin
                        if x > 159 then break;
                        Console_Matrix[y][x]:= WindowManager.Windows[WindowManager.Z_Order[w]]^.buffer[y - WindowManager.Windows[WindowManager.Z_Order[w]]^.WND_Y][x - WindowManager.Windows[WindowManager.Z_Order[w]]^.WND_X];
                        WindowTitleMask[y][x]:= 0;
                        WindowMask[y][x]:= WindowManager.Z_Order[w];
                        ExitMask[y][x]:= 0;
                    end;
                end;
            end;
        end;
    end;

    { Handle any Clicks that have happened since last redraw }
    if UnhandledClick then begin
        if UnhandledClickLeft then begin
            
            SelectedWindow:= ExitMask[MouseYToTile(WindowManager.MousePrev.Y)][MouseXToTile(WindowManager.MousePrev.X)];
            if SelectedWindow <> 0 then begin
                closeWindow(SelectedWindow);
            end else begin
                SelectedWindow:= WindowTitleMask[MouseYToTile(WindowManager.MousePrev.Y)][MouseXToTile(WindowManager.MousePrev.X)];
                if SelectedWindow <> 0 then begin
                    if WindowManager.Windows[SelectedWindow] <> nil then begin
                        if WindowManager.Windows[SelectedWindow]^.ShellWND then FocusZOrder(SelectedWindow);
                    end;
                end else begin
                    SelectedWindow:= WindowMask[MouseYToTile(WindowManager.MousePrev.Y)][MouseXToTile(WindowManager.MousePrev.X)];
                    if (SelectedWindow <> 0) and (WindowManager.Windows[SelectedWindow] <> nil) then begin
                        if (WindowManager.Z_Order[0] = SelectedWindow) or (WindowManager.Windows[SelectedWindow]^.ShellWND = false) then begin
                            if WindowManager.Windows[SelectedWindow]^.Hooks.OnMouseClick <> nil then begin
                                deltax:= MouseXToTile(WindowManager.MousePrev.X) - WindowManager.Windows[SelectedWindow]^.WND_X;
                                deltay:= MouseYToTile(WindowManager.MousePrev.Y) - WindowManager.Windows[SelectedWindow]^.WND_Y;
                                WindowManager.Windows[SelectedWindow]^.Hooks.OnMouseClick(deltax, deltay, true);
                            end;
                        end;
                        if (WindowManager.Z_Order[0] <> SelectedWindow) and (WindowManager.Windows[SelectedWindow]^.ShellWND) then begin
                            FocusZOrder(SelectedWindow);
                        end;
                    end;
                end;
            end;

            {SelectedWindow:= WindowMask[MouseYToTile(WindowManager.MousePrev.Y)][MouseXToTile(WindowManager.MousePrev.X)];
            if (SelectedWindow <> 0) and (WindowManager.Windows[SelectedWindow] <> nil) then begin
                //OnClickHandler(Left)
                if (WindowManager.Z_Order[0] = SelectedWindow) or (WindowManager.Windows[SelectedWindow]^.ShellWND = false) then begin
                    if WindowManager.Windows[SelectedWindow]^.Hooks.OnMouseClick <> nil then begin
                        deltax:= MouseXToTile(WindowManager.MousePrev.X) - WindowManager.Windows[SelectedWindow]^.WND_X;
                        deltay:= MouseYToTile(WindowManager.MousePrev.Y) - WindowManager.Windows[SelectedWindow]^.WND_Y;
                        WindowManager.Windows[SelectedWindow]^.Hooks.OnMouseClick(deltax, deltay, true);
                    end;
                end;
                if (WindowManager.Z_Order[0] <> SelectedWindow) and (WindowManager.Windows[SelectedWindow]^.ShellWND) then begin
                    FocusZOrder(SelectedWindow);
                end;
            end else begin
                SelectedWindow:= WindowTitleMask[MouseYToTile(WindowManager.MousePrev.Y)][MouseXToTile(WindowManager.MousePrev.X)];
                if SelectedWindow <> 0 then begin
                    if WindowManager.Windows[SelectedWindow] <> nil then begin
                        if WindowManager.Windows[SelectedWindow]^.ShellWND then FocusZOrder(SelectedWindow);
                    end;
                end;
                SelectedWindow:= ExitMask[MouseYToTile(WindowManager.MousePrev.Y)][MouseXToTile(WindowManager.MousePrev.X)];
                if SelectedWindow <> 0 then begin
                    closeWindow(SelectedWindow);
                end;
            end;}


        end;
        if not UnhandledClickLeft then begin
            SelectedWindow:= WindowMask[MouseYToTile(WindowManager.MousePrev.Y)][MouseXToTile(WindowManager.MousePrev.X)];
            if (SelectedWindow <> 0) and (WindowManager.Windows[SelectedWindow] <> nil) then begin
                if (WindowManager.Z_Order[0] = SelectedWindow) or (WindowManager.Windows[SelectedWindow]^.ShellWND = false) then begin
                    if WindowManager.Windows[SelectedWindow]^.Hooks.OnMouseClick <> nil then begin
                        deltax:= MouseXToTile(WindowManager.MousePrev.X) - WindowManager.Windows[SelectedWindow]^.WND_X;
                        deltay:= MouseYToTile(WindowManager.MousePrev.Y) - WindowManager.Windows[SelectedWindow]^.WND_Y;
                        WindowManager.Windows[SelectedWindow]^.Hooks.OnMouseClick(deltax, deltay, false);
                    end;
                end;
            end;
        end;
        UnhandledClick:= false;
    end;

    { Handle Moving Windows using MouseDown and Delta positions }
    if MouseDown then begin
        if MovingWindow = 0 then begin
            MovingWindow:= WindowTitleMask[MouseYToTile(WindowManager.MousePrev.Y)][MouseXToTile(WindowManager.MousePrev.X)];
            if MovingWindow <> 0 then begin
                WindowMovePos.x:= MouseXToTile(WindowManager.MousePrev.X);
                WindowMovePos.y:= MouseYToTile(WindowManager.MousePrev.Y);
            end else begin
                MovingWindow:= MAX_WINDOWS;
            end;
        end;
        if MovingWindow <> MAX_WINDOWS then begin
            if WindowManager.Windows[MovingWindow] <> nil then begin
                deltax:= WindowMovePos.x - MouseXToTile(WindowManager.MousePrev.X);
                deltay:= WindowMovePos.y - MouseYToTile(WindowManager.MousePrev.Y);
                WindowMovePos.x:= MouseXToTile(WindowManager.MousePrev.X);
                WindowMovePos.y:= MouseYToTile(WindowManager.MousePrev.Y);
                setWindowPosition(MovingWindow, WindowManager.Windows[MovingWindow]^.WND_X - deltax, WindowManager.Windows[MovingWindow]^.WND_Y - deltay);
                FocusZOrder(MovingWindow);
            end;
        end;
    end else begin
        MovingWindow:= 0;
    end;
    
    { Console_Matrix -> Actual Screen Buffer }
    redrawMatrix;

    { Handle any closed Windows ready for next redraw }
    for w:=0 to MAX_WINDOWS-1 do begin
        if WindowManager.Windows[w] <> nil then begin
            if WindowManager.Windows[w]^.Closed then _closeWindow(w);
        end;
    end;
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
    Window_Border.Attributes:= console.combinecolors($01C3, $07EE);
    Window_Border.visible:= true;

    For w:=0 to MAX_WINDOWS-1 do begin
        WindowManager.Windows[w]:= nil;
        WindowManager.Z_Order[w]:= MAX_WINDOWS;
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
    WND^.Hooks.OnDraw:= nil;
    WND^.Hooks.OnMouseClick:= nil;
    WND^.Hooks.OnMouseMove:= nil;
    WND^.Hooks.OnMouseDown:= nil;
    WND^.Hooks.OnMouseUp:= nil;
    WND^.Hooks.OnKeyPressed:= nil;
    WND^.Hooks.OnClose:= nil;
    WND^.Hooks.OnMinimize:= nil;
    WND^.Hooks.OnFocus:= nil;
    WND^.Hooks.OnLoseFocus:= nil;
    WindowManager.Windows[0]:= WND;
    AddToZOrder(0);
    FocusZOrder(0);
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

procedure keyhook(key_info : TKeyInfo);
begin
    if (key_info.CTRL_DOWN) and (key_info.ALT_DOWN) then begin
        case key_info.key_code of
            uint8('c'):OpenTerminal:=true;
            uint8('r'):resetSystem;
        end;
    end else begin
        if WindowManager.Z_Order[0] <> MAX_WINDOWS then begin
            if WindowManager.Windows[WindowManager.Z_Order[0]] <> nil then begin
                if WindowManager.Windows[WindowManager.Z_Order[0]]^.Hooks.OnKeyPressed <> nil then WindowManager.Windows[WindowManager.Z_Order[0]]^.Hooks.OnKeyPressed(key_info);
            end;
        end;
    end;
end;

procedure init(); [public, alias: 'console_init'];
var
   fb: puint32;

Begin
     fb:= puint32(uint32(multibootinfo^.framebuffer_addr));
     kpalloc(uint32(fb));
     keyboard.hook(@keyhook);
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

procedure writecharex(character: char; attributes: uint32); [public, alias: 'console_writecharex'];
begin
    serial.send(COM1, uint8(character), 10000);
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
     serial.send(COM1, uint8(13), 10000);
     serial.send(COM1, uint8(10), 10000);
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
begin
    writehexpairExWND(b, Console_Properties.Default_Attribute, WND);
end;

procedure writehexpairExWND(b : uint8; Attributes : uint32; WND : uint32);
var
    bn : Array[0..1] of uint8;
    i  : uint8;

begin
    bn[0]:= b SHR 4;
    bn[1]:= b AND $0F;
    for i:=0 to 1 do begin
        case bn[i] of
            0 :writestringExWND('0', Attributes, WND);
            1 :writestringExWND('1', Attributes, WND);
            2 :writestringExWND('2', Attributes, WND);
            3 :writestringExWND('3', Attributes, WND);
            4 :writestringExWND('4', Attributes, WND);
            5 :writestringExWND('5', Attributes, WND);
            6 :writestringExWND('6', Attributes, WND);
            7 :writestringExWND('7', Attributes, WND);
            8 :writestringExWND('8', Attributes, WND);
            9 :writestringExWND('9', Attributes, WND);
            10:writestringExWND('A', Attributes, WND);
            11:writestringExWND('B', Attributes, WND);
            12:writestringExWND('C', Attributes, WND);
            13:writestringExWND('D', Attributes, WND);
            14:writestringExWND('E', Attributes, WND);
            15:writestringExWND('F', Attributes, WND);
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
