{
    Driver->HID->PS2->PS2_Mouse - PS/2 Mouse Driver.

    Handles PS/2 mouse packets and delivers events through
    the abstract mouse API (mouse.setMousePos, mouse.fireMouseEvent, etc.).

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit ps2_mouse;

interface

uses
    tracer,
    mouse,
    syslog,
    video,
    util,
    lmemorymanager,
    strings,
    isrmanager,
    drivermanagement;

type
    PMousePacket = ^TMousePacket;
    TMousePacket = record
        x_movement : sint32;
        y_movement : sint32;
        y_overflow : boolean;
        x_overflow : boolean;
        y_sign     : boolean;
        x_sign     : boolean;
        MMB_Down   : Boolean;
        RMB_Down   : Boolean;
        LMB_Down   : Boolean;
    end;

    TMousePos = record
        x : sint32;
        y : sint32;
    end;

procedure init();

implementation

var
    Current, Last : TMousePos;
    Cycle : uint32 = 0;
    Mouse_Byte : Array[0..3] of uint8;
    Packet : uint32;
    Registered : Boolean = false;
    RMouseDownPos : TMousePos;
    LMouseDownPos : TMousePos;
    LMouseDown : Boolean;
    RMouseDown : Boolean;
    HasScrollWheel : Boolean = false;
    PacketSize : uint32 = 3;

function mouse_wait(w_type : uint8) : boolean;
var
    timeout : uint32;
begin
    timeout := 100;
    if (w_type = 0) then begin
        while (timeout > 0) do begin
            if ((inb($64) AND $01) = $01) then break;
            timeout := timeout - 1;
        end;
    end else begin
        while (timeout > 0) do begin
            if ((inb($64) AND 2) = 0) then break;
            timeout := timeout - 1;
        end;
    end;
    mouse_wait := timeout > 0;
end;

{ Longer timeout for init-time use only (not safe in ISR context) }
function mouse_wait_long(w_type : uint8) : boolean;
var
    timeout : uint32;
begin
    timeout := 100000;
    if (w_type = 0) then begin
        while (timeout > 0) do begin
            if ((inb($64) AND $01) = $01) then break;
            timeout := timeout - 1;
        end;
    end else begin
        while (timeout > 0) do begin
            if ((inb($64) AND 2) = 0) then break;
            timeout := timeout - 1;
        end;
    end;
    mouse_wait_long := timeout > 0;
end;

procedure mouse_write(value : uint8);
begin
    mouse_wait_long(1);
    outb($64, $D4);
    mouse_wait_long(1);
    outb($60, value);
end;

function mouse_read : uint8;
begin
    mouse_wait_long(0);
    mouse_read := inb($60);
end;

procedure main();
var
    i : integer;
    b : byte;
    packet  : TMousePacket;
    x, y, f : byte;
    x32, y32 : sint32;
    r : pchar;
begin
    while mouse_wait(0) do begin
        b := mouse_read;
        if Cycle = 0 then begin
            if (b AND $08) = $08 then begin
                Mouse_Byte[Cycle] := b;
                Inc(Cycle);
            end;
        end else begin
            Mouse_Byte[Cycle] := b;
            Inc(Cycle);
        end;
        if Cycle = PacketSize then begin
            { Process }
            f := Mouse_Byte[0];
            Packet.x_sign := (f AND %00010000) = %00010000;
            Packet.y_sign := (f AND %00100000) = %00100000;
            Packet.MMB_Down := (f AND %00000100) = %00000100;
            Packet.RMB_Down := (f AND %00000010) = %00000010;
            Packet.LMB_Down := (f AND %00000001) = %00000001;
            Packet.x_overflow := (f AND $40) = $40;
            Packet.y_overflow := (f AND $80) = $80;
            Packet.x_movement := Mouse_Byte[1];
            Packet.y_movement := Mouse_Byte[2];
            If Packet.x_sign then Packet.x_movement := sint16(Packet.x_movement OR $FF00);
            If Packet.y_sign then Packet.y_movement := sint16(Packet.y_movement OR $FF00);
            if not(Packet.x_overflow) and not(Packet.y_overflow) then begin
                Current.x := Current.x + Packet.x_movement;
                Current.y := Current.y - Packet.y_movement;
                if Current.x < 0 then Current.x := 0;
                if Current.y < 0 then Current.y := 0;
                if Current.x > sint32(video.frontBufferWidth - 1) then Current.x := sint32(video.frontBufferWidth - 1);
                if Current.y > sint32(video.frontBufferHeight - 1) then Current.y := sint32(video.frontBufferHeight - 1);
            end;
            { Process scroll wheel (4th byte, signed) }
            if HasScrollWheel then begin
                mouse.addScroll(sint8(Mouse_Byte[3]));
            end;
            Cycle := 0;
            if Packet.LMB_Down then begin
                if not LMouseDown then begin
                    LMouseDown := true;
                    LMouseDownPos.x := Current.x;
                    LMouseDownPos.y := Current.y;
                    mouse.setMouseLMB(true);
                    mouse.fireMouseEvent(MOUSE_DOWN_LEFT);
                end;
            end;
            if not Packet.LMB_Down then begin
                if LMouseDown then begin
                    If (Current.x = LMouseDownPos.x) and (Current.y = LMouseDownPos.y) then begin
                        mouse.fireMouseEvent(MOUSE_CLICK_LEFT);
                    end;
                    mouse.setMouseLMB(false);
                    mouse.fireMouseEvent(MOUSE_UP_LEFT);
                    LMouseDown := false;
                end;
            end;
            if Packet.RMB_Down then begin
                if not RMouseDown then begin
                    RMouseDown := true;
                    RMouseDownPos.x := Current.x;
                    RMouseDownPos.y := Current.y;
                    mouse.setMouseRMB(true);
                    mouse.fireMouseEvent(MOUSE_DOWN_RIGHT);
                end;
            end;

            if not Packet.RMB_Down then begin
                if RMouseDown then begin
                    if (Current.x = RMouseDownPos.x) and (Current.y = RMouseDownPos.y) then begin
                        mouse.fireMouseEvent(MOUSE_CLICK_RIGHT);
                    end;
                    mouse.setMouseRMB(false);
                    mouse.fireMouseEvent(MOUSE_UP_RIGHT);
                end;
                RMouseDown := false;
            end;

            mouse.setMousePos(Current.x, Current.y);
            mouse.fireMouseEvent(MOUSE_MOVE);
        end;
    end;
end;

function load(ptr : void) : boolean;
var
    status : uint8;
    devid_byte : uint8;
    tmp : uint8;
begin
    push_trace('ps2_mouse.load');

    { Disable both PS/2 ports while configuring }
    mouse_wait_long(1);
    outb($64, $AD);  { Disable keyboard port }
    mouse_wait_long(1);
    outb($64, $A7);  { Disable mouse port }

    { Flush the output buffer }
    while (inb($64) AND $01) = $01 do begin
        inb($60);
    end;

    { Read Controller Configuration Byte }
    mouse_wait_long(1);
    outb($64, $20);
    mouse_wait_long(0);
    status := inb($60);

    { Enable IRQ12 (bit 1), clear disable-mouse-clock (bit 5) }
    status := status OR $02;
    status := status AND (NOT $20);

    { Write back configuration }
    mouse_wait_long(1);
    outb($64, $60);
    mouse_wait_long(1);
    outb($60, status);

    { Enable auxiliary (mouse) port }
    mouse_wait_long(1);
    outb($64, $A8);

    { Re-enable keyboard port }
    mouse_wait_long(1);
    outb($64, $AE);

    { Reset mouse and wait for self-test }
    mouse_write($FF);
    if mouse_wait_long(0) then begin
        tmp := inb($60);  { ACK ($FA) }
        if mouse_wait_long(0) then begin
            tmp := inb($60);  { Self-test result ($AA = pass) }
            if tmp = $AA then begin
                if mouse_wait_long(0) then begin
                    tmp := inb($60);  { Device ID }
                end;
            end;
        end;
    end;

    { Set defaults }
    mouse_write($F6);
    mouse_read();

    { Enable IntelliMouse scroll wheel: set sample rate 200, 100, 80 }
    mouse_write($F3); mouse_read(); mouse_write(200); mouse_read();
    mouse_write($F3); mouse_read(); mouse_write(100); mouse_read();
    mouse_write($F3); mouse_read(); mouse_write(80);  mouse_read();

    { Query device ID - ID 3 = IntelliMouse (scroll wheel) }
    mouse_write($F2);
    mouse_read(); { ACK }
    devid_byte := mouse_read(); { Device ID }
    if devid_byte = 3 then begin
        HasScrollWheel := true;
        PacketSize := 4;
        syslog.logln('PS/2 MOUSE', 'Scroll wheel enabled (IntelliMouse).');
    end else begin
        HasScrollWheel := false;
        PacketSize := 3;
        syslog.logln('PS/2 MOUSE', 'Standard mouse (no scroll wheel).');
    end;

    mouse_write($F4);
    mouse_read();
    isrmanager.registerISR(44, @Main);
    syslog.logln('PS/2 MOUSE', 'LOADED.');
    syslog.log('PS/2 MOUSE', 'Memory: ');
    syslog.writehexln(uint32(@current));
    load := true;
    pop_trace;
end;

procedure init();
var
    devid : TDeviceIdentifier;
begin
    push_trace('ps2_mouse.init');
    syslog.logln('PS/2 MOUSE', 'INIT BEGIN.');
    devid.bus := biUnknown;
    devid.id0 := 0;
    devid.id1 := 0;
    devid.id2 := 0;
    devid.id3 := 0;
    devid.id4 := 0;
    devid.ex  := nil;
    Current.x := 0;
    Current.y := 0;
    Last.x := 0;
    Last.y := 0;
    drivermanagement.register_driver_ex('PS/2 Mouse', @devid, @load, true);
    syslog.logln('PS/2 MOUSE', 'INIT END.');
    pop_trace;
end;

end.
