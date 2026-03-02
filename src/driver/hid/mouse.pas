{
    Driver->HID->Mouse - Abstract Mouse Input API.

    Owns the global mouse position, button state, and scroll accumulator.
    All mouse drivers (PS/2, USB) push events through the setters and
    fireMouseEvent(). Consumers (LVGL, windows, uidebug) use the getters
    and register hooks via registerMouseHook().

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit mouse;

interface

uses
    video;

type
    TMouseEventType = (
        MOUSE_MOVE,
        MOUSE_DOWN_LEFT,
        MOUSE_UP_LEFT,
        MOUSE_CLICK_LEFT,
        MOUSE_DOWN_RIGHT,
        MOUSE_UP_RIGHT,
        MOUSE_CLICK_RIGHT
    );

    TMouseHookProc = procedure(event: TMouseEventType; x, y: sint32);

{ Getters - safe to call from any context }
function getMouseX: sint32;
function getMouseY: sint32;
function getMouseLMB: boolean;
function getMouseRMB: boolean;
function getMouseScroll: sint32;

{ Setters - called by mouse drivers (PS/2, USB) }
procedure setMousePos(x, y: sint32);
procedure setMouseLMB(down: boolean);
procedure setMouseRMB(down: boolean);
procedure addScroll(delta: sint32);
procedure resetScroll;

{ Hook registration - up to MAX_MOUSE_HOOKS consumers }
function registerMouseHook(hook: TMouseHookProc): boolean;
procedure removeMouseHook(hook: TMouseHookProc);
procedure fireMouseEvent(event: TMouseEventType);

implementation

const
    MAX_MOUSE_HOOKS = 8;

var
    MouseX      : sint32 = 0;
    MouseY      : sint32 = 0;
    MouseLMB    : boolean = false;
    MouseRMB    : boolean = false;
    ScrollAccum : sint32 = 0;
    Hooks       : array[0..MAX_MOUSE_HOOKS-1] of TMouseHookProc;
    HookCount   : uint32 = 0;

function getMouseX: sint32;
begin
    getMouseX := MouseX;
end;

function getMouseY: sint32;
begin
    getMouseY := MouseY;
end;

function getMouseLMB: boolean;
begin
    getMouseLMB := MouseLMB;
end;

function getMouseRMB: boolean;
begin
    getMouseRMB := MouseRMB;
end;

function getMouseScroll: sint32;
begin
    getMouseScroll := ScrollAccum;
    ScrollAccum := 0;
end;

procedure setMousePos(x, y: sint32);
var
    maxW, maxH : sint32;
begin
    maxW := sint32(video.frontBufferWidth);
    maxH := sint32(video.frontBufferHeight);
    if x < 0 then x := 0;
    if y < 0 then y := 0;
    if (maxW > 0) and (x >= maxW) then x := maxW - 1;
    if (maxH > 0) and (y >= maxH) then y := maxH - 1;
    MouseX := x;
    MouseY := y;
end;

procedure setMouseLMB(down: boolean);
begin
    MouseLMB := down;
end;

procedure setMouseRMB(down: boolean);
begin
    MouseRMB := down;
end;

procedure addScroll(delta: sint32);
begin
    ScrollAccum := ScrollAccum + delta;
end;

procedure resetScroll;
begin
    ScrollAccum := 0;
end;

function registerMouseHook(hook: TMouseHookProc): boolean;
begin
    registerMouseHook := false;
    if HookCount < MAX_MOUSE_HOOKS then begin
        Hooks[HookCount] := hook;
        Inc(HookCount);
        registerMouseHook := true;
    end;
end;

procedure removeMouseHook(hook: TMouseHookProc);
var
    i, j: uint32;
begin
    if HookCount = 0 then exit;
    for i := 0 to HookCount - 1 do begin
        if Hooks[i] = hook then begin
            for j := i to HookCount - 2 do begin
                Hooks[j] := Hooks[j + 1];
            end;
            Dec(HookCount);
            Hooks[HookCount] := nil;
            exit;
        end;
    end;
end;

procedure fireMouseEvent(event: TMouseEventType);
var
    i: uint32;
begin
    if HookCount = 0 then exit;
    for i := 0 to HookCount - 1 do begin
        if Hooks[i] <> nil then
            Hooks[i](event, MouseX, MouseY);
    end;
end;

end.
