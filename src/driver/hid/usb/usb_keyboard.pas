{
    Driver->Bus->USB->USB_Keyboard - USB HID Boot Keyboard Class Driver.

    Registers with drivermanagement as a USB class driver matching
    HID boot keyboard devices (class $03, subclass $01, protocol $01).
    Uses boot protocol with 8-byte reports.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit usb_keyboard;

interface

uses
    usbtypes,
    usbcore,
    keyboard,
    ps2_keyboard,
    drivermanagement,
    lmemorymanager,
    lists,
    tracer,
    syslog,
    strings,
    util;

procedure init;
procedure poll_keyboards;
procedure UnitTest;

implementation

{ ========================= Constants ========================= }

const
    { HID Class Requests }
    HID_REQ_GET_REPORT    = $01;
    HID_REQ_SET_REPORT    = $09;
    HID_REQ_GET_IDLE      = $02;
    HID_REQ_SET_IDLE      = $0A;
    HID_REQ_GET_PROTOCOL  = $03;
    HID_REQ_SET_PROTOCOL  = $0B;

    { HID Protocol Values }
    HID_PROTOCOL_BOOT     = 0;
    HID_PROTOCOL_REPORT   = 1;

    { Boot keyboard report size }
    KB_REPORT_SIZE        = 8;

    { Modifier key bits (byte 0 of boot report) }
    KB_MOD_LCTRL          = $01;
    KB_MOD_LSHIFT         = $02;
    KB_MOD_LALT           = $04;
    KB_MOD_LGUI           = $08;
    KB_MOD_RCTRL          = $10;
    KB_MOD_RSHIFT         = $20;
    KB_MOD_RALT           = $40;
    KB_MOD_RGUI           = $80;

    { Maximum simultaneous keyboards }
    MAX_USB_KEYBOARDS     = 4; { Only used for unit test sizing }

    { Maximum keys tracked for rollover }
    MAX_KEYS              = 6;

{ ========================= Types ========================= }

type
    PUSBKeyboardData = ^TUSBKeyboardData;
    TUSBKeyboardData = record
        Device       : PUSBDevice;
        IntrEP       : TUSBEndpoint;
        HasIntrEP    : boolean;
        ReportBuf    : array[0..KB_REPORT_SIZE-1] of uint8;
        PrevReport   : array[0..KB_REPORT_SIZE-1] of uint8;
        Transfer     : PUSBTransfer;
        Active       : boolean;
        FailCount    : uint32;
    end;

{ ========================= Globals ========================= }

var
    KeyboardList : PLinkedListBase;

{ ========================= HID Usage to ASCII Translation ========================= }

{ USB HID Usage Page 7 (Keyboard) to ASCII lookup table.
  Index = HID usage code, value = ASCII character (lowercase).
  0 = no mapping. }
const
    HID_TO_ASCII : array[0..103] of uint8 = (
        { $00 } 0,    { Reserved (no event) }
        { $01 } 0,    { ErrorRollOver }
        { $02 } 0,    { POSTFail }
        { $03 } 0,    { ErrorUndefined }
        { $04 } $61,  { a }
        { $05 } $62,  { b }
        { $06 } $63,  { c }
        { $07 } $64,  { d }
        { $08 } $65,  { e }
        { $09 } $66,  { f }
        { $0A } $67,  { g }
        { $0B } $68,  { h }
        { $0C } $69,  { i }
        { $0D } $6A,  { j }
        { $0E } $6B,  { k }
        { $0F } $6C,  { l }
        { $10 } $6D,  { m }
        { $11 } $6E,  { n }
        { $12 } $6F,  { o }
        { $13 } $70,  { p }
        { $14 } $71,  { q }
        { $15 } $72,  { r }
        { $16 } $73,  { s }
        { $17 } $74,  { t }
        { $18 } $75,  { u }
        { $19 } $76,  { v }
        { $1A } $77,  { w }
        { $1B } $78,  { x }
        { $1C } $79,  { y }
        { $1D } $7A,  { z }
        { $1E } $31,  { 1 }
        { $1F } $32,  { 2 }
        { $20 } $33,  { 3 }
        { $21 } $34,  { 4 }
        { $22 } $35,  { 5 }
        { $23 } $36,  { 6 }
        { $24 } $37,  { 7 }
        { $25 } $38,  { 8 }
        { $26 } $39,  { 9 }
        { $27 } $30,  { 0 }
        { $28 } $0D,  { Enter }
        { $29 } $1B,  { Escape }
        { $2A } $08,  { Backspace }
        { $2B } $09,  { Tab }
        { $2C } $20,  { Space }
        { $2D } $2D,  { - }
        { $2E } $3D,  { = }
        { $2F } $5B,  { [ }
        { $30 } $5D,  { ] }
        { $31 } $5C,  { \ }
        { $32 } 0,    { Non-US # }
        { $33 } $3B,  { ; }
        { $34 } $27,  { ' }
        { $35 } $60,  { ` }
        { $36 } $2C,  { , }
        { $37 } $2E,  { . }
        { $38 } $2F,  { / }
        { $39 } 0,    { Caps Lock }
        { $3A } 0,    { F1 }
        { $3B } 0,    { F2 }
        { $3C } 0,    { F3 }
        { $3D } 0,    { F4 }
        { $3E } 0,    { F5 }
        { $3F } 0,    { F6 }
        { $40 } 0,    { F7 }
        { $41 } 0,    { F8 }
        { $42 } 0,    { F9 }
        { $43 } 0,    { F10 }
        { $44 } 0,    { F11 }
        { $45 } 0,    { F12 }
        { $46 } 0,    { PrintScreen }
        { $47 } 0,    { ScrollLock }
        { $48 } 0,    { Pause }
        { $49 } 0,    { Insert }
        { $4A } 0,    { Home }
        { $4B } 0,    { PageUp }
        { $4C } $7F,  { Delete }
        { $4D } 0,    { End }
        { $4E } 0,    { PageDown }
        { $4F } $14,  { Right Arrow }
        { $50 } $13,  { Left Arrow }
        { $51 } $12,  { Down Arrow }
        { $52 } $10,  { Up Arrow }
        { $53 } 0,    { Num Lock }
        { $54 } $2F,  { KP / }
        { $55 } $2A,  { KP * }
        { $56 } $2D,  { KP - }
        { $57 } $2B,  { KP + }
        { $58 } $0D,  { KP Enter }
        { $59 } $31,  { KP 1 }
        { $5A } $32,  { KP 2 }
        { $5B } $33,  { KP 3 }
        { $5C } $34,  { KP 4 }
        { $5D } $35,  { KP 5 }
        { $5E } $36,  { KP 6 }
        { $5F } $37,  { KP 7 }
        { $60 } $38,  { KP 8 }
        { $61 } $39,  { KP 9 }
        { $62 } $30,  { KP 0 }
        { $63 } $2E,  { KP . }
        { $64 } $5C,  { Non-US \ }
        { $65 } 0,    { Application }
        { $66 } 0,    { Power }
        { $67 } $3D   { KP = }
    );

    { Shifted variants for keys $04..$38 (letters + numbers + symbols) }
    HID_TO_ASCII_SHIFT : array[0..103] of uint8 = (
        { $00 } 0,
        { $01 } 0,
        { $02 } 0,
        { $03 } 0,
        { $04 } $41,  { A }
        { $05 } $42,  { B }
        { $06 } $43,  { C }
        { $07 } $44,  { D }
        { $08 } $45,  { E }
        { $09 } $46,  { F }
        { $0A } $47,  { G }
        { $0B } $48,  { H }
        { $0C } $49,  { I }
        { $0D } $4A,  { J }
        { $0E } $4B,  { K }
        { $0F } $4C,  { L }
        { $10 } $4D,  { M }
        { $11 } $4E,  { N }
        { $12 } $4F,  { O }
        { $13 } $50,  { P }
        { $14 } $51,  { Q }
        { $15 } $52,  { R }
        { $16 } $53,  { S }
        { $17 } $54,  { T }
        { $18 } $55,  { U }
        { $19 } $56,  { V }
        { $1A } $57,  { W }
        { $1B } $58,  { X }
        { $1C } $59,  { Y }
        { $1D } $5A,  { Z }
        { $1E } $21,  { ! }
        { $1F } $40,  { @ }
        { $20 } $23,  { # }
        { $21 } $24,  { $ }
        { $22 } $25,  { % }
        { $23 } $5E,  { ^ }
        { $24 } $26,  { & }
        { $25 } $2A,  { * }
        { $26 } $28,  { ( }
        { $27 } $29,  { ) }
        { $28 } $0D,  { Enter }
        { $29 } $1B,  { Escape }
        { $2A } $08,  { Backspace }
        { $2B } $09,  { Tab }
        { $2C } $20,  { Space }
        { $2D } $5F,  { _ }
        { $2E } $2B,  { + }
        { $2F } $7B,  { lbrace }
        { $30 } $7D,  { rbrace }
        { $31 } $7C,  { | }
        { $32 } 0,    { Non-US # }
        { $33 } $3A,  { : }
        { $34 } $22,  { " }
        { $35 } $7E,  { ~ }
        { $36 } $3C,  { < }
        { $37 } $3E,  { > }
        { $38 } $3F,  { ? }
        { $39 } 0,    { Caps Lock }
        { $3A } 0,    { F1 }
        { $3B } 0,    { F2 }
        { $3C } 0,    { F3 }
        { $3D } 0,    { F4 }
        { $3E } 0,    { F5 }
        { $3F } 0,    { F6 }
        { $40 } 0,    { F7 }
        { $41 } 0,    { F8 }
        { $42 } 0,    { F9 }
        { $43 } 0,    { F10 }
        { $44 } 0,    { F11 }
        { $45 } 0,    { F12 }
        { $46 } 0,
        { $47 } 0,
        { $48 } 0,
        { $49 } 0,
        { $4A } 0,
        { $4B } 0,
        { $4C } $7F,  { Delete }
        { $4D } 0,
        { $4E } 0,
        { $4F } $14,
        { $50 } $13,
        { $51 } $12,
        { $52 } $10,
        { $53 } 0,
        { $54 } $2F,
        { $55 } $2A,
        { $56 } $2D,
        { $57 } $2B,
        { $58 } $0D,
        { $59 } $31,
        { $5A } $32,
        { $5B } $33,
        { $5C } $34,
        { $5D } $35,
        { $5E } $36,
        { $5F } $37,
        { $60 } $38,
        { $61 } $39,
        { $62 } $30,
        { $63 } $2E,
        { $64 } $7C,
        { $65 } 0,
        { $66 } 0,
        { $67 } $3D
    );

{ ========================= Helper Functions ========================= }

{ Convert a HID usage code to ASCII, considering modifier state. }
function hid_usage_to_ascii(usage : uint8; shifted : boolean) : uint8;
begin
    hid_usage_to_ascii := 0;
    if usage > 103 then exit;
    if shifted then
        hid_usage_to_ascii := HID_TO_ASCII_SHIFT[usage]
    else
        hid_usage_to_ascii := HID_TO_ASCII[usage];
end;

{ Check if a key usage code is present in the previous report keys (bytes 2..7). }
function key_was_pressed(kb : PUSBKeyboardData; usage : uint8) : boolean;
var
    i : uint32;
begin
    key_was_pressed := false;
    for i := 2 to 7 do begin
        if kb^.PrevReport[i] = usage then begin
            key_was_pressed := true;
            exit;
        end;
    end;
end;

{ Check if a key usage code is present in the current report keys (bytes 2..7). }
function key_is_pressed(kb : PUSBKeyboardData; usage : uint8) : boolean;
var
    i : uint32;
begin
    key_is_pressed := false;
    for i := 2 to 7 do begin
        if kb^.ReportBuf[i] = usage then begin
            key_is_pressed := true;
            exit;
        end;
    end;
end;

{ Process a completed boot keyboard report. }
procedure process_report(kb : PUSBKeyboardData);
var
    modifiers : uint8;
    shifted   : boolean;
    ctrl, alt : boolean;
    i         : uint32;
    usage     : uint8;
    ascii     : uint8;
    info      : TKeyInfo;
begin
    modifiers := kb^.ReportBuf[0];
    shifted := ((modifiers AND KB_MOD_LSHIFT) <> 0) or
               ((modifiers AND KB_MOD_RSHIFT) <> 0);

    ctrl  := ((modifiers AND KB_MOD_LCTRL) <> 0) or
              ((modifiers AND KB_MOD_RCTRL) <> 0);
    alt   := ((modifiers AND KB_MOD_LALT) <> 0) or
              ((modifiers AND KB_MOD_RALT) <> 0);

    { Process newly pressed keys (in current but not in previous) }
    for i := 2 to 7 do begin
        usage := kb^.ReportBuf[i];
        if (usage <> 0) and (not key_was_pressed(kb, usage)) then begin
            ascii := hid_usage_to_ascii(usage, shifted);
            if ascii <> 0 then begin
                info.key_code     := ascii;
                info.is_down_code := true;
                info.SHIFT_DOWN   := shifted;
                info.CTRL_DOWN    := ctrl;
                info.ALT_DOWN     := alt;
                keyboard.reportKeyEvent(info);
            end;
        end;
    end;

    { Process released keys (in previous but not in current) }
    for i := 2 to 7 do begin
        usage := kb^.PrevReport[i];
        if (usage <> 0) and (not key_is_pressed(kb, usage)) then begin
            ascii := hid_usage_to_ascii(usage, shifted);
            if ascii <> 0 then begin
                info.key_code     := ascii;
                info.is_down_code := false;
                info.SHIFT_DOWN   := shifted;
                info.CTRL_DOWN    := ctrl;
                info.ALT_DOWN     := alt;
                keyboard.reportKeyEvent(info);
            end;
        end;
    end;

    { Save current report as previous for next comparison }
    memcpy(uint32(@kb^.ReportBuf[0]), uint32(@kb^.PrevReport[0]), KB_REPORT_SIZE);
end;

{ ========================= Disconnect Handler ========================= }

procedure unload(dev : PUSBDevice);
var
    i    : uint32;
    kb   : PUSBKeyboardData;
    cnt  : uint32;
begin
    if KeyboardList = nil then exit;
    cnt := LL_Size(KeyboardList);
    i := 0;
    while i < cnt do begin
        kb := PUSBKeyboardData(LL_Get(KeyboardList, i));
        if (kb <> nil) and (kb^.Device = dev) then begin
            syslog.logln('USBKeyboard', 'Device disconnected, deactivating.');
            if kb^.Transfer <> nil then begin
                kfree(void(kb^.Transfer));
                kb^.Transfer := nil;
            end;
            kb^.Device := nil;
            kb^.Active := false;
            LL_Delete(KeyboardList, i);
            dec(cnt);
        end else
            inc(i);
    end;
end;

{ ========================= Polling ========================= }

procedure poll_keyboards;
var
    i     : uint32;
    cnt   : uint32;
    kb    : PUSBKeyboardData;
begin
    if KeyboardList = nil then exit;
    cnt := LL_Size(KeyboardList);
    i := 0;
    while i < cnt do begin
        kb := PUSBKeyboardData(LL_Get(KeyboardList, i));
        if (kb = nil) or (not kb^.Active) or (not kb^.HasIntrEP) or (kb^.Device = nil) then begin
            inc(i);
            continue;
        end;

        if kb^.Transfer <> nil then begin
            if kb^.Transfer^.Status = tsSuccess then begin
                { Got a report — process it }
                kb^.FailCount := 0;
                process_report(kb);
                { Free old transfer and resubmit }
                kfree(void(kb^.Transfer));
                kb^.Transfer := usb_interrupt_transfer(
                    kb^.Device, @kb^.IntrEP,
                    @kb^.ReportBuf[0], KB_REPORT_SIZE);
            end else if (kb^.Transfer^.Status <> tsInProgress) and
                        (kb^.Transfer^.Status <> tsNotStarted) then begin
                { Transfer failed (stall, error, etc.) }
                inc(kb^.FailCount);
                kfree(void(kb^.Transfer));
                if kb^.FailCount >= 3 then begin
                    { Too many consecutive failures — device likely unplugged }
                    syslog.logln('USBKeyboard', 'Too many failures, deactivating.');
                    kb^.Transfer := nil;
                    kb^.Active := false;
                    kb^.Device := nil;
                    LL_Delete(KeyboardList, i);
                    dec(cnt);
                    continue;
                end else begin
                    kb^.Transfer := usb_interrupt_transfer(
                        kb^.Device, @kb^.IntrEP,
                        @kb^.ReportBuf[0], KB_REPORT_SIZE);
                end;
            end;
            { tsInProgress / tsNotStarted — still waiting, do nothing }
        end;
        inc(i);
    end;
end;

{ ========================= Driver Load ========================= }

function load(ptr : void) : boolean;
var
    dev     : PUSBDevice;
    kb      : PUSBKeyboardData;
    status  : TUSBTransferStatus;
    i       : uint32;
begin
    push_trace('usb_keyboard.load');
    load := false;

    dev := PUSBDevice(ptr);
    if dev = nil then begin
        pop_trace;
        exit;
    end;

    syslog.logln('USBKeyboard', 'Configuring USB keyboard...');

    kb := PUSBKeyboardData(LL_Add(KeyboardList));
    kb^.Device    := dev;
    kb^.HasIntrEP := false;
    kb^.Active    := false;
    kb^.Transfer  := nil;
    kb^.FailCount := 0;

    { Clear report buffers }
    for i := 0 to KB_REPORT_SIZE - 1 do begin
        kb^.ReportBuf[i]  := 0;
        kb^.PrevReport[i] := 0;
    end;

    { SET_PROTOCOL(Boot) — request type: class, recipient: interface }
    status := usb_control_msg(dev,
        USB_REQTYPE_DIR_OUT OR USB_REQTYPE_TYPE_CLASS OR USB_REQTYPE_REC_INTERFACE,
        HID_REQ_SET_PROTOCOL,
        HID_PROTOCOL_BOOT,   { wValue = boot protocol }
        0,                    { wIndex = interface 0 }
        nil, 0);
    if status <> tsSuccess then begin
        syslog.logln('USBKeyboard', 'SET_PROTOCOL(Boot) failed, continuing anyway.');
    end;

    { SET_IDLE(0) — infinite idle duration (report only on change) }
    status := usb_control_msg(dev,
        USB_REQTYPE_DIR_OUT OR USB_REQTYPE_TYPE_CLASS OR USB_REQTYPE_REC_INTERFACE,
        HID_REQ_SET_IDLE,
        0,                    { wValue = 0 (infinite) }
        0,                    { wIndex = interface 0 }
        nil, 0);
    if status <> tsSuccess then begin
        syslog.logln('USBKeyboard', 'SET_IDLE failed, continuing anyway.');
    end;

    { Find the interrupt IN endpoint }
    for i := 0 to dev^.NumEndpoints - 1 do begin
        if (dev^.Endpoints[i].PipeType = ptInterrupt) and
           (dev^.Endpoints[i].Direction = dirIn) then begin
            kb^.IntrEP    := dev^.Endpoints[i];
            kb^.HasIntrEP := true;
            break;
        end;
    end;

    if not kb^.HasIntrEP then begin
        syslog.logln('USBKeyboard', 'No interrupt IN endpoint found.');
        pop_trace;
        exit;
    end;

    { Start first interrupt transfer }
    kb^.Transfer := usb_interrupt_transfer(
        dev, @kb^.IntrEP,
        @kb^.ReportBuf[0], KB_REPORT_SIZE);

    { Register disconnect callback }
    dev^.fnDisconnect := TUSBDisconnectCallback(@unload);

    kb^.Active := true;

    syslog.log('USBKeyboard', 'Keyboard ready (EP');
    syslog.writeint(kb^.IntrEP.Address);
    syslog.writestring(', MaxPkt=');
    syslog.writeint(kb^.IntrEP.MaxPacket);
    syslog.writestringln(').');

    { Disable PS/2 keyboard to prevent duplicate input from USB legacy emulation }
    ps2_keyboard.disable;

    load := true;
    pop_trace;
end;

{ ========================= Init ========================= }

procedure init;
var
    KBID : TDeviceIdentifier;
begin
    push_trace('usb_keyboard.init');
    syslog.logln('USBKeyboard', 'INIT BEGIN.');

    KeyboardList := LL_New(sizeof(TUSBKeyboardData));

    { Register as a USB class driver matching HID boot keyboard }
    { id2 = bInterfaceClass = $03 (HID) }
    { id3 = bInterfaceSubClass = $01 (Boot) }
    { id4 = bInterfaceProtocol = $01 (Keyboard) }
    KBID.Bus := biUSB;
    KBID.id0 := idANY;                { Any VID:PID }
    KBID.id1 := $FFFFFFFF;            { Any device class }
    KBID.id2 := USB_CLASS_HID;        { bInterfaceClass = $03 }
    KBID.id3 := USB_HID_SUBCLASS_BOOT;{ bInterfaceSubClass = $01 }
    KBID.id4 := USB_HID_PROTO_KEYBOARD; { bInterfaceProtocol = $01 }
    KBID.ex  := nil;

    drivermanagement.register_driver('USB Keyboard Driver', @KBID, @load);

    { Register completion hook so HC ISRs trigger keyboard polling }
    usbcore.register_completion_hook(usbcore.TUSBCompletionHook(@poll_keyboards));

    syslog.logln('USBKeyboard', 'INIT END.');
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
            syslog.logln('USBKeyboard', msg);
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
        syslog.logln('USBKeyboard', msg);
        kfree(void(msg));
        kfree(void(pStr));
        kfree(void(fStr));
    end;

var
    testKB : TUSBKeyboardData;
    ascii  : uint8;
    i      : uint32;
begin
    passed := 0;
    failed := 0;
    syslog.logln('USBKeyboard', 'Unit tests starting...');

    { === HID Constants === }
    Assert(HID_REQ_SET_PROTOCOL = $0B, 'SET_PROTOCOL request code');
    Assert(HID_REQ_SET_IDLE = $0A, 'SET_IDLE request code');
    Assert(HID_PROTOCOL_BOOT = 0, 'BOOT protocol value');
    Assert(KB_REPORT_SIZE = 8, 'Boot report size');

    { === Modifier bit masks === }
    Assert(KB_MOD_LCTRL = $01, 'LCTRL bit');
    Assert(KB_MOD_LSHIFT = $02, 'LSHIFT bit');
    Assert(KB_MOD_LALT = $04, 'LALT bit');
    Assert(KB_MOD_RCTRL = $10, 'RCTRL bit');
    Assert(KB_MOD_RSHIFT = $20, 'RSHIFT bit');
    Assert(KB_MOD_RALT = $40, 'RALT bit');

    { === HID usage to ASCII (unshifted) === }
    Assert(hid_usage_to_ascii($04, false) = $61, 'a unshifted');
    Assert(hid_usage_to_ascii($1D, false) = $7A, 'z unshifted');
    Assert(hid_usage_to_ascii($1E, false) = $31, '1 unshifted');
    Assert(hid_usage_to_ascii($27, false) = $30, '0 unshifted');
    Assert(hid_usage_to_ascii($28, false) = $0D, 'Enter unshifted');
    Assert(hid_usage_to_ascii($29, false) = $1B, 'Escape unshifted');
    Assert(hid_usage_to_ascii($2A, false) = $08, 'Backspace unshifted');
    Assert(hid_usage_to_ascii($2B, false) = $09, 'Tab unshifted');
    Assert(hid_usage_to_ascii($2C, false) = $20, 'Space unshifted');

    { === HID usage to ASCII (shifted) === }
    Assert(hid_usage_to_ascii($04, true) = $41, 'A shifted');
    Assert(hid_usage_to_ascii($1D, true) = $5A, 'Z shifted');
    Assert(hid_usage_to_ascii($1E, true) = $21, '! shifted');
    Assert(hid_usage_to_ascii($1F, true) = $40, '@ shifted');
    Assert(hid_usage_to_ascii($20, true) = $23, '# shifted');
    Assert(hid_usage_to_ascii($2D, true) = $5F, '_ shifted');
    Assert(hid_usage_to_ascii($2E, true) = $2B, '+ shifted');

    { === Out of range === }
    Assert(hid_usage_to_ascii(104, false) = 0, 'usage 104 out of range');
    Assert(hid_usage_to_ascii(200, false) = 0, 'usage 200 out of range');
    Assert(hid_usage_to_ascii(0, false) = 0, 'usage 0 = no event');

    { === Key tracking functions === }
    for i := 0 to KB_REPORT_SIZE - 1 do begin
        testKB.ReportBuf[i]  := 0;
        testKB.PrevReport[i] := 0;
    end;

    { Simulate: previous had key $04 (a) in slot 2, current has $05 (b) in slot 2 }
    testKB.PrevReport[2] := $04;
    testKB.ReportBuf[2]  := $05;
    Assert(key_was_pressed(@testKB, $04) = true, 'key_was_pressed finds $04');
    Assert(key_was_pressed(@testKB, $05) = false, 'key_was_pressed misses $05');
    Assert(key_is_pressed(@testKB, $05) = true, 'key_is_pressed finds $05');
    Assert(key_is_pressed(@testKB, $04) = false, 'key_is_pressed misses $04');

    { Multiple keys in report }
    testKB.ReportBuf[3] := $06;
    testKB.ReportBuf[4] := $07;
    Assert(key_is_pressed(@testKB, $06) = true, 'key_is_pressed finds $06 in slot 3');
    Assert(key_is_pressed(@testKB, $07) = true, 'key_is_pressed finds $07 in slot 4');
    Assert(key_is_pressed(@testKB, $08) = false, 'key_is_pressed misses $08');

    { === Symbol keys unshifted === }
    Assert(hid_usage_to_ascii($2D, false) = $2D, '- unshifted');
    Assert(hid_usage_to_ascii($2E, false) = $3D, '= unshifted');
    Assert(hid_usage_to_ascii($2F, false) = $5B, '[ unshifted');
    Assert(hid_usage_to_ascii($30, false) = $5D, '] unshifted');
    Assert(hid_usage_to_ascii($31, false) = $5C, 'backslash unshifted');
    Assert(hid_usage_to_ascii($33, false) = $3B, '; unshifted');
    Assert(hid_usage_to_ascii($34, false) = $27, 'apostrophe unshifted');
    Assert(hid_usage_to_ascii($35, false) = $60, 'backtick unshifted');
    Assert(hid_usage_to_ascii($36, false) = $2C, ', unshifted');
    Assert(hid_usage_to_ascii($37, false) = $2E, '. unshifted');
    Assert(hid_usage_to_ascii($38, false) = $2F, '/ unshifted');

    { === Symbol keys shifted === }
    Assert(hid_usage_to_ascii($33, true) = $3A, ': shifted');
    Assert(hid_usage_to_ascii($34, true) = $22, 'dquote shifted');
    Assert(hid_usage_to_ascii($35, true) = $7E, '~ shifted');
    Assert(hid_usage_to_ascii($36, true) = $3C, '< shifted');
    Assert(hid_usage_to_ascii($37, true) = $3E, '> shifted');
    Assert(hid_usage_to_ascii($38, true) = $3F, '? shifted');
    Assert(hid_usage_to_ascii($2F, true) = $7B, 'lbrace shifted');
    Assert(hid_usage_to_ascii($30, true) = $7D, 'rbrace shifted');
    Assert(hid_usage_to_ascii($31, true) = $7C, 'pipe shifted');

    { === Function keys and special keys have no ASCII === }
    Assert(hid_usage_to_ascii($39, false) = 0, 'CapsLock no ASCII');
    Assert(hid_usage_to_ascii($3A, false) = 0, 'F1 no ASCII');
    Assert(hid_usage_to_ascii($45, false) = 0, 'F12 no ASCII');

    { === Keypad === }
    Assert(hid_usage_to_ascii($58, false) = $0D, 'KP Enter');
    Assert(hid_usage_to_ascii($54, false) = $2F, 'KP /');
    Assert(hid_usage_to_ascii($55, false) = $2A, 'KP *');

    PrintSummary;
end;

end.
