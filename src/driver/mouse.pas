{ ************************************************
  * Asuro
  * Unit: Drivers/mouse
  * Description: Mouse Driver
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit mouse;

interface

uses 
    console,
    util,
    isr44,
    lmemorymanager,
    strings;

type
    PMousePacket = ^TMousePacket;
    TMousePacket = record
        x_movement : byte;
        y_movement : byte;
        y_overflow : boolean;
        x_overflow : boolean;
        y_sign     : boolean;
        x_sign     : boolean;
        MMB_Down   : Boolean;
        RMB_Down   : Boolean;
        LMB_Down   : Boolean;
    end;

procedure init();

implementation

procedure callback(raw : void);
var
    packet  : PMousePacket;
    x, y, f : byte;
    r : pchar;

begin
    packet:= PMousePacket(kalloc(sizeof(TMousePacket)));
    f:= (uint32(raw) AND $FF000000) SHR 24;
    x:= (uint32(raw) AND $00FF0000) SHR 16;
    y:= (uint32(raw) AND $0000FF00) SHR 8;
    packet^.x_movement:= x;
    packet^.y_movement:= y;
    packet^.y_overflow:= (f AND $80) = $80;
    packet^.x_overflow:= (f AND $40) = $40;
    packet^.y_sign:= (f AND $20) = $20;
    packet^.x_sign:= (f AND $10) = $10;
    packet^.MMB_Down:= (f AND $4) = $4;
    packet^.RMB_Down:= (f AND $2) = $2;
    packet^.LMB_Down:= (f AND $1) = $1;
    //Do Hook here
    // console.writestring('X Movement: ');
    // console.writeintln(packet^.x_movement);

    // console.writestring('Y Movement: ');
    // console.writeintln(packet^.y_movement);

    // console.writestring('Y Overflow: ');
    // r:= boolToString(packet^.y_overflow, true);
    // console.writestringln(r);
    // kfree(void(r));

    // console.writestring('X Overflow: ');
    // r:= boolToString(packet^.x_overflow, true);
    // console.writestringln(r);
    // kfree(void(r));

    // console.writestring('Y Sign: ');
    // r:= boolToString(packet^.y_sign, true);
    // console.writestringln(r);
    // kfree(void(r));

    // console.writestring('X Sign: ');
    // r:= boolToString(packet^.x_sign, true);
    // console.writestringln(r);
    // kfree(void(r));

    // console.writestring('Middle Button Down: ');
    // r:= boolToString(packet^.MMB_Down, true);
    // console.writestringln(r);
    // kfree(void(r));
    
    // console.writestring('Right Button Down: ');
    // r:= boolToString(packet^.RMB_Down, true);
    // console.writestringln(r);
    // kfree(void(r));

    // console.writestring('Left Button Down: ');
    // r:= boolToString(packet^.LMB_Down, true);
    // console.writestringln(r);
    // kfree(void(r));

    kfree(void(packet));
    //console.writestring('Mouse Packet: ');
    //console.writehexln(DWORD(raw));
end;

procedure init();
begin
    isr44.hook(uint32(@callback));
end;

end.