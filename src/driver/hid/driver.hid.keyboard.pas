{
    Driver->HID->Keyboard - Abstract Keyboard Input API.

    Provides the unified driver.hid.keyboard interface for the system.
    All driver.hid.keyboard drivers (PS/2, driver.bus.usb) push key events through
    reportKeyEvent(). Consumers (LVGL, app.vterminal, etc.) register
    a single hook via hook() to receive all driver.hid.keyboard input
    regardless of the underlying hardware.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.hid.keyboard;

interface

type
    TKeyInfo = packed record
        key_code     : byte;
        is_down_code : boolean; { true when pressing down, false when releasing }
        SHIFT_DOWN   : boolean;
        CTRL_DOWN    : boolean;
        ALT_DOWN     : boolean;
    end;

    PKeyInfo       = ^TKeyInfo;
    pp_hook_method = procedure(key_info : TKeyInfo);

var
    captin_hook : pp_hook_method = nil;
    is_shift    : boolean = false;
    is_ctrl     : boolean = false;
    is_alt      : boolean = false;

{ Register a hook to receive all driver.hid.keyboard events. }
procedure hook(proc : pp_hook_method);

{ Called by driver.hid.keyboard drivers (PS/2, driver.bus.usb) to deliver a key event.
  Dispatches to the registered hook. Updates global modifier state. }
procedure reportKeyEvent(info : TKeyInfo);

implementation

procedure hook(proc : pp_hook_method);
begin
    captin_hook := proc;
end;

procedure reportKeyEvent(info : TKeyInfo);
begin
    { Update global modifier state from the event }
    is_shift := info.SHIFT_DOWN;
    is_ctrl  := info.CTRL_DOWN;
    is_alt   := info.ALT_DOWN;

    if captin_hook <> nil then
        captin_hook(info);
end;

end.
