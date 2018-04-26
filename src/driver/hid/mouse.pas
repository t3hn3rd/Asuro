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
    tracer,
    console,
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
procedure DrawCursor;

implementation

var
    Current, Last : TMousePos;
    FirstDraw : boolean = true;
    BackPixels : Array[0..1] of Array[0..1] of uint16;
    Cycle : uint32 = 0;
    Mouse_Byte : Array[0..2] of uint8;
    Packet : uint32;
    Registered : Boolean = false;
    NeedsRedraw : Boolean = false;

procedure DrawCursor;
var
    x, y : uint32;
    nx, ny : uint32;

begin 
    nx:= Current.x;
    ny:= Current.y;
    if not NeedsRedraw then exit;
    NeedsRedraw:= false;
    if not FirstDraw then begin
        for y:=0 to 1 do begin
            for x:=0 to 1 do begin
                DrawPixel(Last.x + x, Last.y + y, BackPixels[x][y]);
            end;
        end;        
    end;
    Last.x:= nx;
    Last.y:= ny;
    for y:=0 to 1 do begin
        for x:=0 to 1 do begin
            BackPixels[x][y]:= GetPixel(nx + x, ny + y);
            DrawPixel(nx + x, ny + y, $FFFF);
        end;
    end;
    FirstDraw:= false;
end;

function mouse_wait(w_type : uint8) : boolean;
var
    timeout : uint32;

begin
    timeout:= 100;
    if (w_type = 0) then begin
        while (timeout > 0) do begin
            if ((inb($64) AND $01) = $01) then break;
            timeout:= timeout-1;
        end;
    end else begin
        while (timeout > 0) do begin
            if ((inb($64) AND 2) = 0) then break;
            timeout := timeout - 1;
        end;
    end;
    mouse_wait:= timeout > 0;
end;

procedure mouse_write(value : uint8);
begin
    mouse_wait(1);
    outb($64, $D4);
    mouse_wait(1);
    outb($60, value);
end;

function mouse_read : uint8;
begin
    mouse_wait(0);
    mouse_read:= inb($60);
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
    //push_trace('mouse.main');
    while mouse_wait(0) do begin
        b:= mouse_read;
        if Cycle = 0 then begin
            if (b AND $08) = $08 then begin
                Mouse_Byte[Cycle]:= b;
                Inc(Cycle);
            end;
        end else begin
            Mouse_Byte[Cycle]:= b;
            Inc(Cycle);
        end;
        if Cycle = 3 then begin
            //Process
            f:= Mouse_Byte[0];
            //Packet.x_movement:= Mouse_Byte[1];
            //Packet.y_movement:= Mouse_Byte[2];
            Packet.x_sign:= (f AND %00010000) = %00010000;
            Packet.y_sign:= (f AND %00100000) = %00100000;
            Packet.x_overflow:= (f AND $40) = $40;
            Packet.y_overflow:= (f AND $80) = $80;
            Packet.x_movement:= Mouse_Byte[1] - ((f SHL 4) AND $100);//Packet.x_movement div 4;
            Packet.y_movement:= Mouse_Byte[2] - ((f SHL 3) AND $100);//Packet.y_movement div 4;
            //if Packet.x_movement < 1 then Packet.x_movement:= 1;
            //if Packet.y_movement < 1 then Packet.y_movement:= 1;
            if not(Packet.x_overflow) and not(Packet.y_overflow) then begin
                Current.x:= Current.x + Packet.x_movement;
                Current.y:= Current.y + Packet.y_movement;            
                {If (Packet.x_sign) and (Packet.x_movement > 0) then begin
                    dec(Current.x, Packet.x_movement);
                end;
                If not(Packet.x_sign) and (Packet.x_movement > 0) then begin
                    inc(Current.x, Packet.x_movement);
                end;
                If not(Packet.y_sign) and (Packet.y_movement > 0) then begin
                    dec(Current.y, Packet.y_movement);
                end;
                If (Packet.y_sign) and (Packet.y_movement > 0) then begin
                    inc(Current.y, Packet.y_movement);
                end;}
                if Current.x < 0 then Current.x:= 0;
                if Current.y < 0 then Current.y:= 0;
                if Current.x > 1279 then Current.x:= 1279;
                if Current.y > 1023 then Current.y:= 1023;
                //console.writestring('Mouse X: ');
                //console.writeintln(current.x);
                //console.writestring('Mouse Y: ');
                //console.writeintln(current.y);
                //DrawCursor;
            end;
            Cycle:= 0;
            NeedsRedraw:= true;
        end;
    end;
end;

function load(ptr : void) : boolean;
var
    status : uint8; 
begin
    push_trace('mouse.load');
    mouse_wait(1);
    outb($64, $A8);
    mouse_wait(1);
    outb($64, $20); 
    mouse_wait(0);
    status:= inb($60) OR $02;
    mouse_wait(1);
    outb($64, $60);
    mouse_wait(1);
    outb($60, status);
    mouse_write($F6);
    mouse_read();
    mouse_write($F4);
    mouse_read();
    isrmanager.registerISR(44, @Main);
    console.outputln('PS/2 MOUSE', 'LOADED.'); 
    console.output('PS/2 MOUSE', 'Memory: ');
    console.writehexln(uint32(@current));
    load:= true;
    pop_trace;
end;

procedure init();
var
    devid : TDeviceIdentifier;

begin
    push_trace('mouse.init');
    console.outputln('PS/2 MOUSE', 'INIT BEGIN.');
    devid.bus:= biUnknown;
    devid.id0:= 0;
    devid.id1:= 0;
    devid.id2:= 0;
    devid.id3:= 0;
    devid.id4:= 0;
    devid.ex:= nil;
    Current.x:= 0;
    Current.y:= 0;
    Last.x:= 0;
    Last.y:= 0;
    drivermanagement.register_driver_ex('PS/2 Mouse', @devid, @load, true);
    console.outputln('PS/2 MOUSE', 'INIT END.');
    pop_trace;
end;

end.