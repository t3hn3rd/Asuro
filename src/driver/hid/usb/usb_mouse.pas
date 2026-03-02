{
    Driver->Bus->USB->USB_Mouse - USB HID Boot Mouse Class Driver.

    Registers with drivermanagement as a USB class driver matching
    HID boot mouse devices (class $03, subclass $01, protocol $02).
    Uses boot protocol with 3/4-byte reports.
    Integrates with mouse API for position/button/scroll state.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit usb_mouse;

interface

uses
    usbtypes,
    usbcore,
    mouse,
    drivermanagement,
    lmemorymanager,
    lists,
    tracer,
    syslog,
    strings,
    util;

procedure init;
procedure poll_mice;
procedure UnitTest;

implementation

{ ========================= Constants ========================= }

const
    { HID Class Requests }
    HID_REQ_SET_PROTOCOL  = $0B;
    HID_REQ_SET_IDLE      = $0A;

    { HID Protocol Values }
    HID_PROTOCOL_BOOT     = 0;

    { Boot mouse report: at least 3 bytes, may have 4th for wheel }
    MOUSE_REPORT_SIZE     = 4;

    { Mouse button bits (byte 0 of boot report) }
    MOUSE_BTN_LEFT        = $01;
    MOUSE_BTN_RIGHT       = $02;
    MOUSE_BTN_MIDDLE      = $04;

    { Maximum simultaneous mice }
    MAX_USB_MICE          = 4; { Only used for unit test sizing }

{ ========================= Types ========================= }

type
    PUSBMouseData = ^TUSBMouseData;
    TUSBMouseData = record
        Device      : PUSBDevice;
        IntrEP      : TUSBEndpoint;
        HasIntrEP   : boolean;
        ReportBuf   : array[0..MOUSE_REPORT_SIZE-1] of uint8;
        Transfer    : PUSBTransfer;
        Active      : boolean;
        FailCount   : uint32;
        PrevLMB     : boolean;
        PrevRMB     : boolean;
        PosX        : sint32;
        PosY        : sint32;
    end;

{ ========================= Globals ========================= }

var
    MouseList : PLinkedListBase;

{ ========================= Helper Functions ========================= }

{ Extract signed X delta from boot mouse report byte 1. }
function mouse_delta_x(report : Pointer) : sint32;
var
    raw : uint8;
begin
    raw := PUint8(uint32(report) + 1)^;
    if raw < 128 then
        mouse_delta_x := sint32(raw)
    else
        mouse_delta_x := sint32(raw) - 256;
end;

{ Extract signed Y delta from boot mouse report byte 2. }
function mouse_delta_y(report : Pointer) : sint32;
var
    raw : uint8;
begin
    raw := PUint8(uint32(report) + 2)^;
    if raw < 128 then
        mouse_delta_y := sint32(raw)
    else
        mouse_delta_y := sint32(raw) - 256;
end;

{ Extract signed scroll delta from boot mouse report byte 3 (if present). }
function mouse_scroll(report : Pointer; reportLen : uint32) : sint32;
var
    raw : uint8;
begin
    mouse_scroll := 0;
    if reportLen < 4 then exit;
    raw := PUint8(uint32(report) + 3)^;
    if raw < 128 then
        mouse_scroll := sint32(raw)
    else
        mouse_scroll := sint32(raw) - 256;
end;

{ Extract button state from boot mouse report byte 0. }
function mouse_buttons(report : Pointer) : uint8;
begin
    mouse_buttons := PUint8(report)^;
end;

{ ========================= Report Processing ========================= }

procedure process_report(ms : PUSBMouseData; reportLen : uint32);
var
    btns    : uint8;
    dx, dy  : sint32;
    scroll  : sint32;
    lmb, rmb : boolean;
    lmbDown, lmbUp : boolean;
    rmbDown, rmbUp : boolean;
begin
    btns := mouse_buttons(@ms^.ReportBuf[0]);
    dx   := mouse_delta_x(@ms^.ReportBuf[0]);
    dy   := mouse_delta_y(@ms^.ReportBuf[0]);
    scroll := mouse_scroll(@ms^.ReportBuf[0], reportLen);

    lmb := (btns AND MOUSE_BTN_LEFT) <> 0;
    rmb := (btns AND MOUSE_BTN_RIGHT) <> 0;

    { Update position }
    ms^.PosX := ms^.PosX + dx;
    ms^.PosY := ms^.PosY + dy;
    mouse.setMousePos(ms^.PosX, ms^.PosY);
    { Re-read clamped position back }
    ms^.PosX := mouse.getMouseX;
    ms^.PosY := mouse.getMouseY;

    { Detect button transitions }
    lmbDown := lmb and (not ms^.PrevLMB);
    lmbUp   := (not lmb) and ms^.PrevLMB;
    rmbDown := rmb and (not ms^.PrevRMB);
    rmbUp   := (not rmb) and ms^.PrevRMB;

    { Update button state }
    if lmbDown then begin
        mouse.setMouseLMB(true);
        mouse.fireMouseEvent(MOUSE_DOWN_LEFT);
    end;
    if lmbUp then begin
        mouse.setMouseLMB(false);
        mouse.fireMouseEvent(MOUSE_CLICK_LEFT);
        mouse.fireMouseEvent(MOUSE_UP_LEFT);
    end;
    if rmbDown then begin
        mouse.setMouseRMB(true);
        mouse.fireMouseEvent(MOUSE_DOWN_RIGHT);
    end;
    if rmbUp then begin
        mouse.setMouseRMB(false);
        mouse.fireMouseEvent(MOUSE_CLICK_RIGHT);
        mouse.fireMouseEvent(MOUSE_UP_RIGHT);
    end;

    { Scroll wheel }
    if scroll <> 0 then begin
        mouse.addScroll(scroll);
    end;

    { Fire move event if there was movement }
    if (dx <> 0) or (dy <> 0) then begin
        mouse.fireMouseEvent(MOUSE_MOVE);
    end;

    ms^.PrevLMB := lmb;
    ms^.PrevRMB := rmb;
end;

{ ========================= Polling ========================= }

{ ========================= Disconnect Handler ========================= }

procedure unload(dev : PUSBDevice);
var
    i    : uint32;
    ms   : PUSBMouseData;
    cnt  : uint32;
begin
    if MouseList = nil then exit;
    cnt := LL_Size(MouseList);
    i := 0;
    while i < cnt do begin
        ms := PUSBMouseData(LL_Get(MouseList, i));
        if (ms <> nil) and (ms^.Device = dev) then begin
            syslog.logln('USBMouse', 'Device disconnected, deactivating.');
            if ms^.Transfer <> nil then begin
                kfree(void(ms^.Transfer));
                ms^.Transfer := nil;
            end;
            ms^.Device := nil;
            ms^.Active := false;
            LL_Delete(MouseList, i);
            dec(cnt);
        end else
            inc(i);
    end;
end;

procedure poll_mice;
var
    i      : uint32;
    cnt    : uint32;
    ms     : PUSBMouseData;
    repLen : uint32;
begin
    if MouseList = nil then exit;
    cnt := LL_Size(MouseList);
    i := 0;
    while i < cnt do begin
        ms := PUSBMouseData(LL_Get(MouseList, i));
        if (ms = nil) or (not ms^.Active) or (not ms^.HasIntrEP) or (ms^.Device = nil) then begin
            inc(i);
            continue;
        end;

        if ms^.Transfer <> nil then begin
            if ms^.Transfer^.Status = tsSuccess then begin
                { Determine actual report length }
                ms^.FailCount := 0;
                repLen := ms^.Transfer^.ActualLen;
                if repLen < 3 then repLen := 3;
                if repLen > MOUSE_REPORT_SIZE then repLen := MOUSE_REPORT_SIZE;
                process_report(ms, repLen);
                { Free old transfer and resubmit }
                kfree(void(ms^.Transfer));
                ms^.Transfer := usb_interrupt_transfer(
                    ms^.Device, @ms^.IntrEP,
                    @ms^.ReportBuf[0], MOUSE_REPORT_SIZE);
            end else if (ms^.Transfer^.Status <> tsInProgress) and
                        (ms^.Transfer^.Status <> tsNotStarted) then begin
                { Transfer failed }
                inc(ms^.FailCount);
                kfree(void(ms^.Transfer));
                if ms^.FailCount >= 3 then begin
                    syslog.logln('USBMouse', 'Too many failures, deactivating.');
                    ms^.Transfer := nil;
                    ms^.Active := false;
                    ms^.Device := nil;
                    LL_Delete(MouseList, i);
                    dec(cnt);
                    continue;
                end else begin
                    ms^.Transfer := usb_interrupt_transfer(
                        ms^.Device, @ms^.IntrEP,
                        @ms^.ReportBuf[0], MOUSE_REPORT_SIZE);
                end;
            end;
        end;
        inc(i);
    end;
end;

{ ========================= Driver Load ========================= }

function load(ptr : void) : boolean;
var
    dev    : PUSBDevice;
    ms     : PUSBMouseData;
    status : TUSBTransferStatus;
    i      : uint32;
begin
    push_trace('usb_mouse.load');
    load := false;

    dev := PUSBDevice(ptr);
    if dev = nil then begin
        pop_trace;
        exit;
    end;

    syslog.logln('USBMouse', 'Configuring USB mouse...');

    ms := PUSBMouseData(LL_Add(MouseList));
    ms^.Device    := dev;
    ms^.HasIntrEP := false;
    ms^.Active    := false;
    ms^.Transfer  := nil;
    ms^.FailCount := 0;
    ms^.PrevLMB   := false;
    ms^.PrevRMB   := false;
    ms^.PosX      := mouse.getMouseX;
    ms^.PosY      := mouse.getMouseY;

    { Clear report buffer }
    for i := 0 to MOUSE_REPORT_SIZE - 1 do
        ms^.ReportBuf[i] := 0;

    { SET_PROTOCOL(Boot) }
    status := usb_control_msg(dev,
        USB_REQTYPE_DIR_OUT OR USB_REQTYPE_TYPE_CLASS OR USB_REQTYPE_REC_INTERFACE,
        HID_REQ_SET_PROTOCOL,
        HID_PROTOCOL_BOOT,
        0,
        nil, 0);
    if status <> tsSuccess then begin
        syslog.logln('USBMouse', 'SET_PROTOCOL(Boot) failed, continuing anyway.');
    end;

    { SET_IDLE(0) }
    status := usb_control_msg(dev,
        USB_REQTYPE_DIR_OUT OR USB_REQTYPE_TYPE_CLASS OR USB_REQTYPE_REC_INTERFACE,
        HID_REQ_SET_IDLE,
        0,
        0,
        nil, 0);
    if status <> tsSuccess then begin
        syslog.logln('USBMouse', 'SET_IDLE failed, continuing anyway.');
    end;

    { Find the interrupt IN endpoint }
    for i := 0 to dev^.NumEndpoints - 1 do begin
        if (dev^.Endpoints[i].PipeType = ptInterrupt) and
           (dev^.Endpoints[i].Direction = dirIn) then begin
            ms^.IntrEP    := dev^.Endpoints[i];
            ms^.HasIntrEP := true;
            break;
        end;
    end;

    if not ms^.HasIntrEP then begin
        syslog.logln('USBMouse', 'No interrupt IN endpoint found.');
        pop_trace;
        exit;
    end;

    { Start first interrupt transfer }
    ms^.Transfer := usb_interrupt_transfer(
        dev, @ms^.IntrEP,
        @ms^.ReportBuf[0], MOUSE_REPORT_SIZE);

    { Register disconnect callback }
    dev^.fnDisconnect := TUSBDisconnectCallback(@unload);

    ms^.Active := true;

    syslog.log('USBMouse', 'Mouse ready (EP');
    syslog.writeint(ms^.IntrEP.Address);
    syslog.writestring(', MaxPkt=');
    syslog.writeint(ms^.IntrEP.MaxPacket);
    syslog.writestringln(').');
    load := true;
    pop_trace;
end;

{ ========================= Init ========================= }

procedure init;
var
    MouseID : TDeviceIdentifier;
begin
    push_trace('usb_mouse.init');
    syslog.logln('USBMouse', 'INIT BEGIN.');

    MouseList := LL_New(sizeof(TUSBMouseData));

    { Register as a USB class driver matching HID boot mouse }
    { id2 = bInterfaceClass = $03 (HID) }
    { id3 = bInterfaceSubClass = $01 (Boot) }
    { id4 = bInterfaceProtocol = $02 (Mouse) }
    MouseID.Bus := biUSB;
    MouseID.id0 := idANY;                 { Any VID:PID }
    MouseID.id1 := $FFFFFFFF;             { Any device class }
    MouseID.id2 := USB_CLASS_HID;         { bInterfaceClass = $03 }
    MouseID.id3 := USB_HID_SUBCLASS_BOOT; { bInterfaceSubClass = $01 }
    MouseID.id4 := USB_HID_PROTO_MOUSE;   { bInterfaceProtocol = $02 }
    MouseID.ex  := nil;

    drivermanagement.register_driver('USB Mouse Driver', @MouseID, @load);

    { Register completion hook so HC ISRs trigger mouse polling }
    usbcore.register_completion_hook(usbcore.TUSBCompletionHook(@poll_mice));

    syslog.logln('USBMouse', 'INIT END.');
    pop_trace;
end;

{ ========================= Unit Tests ========================= }

procedure UnitTest;
var
    passed, failed : uint32;

    procedure Assert(condition : boolean; testName : pchar);
    var
        msg : pchar;
    begin
        if condition then begin
            inc(passed);
        end else begin
            inc(failed);
            msg := stringConcat('FAIL: ', testName);
            syslog.logln('USBMouse', msg);
            kfree(void(msg));
        end;
    end;

    procedure PrintSummary;
    var
        pStr, fStr, msg, tmp : pchar;
    begin
        pStr := intToString(passed);
        fStr := intToString(failed);
        msg := stringConcat(pStr, ' passed, ');
        tmp := stringConcat(msg, fStr);
        kfree(void(msg));
        msg := stringConcat(tmp, ' failed.');
        kfree(void(tmp));
        syslog.logln('USBMouse', msg);
        kfree(void(msg));
        kfree(void(pStr));
        kfree(void(fStr));
    end;

var
    report : array[0..3] of uint8;
    dx, dy, sc : sint32;
    btns   : uint8;
begin
    passed := 0;
    failed := 0;
    syslog.logln('USBMouse', 'Unit tests starting...');

    { === Constants === }
    Assert(MOUSE_BTN_LEFT = $01, 'BTN_LEFT bit');
    Assert(MOUSE_BTN_RIGHT = $02, 'BTN_RIGHT bit');
    Assert(MOUSE_BTN_MIDDLE = $04, 'BTN_MIDDLE bit');
    Assert(MOUSE_REPORT_SIZE = 4, 'report size');
    Assert(HID_REQ_SET_PROTOCOL = $0B, 'SET_PROTOCOL code');
    Assert(HID_PROTOCOL_BOOT = 0, 'BOOT protocol');

    { === Delta X extraction === }
    { Positive X }
    report[0] := 0; report[1] := 10; report[2] := 0; report[3] := 0;
    dx := mouse_delta_x(@report[0]);
    Assert(dx = 10, 'delta_x positive 10');

    { Negative X (-5 = 251 unsigned) }
    report[1] := 251;
    dx := mouse_delta_x(@report[0]);
    Assert(dx = -5, 'delta_x negative -5');

    { Zero X }
    report[1] := 0;
    dx := mouse_delta_x(@report[0]);
    Assert(dx = 0, 'delta_x zero');

    { Max positive X (127) }
    report[1] := 127;
    dx := mouse_delta_x(@report[0]);
    Assert(dx = 127, 'delta_x max positive');

    { Max negative X (-128 = 128 unsigned) }
    report[1] := 128;
    dx := mouse_delta_x(@report[0]);
    Assert(dx = -128, 'delta_x max negative');

    { === Delta Y extraction === }
    report[1] := 0;

    { Positive Y }
    report[2] := 20;
    dy := mouse_delta_y(@report[0]);
    Assert(dy = 20, 'delta_y positive 20');

    { Negative Y (-10 = 246 unsigned) }
    report[2] := 246;
    dy := mouse_delta_y(@report[0]);
    Assert(dy = -10, 'delta_y negative -10');

    { Zero Y }
    report[2] := 0;
    dy := mouse_delta_y(@report[0]);
    Assert(dy = 0, 'delta_y zero');

    { === Scroll extraction === }
    { Scroll up (+1) }
    report[3] := 1;
    sc := mouse_scroll(@report[0], 4);
    Assert(sc = 1, 'scroll up +1');

    { Scroll down (-1 = 255 unsigned) }
    report[3] := 255;
    sc := mouse_scroll(@report[0], 4);
    Assert(sc = -1, 'scroll down -1');

    { No scroll byte (3-byte report) }
    sc := mouse_scroll(@report[0], 3);
    Assert(sc = 0, 'scroll 3-byte report = 0');

    { Zero scroll }
    report[3] := 0;
    sc := mouse_scroll(@report[0], 4);
    Assert(sc = 0, 'scroll zero');

    { === Button extraction === }
    report[0] := MOUSE_BTN_LEFT;
    btns := mouse_buttons(@report[0]);
    Assert((btns AND MOUSE_BTN_LEFT) <> 0, 'LMB set');
    Assert((btns AND MOUSE_BTN_RIGHT) = 0, 'RMB clear');
    Assert((btns AND MOUSE_BTN_MIDDLE) = 0, 'MMB clear');

    report[0] := MOUSE_BTN_LEFT OR MOUSE_BTN_RIGHT;
    btns := mouse_buttons(@report[0]);
    Assert((btns AND MOUSE_BTN_LEFT) <> 0, 'LMB+RMB: LMB set');
    Assert((btns AND MOUSE_BTN_RIGHT) <> 0, 'LMB+RMB: RMB set');

    report[0] := MOUSE_BTN_MIDDLE;
    btns := mouse_buttons(@report[0]);
    Assert((btns AND MOUSE_BTN_MIDDLE) <> 0, 'MMB set');
    Assert((btns AND MOUSE_BTN_LEFT) = 0, 'MMB: LMB clear');

    report[0] := $07; { all buttons }
    btns := mouse_buttons(@report[0]);
    Assert((btns AND MOUSE_BTN_LEFT) <> 0, 'all: LMB set');
    Assert((btns AND MOUSE_BTN_RIGHT) <> 0, 'all: RMB set');
    Assert((btns AND MOUSE_BTN_MIDDLE) <> 0, 'all: MMB set');

    report[0] := 0;
    btns := mouse_buttons(@report[0]);
    Assert(btns = 0, 'no buttons');

    { === Combined report === }
    report[0] := MOUSE_BTN_LEFT; report[1] := 5; report[2] := 250; report[3] := 1;
    btns := mouse_buttons(@report[0]);
    dx := mouse_delta_x(@report[0]);
    dy := mouse_delta_y(@report[0]);
    sc := mouse_scroll(@report[0], 4);
    Assert((btns AND MOUSE_BTN_LEFT) <> 0, 'combined: LMB');
    Assert(dx = 5, 'combined: dx=5');
    Assert(dy = -6, 'combined: dy=-6');
    Assert(sc = 1, 'combined: scroll=1');

    PrintSummary;
end;

end.
