{
    Driver->HID->PS2->PS2_Keyboard - PS/2 Keyboard Driver.

    Handles PS/2 scan code translation and delivers key events
    through the abstract keyboard API (keyboard.reportKeyEvent).

    @author(Aaron Hance <ah@aaronhance.me>)
    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit ps2_keyboard;

interface

uses
    keyboard,
    syslog,
    util,
    PS2_KEYBOARD_ISR;

var
    key_matrix       : array [1..256] of TKeyInfo;
    key_matrix_shift : array [1..256] of TKeyInfo;

procedure init(keyboard_layout : array of TKeyInfo);
procedure disable;
procedure lang_USA();

implementation

uses
    drivermanagement;

procedure callback(scan_code : void);
var
    info     : TKeyInfo;
    raw      : uint8;
    baseCode : uint8;
    isBreak  : boolean;
begin
    raw := uint8(scan_code);

    { In PS/2 scancode set 1, bit 7 set = key release (break code) }
    isBreak  := (raw AND $80) <> 0;
    baseCode := raw AND $7F;

    { Update modifier state (use raw codes so both make/break are handled) }
    if raw = 42  then keyboard.is_shift := true;
    if raw = 170 then keyboard.is_shift := false;
    if raw = 29  then keyboard.is_ctrl  := true;
    if raw = 157 then keyboard.is_ctrl  := false;
    if raw = 56  then keyboard.is_alt   := true;
    if raw = 184 then keyboard.is_alt   := false;

    info.SHIFT_DOWN    := keyboard.is_shift;
    info.CTRL_DOWN     := keyboard.is_ctrl;
    info.ALT_DOWN      := keyboard.is_alt;
    info.is_down_code  := not isBreak;

    if keyboard.is_shift then begin
        if key_matrix_shift[baseCode].key_code <> 0 then begin
            info.key_code := key_matrix_shift[baseCode].key_code;
            keyboard.reportKeyEvent(info);
        end;
    end else begin
        if key_matrix[baseCode].key_code <> 0 then begin
            info.key_code := key_matrix[baseCode].key_code;
            keyboard.reportKeyEvent(info);
        end;
    end;
end;

function load(ptr : void) : boolean;
begin
    PS2_KEYBOARD_ISR.register();
    PS2_KEYBOARD_ISR.hook(uint32(@callback));
    syslog.logln('PS/2 KEYBOARD', 'LOADED.');
    load := true;
end;

procedure disable;
begin
    PS2_KEYBOARD_ISR.unhook(uint32(@callback));
    syslog.logln('PS/2 KEYBOARD', 'Disabled (USB keyboard active).');
end;

procedure init(keyboard_layout : array of TKeyInfo);
var
    devid : TDeviceIdentifier;
begin
    syslog.logln('PS/2 KEYBOARD', 'INIT BEGIN.');
    if keyboard_layout[1].key_code = 0 then lang_USA();
    devid.bus := biUnknown;
    devid.id0 := 0;
    devid.id1 := 0;
    devid.id2 := 0;
    devid.id3 := 0;
    devid.id4 := 0;
    devid.ex  := nil;
    drivermanagement.register_driver_ex('PS/2 Keyboard', @devid, @load, true);
    syslog.logln('PS/2 KEYBOARD', 'INIT END.');
end;

procedure lang_USA();
begin
    key_matrix[1].key_code := $1B;
    key_matrix[1].is_down_code := true;
    key_matrix[2].key_code := $31;
    key_matrix[2].is_down_code := true;
    key_matrix[3].key_code := $32;
    key_matrix[3].is_down_code := true;
    key_matrix[4].key_code := $33;
    key_matrix[4].is_down_code := true;
    key_matrix[5].key_code := $34;
    key_matrix[5].is_down_code := true;
    key_matrix[6].key_code := $35;
    key_matrix[6].is_down_code := true;
    key_matrix[7].key_code := $36;
    key_matrix[7].is_down_code := true;
    key_matrix[8].key_code := $37;
    key_matrix[8].is_down_code := true;
    key_matrix[9].key_code := $38;
    key_matrix[9].is_down_code := true;
    key_matrix[10].key_code := $39;
    key_matrix[10].is_down_code := true;
    key_matrix[11].key_code := $30;
    key_matrix[11].is_down_code := true;
    key_matrix[12].key_code := $2D;
    key_matrix[12].is_down_code := true;
    key_matrix[13].key_code := $3D;
    key_matrix[13].is_down_code := true;
    key_matrix[14].key_code := $08;
    key_matrix[14].is_down_code := true;
    key_matrix[15].key_code := $09;
    key_matrix[15].is_down_code := true;
    key_matrix[16].key_code := $71;
    key_matrix[16].is_down_code := true;
    key_matrix[17].key_code := $77;
    key_matrix[17].is_down_code := true;
    key_matrix[18].key_code := $65;
    key_matrix[18].is_down_code := true;
    key_matrix[19].key_code := $72;
    key_matrix[19].is_down_code := true;
    key_matrix[20].key_code := $74;
    key_matrix[20].is_down_code := true;
    key_matrix[21].key_code := $79;
    key_matrix[21].is_down_code := true;
    key_matrix[22].key_code := $75;
    key_matrix[22].is_down_code := true;
    key_matrix[23].key_code := $69;
    key_matrix[23].is_down_code := true;
    key_matrix[24].key_code := $6F;
    key_matrix[24].is_down_code := true;
    key_matrix[25].key_code := $70;
    key_matrix[25].is_down_code := true;
    key_matrix[26].key_code := $5B;
    key_matrix[26].is_down_code := true;
    key_matrix[27].key_code := $5D;
    key_matrix[27].is_down_code := true;
    key_matrix[28].key_code := $0D;
    key_matrix[28].is_down_code := true;
    key_matrix[29].key_code := $00;
    key_matrix[29].is_down_code := true; { no ascii }
    key_matrix[30].key_code := $61;
    key_matrix[30].is_down_code := true;
    key_matrix[31].key_code := $73;
    key_matrix[31].is_down_code := true;
    key_matrix[32].key_code := $64;
    key_matrix[32].is_down_code := true;
    key_matrix[33].key_code := $66;
    key_matrix[33].is_down_code := true;
    key_matrix[34].key_code := $67;
    key_matrix[34].is_down_code := true;
    key_matrix[35].key_code := $68;
    key_matrix[35].is_down_code := true;
    key_matrix[36].key_code := $6A;
    key_matrix[36].is_down_code := true;
    key_matrix[37].key_code := $6B;
    key_matrix[37].is_down_code := true;
    key_matrix[38].key_code := $6C;
    key_matrix[38].is_down_code := true;
    key_matrix[39].key_code := $3B;
    key_matrix[39].is_down_code := true;
    key_matrix[40].key_code := $27;
    key_matrix[40].is_down_code := true;
    key_matrix[41].key_code := $60;
    key_matrix[41].is_down_code := true;
    key_matrix[42].key_code := $00;
    key_matrix[42].is_down_code := true; { no ascii, SHIFT DOWN }
    key_matrix[43].key_code := $5C;
    key_matrix[43].is_down_code := true;
    key_matrix[44].key_code := $7A;
    key_matrix[44].is_down_code := true;
    key_matrix[45].key_code := $78;
    key_matrix[45].is_down_code := true;
    key_matrix[46].key_code := $63;
    key_matrix[46].is_down_code := true;
    key_matrix[47].key_code := $76;
    key_matrix[47].is_down_code := true;
    key_matrix[48].key_code := $62;
    key_matrix[48].is_down_code := true;
    key_matrix[49].key_code := $6E;
    key_matrix[49].is_down_code := true;
    key_matrix[50].key_code := $6D;
    key_matrix[50].is_down_code := true;
    key_matrix[51].key_code := $2C;
    key_matrix[51].is_down_code := true;
    key_matrix[52].key_code := $2E;
    key_matrix[52].is_down_code := true;
    key_matrix[53].key_code := $2F;
    key_matrix[53].is_down_code := true;
    key_matrix[54].key_code := $00;
    key_matrix[54].is_down_code := true; { no ascii }
    key_matrix[55].key_code := $2A;
    key_matrix[55].is_down_code := true;
    key_matrix[56].key_code := $00;
    key_matrix[56].is_down_code := true; { no ascii }
    key_matrix[57].key_code := $20;
    key_matrix[57].is_down_code := true;
    key_matrix[58].key_code := $00;
    key_matrix[58].is_down_code := true; { no ascii }
    key_matrix[59].key_code := $3B;
    key_matrix[59].is_down_code := true;
    key_matrix[60].key_code := $3C;
    key_matrix[60].is_down_code := true;
    key_matrix[61].key_code := $3D;
    key_matrix[61].is_down_code := true;
    key_matrix[62].key_code := $3E;
    key_matrix[62].is_down_code := true;
    key_matrix[63].key_code := $3F;
    key_matrix[63].is_down_code := true;
    key_matrix[64].key_code := $40;
    key_matrix[64].is_down_code := true;
    key_matrix[65].key_code := $41;
    key_matrix[65].is_down_code := true;
    key_matrix[66].key_code := $42;
    key_matrix[66].is_down_code := true;
    key_matrix[67].key_code := $43;
    key_matrix[67].is_down_code := true;
    key_matrix[68].key_code := $44;
    key_matrix[68].is_down_code := true;
    key_matrix[69].key_code := $44;
    key_matrix[69].is_down_code := true;
    key_matrix[70].key_code := $44;
    key_matrix[70].is_down_code := true;
    key_matrix[71].key_code := $44;
    key_matrix[71].is_down_code := true;
    key_matrix[72].key_code := $10;
    key_matrix[72].is_down_code := true;
    key_matrix[73].key_code := $44;
    key_matrix[73].is_down_code := true;
    key_matrix[74].key_code := $44;
    key_matrix[74].is_down_code := true;
    key_matrix[75].key_code := $13;
    key_matrix[75].is_down_code := true;
    key_matrix[76].key_code := $44;
    key_matrix[76].is_down_code := true;
    key_matrix[77].key_code := $14;
    key_matrix[77].is_down_code := true;
    key_matrix[78].key_code := $85;
    key_matrix[78].is_down_code := true;
    key_matrix[79].key_code := $86;
    key_matrix[79].is_down_code := true;
    key_matrix[80].key_code := $12;
    key_matrix[80].is_down_code := true;
    key_matrix[81].key_code := $86;
    key_matrix[81].is_down_code := true;
    key_matrix[82].key_code := $86;
    key_matrix[82].is_down_code := true;
    key_matrix[83].key_code := $86;
    key_matrix[83].is_down_code := true;
    key_matrix[84].key_code := $86;
    key_matrix[84].is_down_code := true;
    key_matrix[85].key_code := $86;
    key_matrix[85].is_down_code := true;
    key_matrix[86].key_code := $86;
    key_matrix[86].is_down_code := true;
    key_matrix[87].key_code := $86;
    key_matrix[87].is_down_code := true;
    key_matrix[88].key_code := $86;
    key_matrix[88].is_down_code := true;
    key_matrix[89].key_code := $86;
    key_matrix[89].is_down_code := true;
    key_matrix[90].key_code := $86;
    key_matrix[90].is_down_code := true;
    key_matrix[91].key_code := $86;
    key_matrix[91].is_down_code := true;
    key_matrix[92].key_code := $86;
    key_matrix[92].is_down_code := true;

    key_matrix[170].key_code := $00; { no ascii, SHIFT UP }
    key_matrix[170].is_down_code := false;

    { Shifted variants }
    key_matrix_shift[2].key_code := $21;
    key_matrix_shift[3].key_code := $40;
    key_matrix_shift[4].key_code := $23;
    key_matrix_shift[5].key_code := $24;
    key_matrix_shift[6].key_code := $25;
    key_matrix_shift[7].key_code := $5E;
    key_matrix_shift[8].key_code := $26;
    key_matrix_shift[9].key_code := $2A;
    key_matrix_shift[10].key_code := $28;
    key_matrix_shift[11].key_code := $29;
    key_matrix_shift[12].key_code := $5F;
    key_matrix_shift[13].key_code := $2B;

    key_matrix_shift[16].key_code := $51;
    key_matrix_shift[17].key_code := $57;
    key_matrix_shift[18].key_code := $45;
    key_matrix_shift[19].key_code := $52;
    key_matrix_shift[20].key_code := $54;
    key_matrix_shift[21].key_code := $59;
    key_matrix_shift[22].key_code := $55;
    key_matrix_shift[23].key_code := $49;
    key_matrix_shift[24].key_code := $4F;
    key_matrix_shift[25].key_code := $50;
    key_matrix_shift[26].key_code := $7B;
    key_matrix_shift[27].key_code := $7D;

    key_matrix_shift[30].key_code := $41;
    key_matrix_shift[31].key_code := $53;
    key_matrix_shift[32].key_code := $44;
    key_matrix_shift[33].key_code := $46;
    key_matrix_shift[34].key_code := $47;
    key_matrix_shift[35].key_code := $48;
    key_matrix_shift[36].key_code := $4A;
    key_matrix_shift[37].key_code := $4B;
    key_matrix_shift[38].key_code := $4C;
    key_matrix_shift[39].key_code := $3A;
    key_matrix_shift[40].key_code := $22;
    key_matrix_shift[41].key_code := $7E;

    key_matrix_shift[43].key_code := $7C;
    key_matrix_shift[44].key_code := $5A;
    key_matrix_shift[45].key_code := $58;
    key_matrix_shift[46].key_code := $43;
    key_matrix_shift[47].key_code := $56;
    key_matrix_shift[48].key_code := $42;
    key_matrix_shift[49].key_code := $4E;
    key_matrix_shift[50].key_code := $4D;
    key_matrix_shift[51].key_code := $3C;
    key_matrix_shift[52].key_code := $3E;
    key_matrix_shift[53].key_code := $3F;
end;

end.
