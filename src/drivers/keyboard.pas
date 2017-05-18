{ ************************************************
  * Asuro
  * Unit: Drivers/keyboard
  * Description: Keyboard driver
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }

unit keyboard;

interface

uses 
    console,
    util,
    isr33;


type
    TKeyInfo = packed record 
        key_code : byte;
        pressed : boolean;
    end;

    PKeyInfo = ^TKeyInfo;

var
    key_matrix : array [1..256] of TKeyInfo; 
    key_buffer : array[1..128] of TkeyInfo;
    

procedure init();
procedure callback(scan_code : void);
procedure buffer_push_sc(scan_code : uInt8);

procedure lang_UK();
procedure lang_USA();

implementation

procedure init(keyboard_layout : pchar);  
begin
    memset(uint32(@key_matrix[0]), 0, sizeof(TKeyInfo)*256);
    memset(uint32(@key_buffer), 0, sizeof(TKeyInfo)*128);

    if(keyboard_layout = 'USA') then lang_USA();
    if(keyboard_layout = 'UK') then lang_UK();

    isr33.hook(uint32(@callback));

end;

procedure callback(scan_code : void);
begin
    if key_matrix[uint8(scan_code)].key_code <> 0 then begin
        buffer_push_sc(uint8(scan_code));
        console.writechar(char(key_buffer[0].key_code));
    end;
end;

procedure buffer_push_sc(scan_code : uInt8);
var
    i : uInt8; 
begin
    for i:=127 downto 1 do begin
        key_buffer[i] := key_buffer[i - 1];
    end;

    key_buffer[0] := key_matrix[scan_code];

end;

procedure lang_UK();
begin
end;


procedure lang_USA();
begin
    key_matrix[1].key_code := $1B;
    key_matrix[2].key_code := $31;
    key_matrix[3].key_code := $32;
    key_matrix[4].key_code := $33;
    key_matrix[5].key_code := $34;
    key_matrix[6].key_code := $35;
    key_matrix[7].key_code := $36;
    key_matrix[8].key_code := $37;
    key_matrix[9].key_code := $38;
    key_matrix[10].key_code := $39;
    key_matrix[11].key_code := $30;
    key_matrix[12].key_code := $2D;
    key_matrix[13].key_code := $3D;
    key_matrix[14].key_code := $08;
    key_matrix[15].key_code := $09;
    key_matrix[16].key_code := $71;
    key_matrix[17].key_code := $77;
    key_matrix[18].key_code := $65;
    key_matrix[19].key_code := $72;
    key_matrix[20].key_code := $74;
    key_matrix[21].key_code := $79;
    key_matrix[22].key_code := $75;
    key_matrix[23].key_code := $69;
    key_matrix[24].key_code := $6F;
    key_matrix[25].key_code := $70;
    key_matrix[26].key_code := $5B;
    key_matrix[27].key_code := $5D;
    key_matrix[28].key_code := $0D;
    key_matrix[29].key_code := $00; //no ascii
    key_matrix[30].key_code := $61;
    key_matrix[31].key_code := $73;
    key_matrix[32].key_code := $64;
    key_matrix[33].key_code := $66;
    key_matrix[34].key_code := $67;
    key_matrix[35].key_code := $68;
    key_matrix[36].key_code := $6A;
    key_matrix[37].key_code := $6B;
    key_matrix[38].key_code := $6C;
    key_matrix[39].key_code := $3B;
    key_matrix[40].key_code := $27;
    key_matrix[41].key_code := $60;
    key_matrix[42].key_code := $00; //no ascii
    key_matrix[43].key_code := $5C;
    key_matrix[44].key_code := $7A;
    key_matrix[45].key_code := $78;
    key_matrix[46].key_code := $63;
    key_matrix[47].key_code := $76;
    key_matrix[48].key_code := $62;
    key_matrix[49].key_code := $6E;
    key_matrix[50].key_code := $6D;
    key_matrix[51].key_code := $2C;
    key_matrix[52].key_code := $2E;
    key_matrix[53].key_code := $2F;
    key_matrix[54].key_code := $00; //no ascii
    key_matrix[55].key_code := $2A;
    key_matrix[56].key_code := $00; //no ascii
    key_matrix[57].key_code := $20;
    key_matrix[58].key_code := $00; //no ascii
    key_matrix[59].key_code := $3B;
    key_matrix[60].key_code := $3C;
    key_matrix[61].key_code := $3D;
    key_matrix[62].key_code := $3E;
    key_matrix[63].key_code := $3F;
    key_matrix[64].key_code := $40;
    key_matrix[65].key_code := $41;
    key_matrix[66].key_code := $42;
    key_matrix[67].key_code := $43;
    key_matrix[68].key_code := $44;

    key_matrix[87].key_code := $85;
    key_matrix[88].key_code := $86;
end;

end.