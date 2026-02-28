//  Copyright 2021 Kieron Morris
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

{ 
	Driver->HID->Mouse - Mouse Driver.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit mouse;

interface

uses 
    tracer,
    console,
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
procedure DrawCursor;
function getMouseX: sint32;
function getMouseY: sint32;
function getMouseLMB: boolean;
function getMouseRMB: boolean;
function getMouseScroll: sint32;  { returns accumulated scroll delta since last call }

implementation

var
    Current, Last : TMousePos;
    FirstDraw : boolean = true;
    BackPixels : Array[0..1] of Array[0..7] of uint64;
    Cycle : uint32 = 0;
    Mouse_Byte : Array[0..3] of uint8;
    Packet : uint32;
    Registered : Boolean = false;
    NeedsRedraw : Boolean = false;
    RMouseDownPos : TMousePos;
    LMouseDownPos : TMousePos;
    LMouseDown : Boolean;
    RMouseDown : Boolean;
    HasScrollWheel : Boolean = false;
    ScrollAccum : sint32 = 0;
    PacketSize : uint32 = 3;

function getMouseX: sint32;
begin
    getMouseX := Current.x;
end;

function getMouseY: sint32;
begin
    getMouseY := Current.y;
end;

function getMouseLMB: boolean;
begin
    getMouseLMB := LMouseDown;
end;

function getMouseRMB: boolean;
begin
    getMouseRMB := RMouseDown;
end;

function getMouseScroll: sint32;
begin
    getMouseScroll := ScrollAccum;
    ScrollAccum := 0;
end;

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
        for y:=0 to 7 do begin
            for x:=0 to 1 do begin
                drawPixel64(Last.x + (x * 4), Last.y + y, BackPixels[x][y]);
            end;
        end;        
    end;
    Last.x:= nx;
    Last.y:= ny;
    for y:=0 to 7 do begin
        for x:=0 to 1 do begin
            BackPixels[x][y]:= GetPixel64(nx + (x * 4), ny + y);
        end; 
    end;
    outputCharToScreenSpace(char(0), nx, ny, $FFFF);
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

{ Longer timeout for init-time use only (not safe in ISR context) }
function mouse_wait_long(w_type : uint8) : boolean;
var
    timeout : uint32;

begin
    timeout:= 100000;
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
    mouse_wait_long:= timeout > 0;
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
        if Cycle = PacketSize then begin
            //Process
            f:= Mouse_Byte[0];
            Packet.x_sign:= (f AND %00010000) = %00010000;
            Packet.y_sign:= (f AND %00100000) = %00100000;
            Packet.MMB_Down:= (f AND %00000100) = %00000100;
            Packet.RMB_Down:= (f AND %00000010) = %00000010;
            Packet.LMB_Down:= (f AND %00000001) = %00000001;
            Packet.x_overflow:= (f AND $40) = $40;
            Packet.y_overflow:= (f AND $80) = $80;
            Packet.x_movement:= Mouse_Byte[1];// - ((f SHL 4) AND $100);
            Packet.y_movement:= Mouse_Byte[2];// - ((f SHL 3) AND $100);
            If Packet.x_sign then Packet.x_movement:= sint16(Packet.x_movement OR $FF00);
            If Packet.y_sign then Packet.y_movement:= sint16(Packet.y_movement OR $FF00);
            if not(Packet.x_overflow) and not(Packet.y_overflow) then begin
                Current.x:= Current.x + Packet.x_movement;
                Current.y:= Current.y - Packet.y_movement;            
                if Current.x < 0 then Current.x:= 0;
                if Current.y < 0 then Current.y:= 0;
                if Current.x > sint32(video.frontBufferWidth - 1) then Current.x:= sint32(video.frontBufferWidth - 1);
                if Current.y > sint32(video.frontBufferHeight - 1) then Current.y:= sint32(video.frontBufferHeight - 1);
            end;
            { Process scroll wheel (4th byte, signed) }
            if HasScrollWheel then begin
                ScrollAccum := ScrollAccum + sint8(Mouse_Byte[3]);
            end;
            Cycle:= 0;
            if Packet.LMB_Down then begin
                if not LMouseDown then begin
                    LMouseDown:= true;
                    LMouseDownPos.x:= Current.x;
                    LMouseDownPos.y:= Current.y;
                    //MouseDownEvent
                    console._mouseDown();
                end;
            end;
            if not Packet.LMB_Down then begin
                if LMouseDown then begin
                    If (Current.x = LMouseDownPos.x) and (Current.y = LMouseDownPos.y) then begin
                        Console._MouseClick(true);
                    end;
                    //MouseUpEvent
                    Console._MouseUp();
                    LMouseDown:= false;
                end;
            end;
            if Packet.RMB_Down then begin
                if not RMouseDown then begin
                    RMouseDown:= true;
                    RMouseDownPos.x:= Current.x;
                    RMouseDownPos.y:= Current.y;
                end;
            end;
            
            if not Packet.RMB_Down then begin
                if RMouseDown then begin
                    if (Current.x = RMouseDownPos.x) and (Current.y = RMouseDownPos.y) then begin
                        Console._MouseClick(false);
                    end;
                end;
                RMouseDown:= false;
            end;
            
            console.setMousePosition(Current.x, Current.y);
        end;
    end;
end;

function load(ptr : void) : boolean;
var
    status : uint8;
    devid_byte : uint8;
begin
    push_trace('mouse.load');
    mouse_wait_long(1);
    outb($64, $A8);
    mouse_wait_long(1);
    outb($64, $20); 
    mouse_wait_long(0);
    status:= (inb($60) OR $02) AND (NOT $20);
    mouse_wait_long(1);
    outb($64, $60);
    mouse_wait_long(1);
    outb($60, status);
    mouse_write($F6);
    mouse_read();

    { Enable IntelliMouse scroll wheel: set sample rate 200, 100, 80 }
    mouse_write($F3); mouse_read(); mouse_write(200); mouse_read();
    mouse_write($F3); mouse_read(); mouse_write(100); mouse_read();
    mouse_write($F3); mouse_read(); mouse_write(80);  mouse_read();

    { Query device ID — ID 3 = IntelliMouse (scroll wheel) }
    mouse_write($F2);
    mouse_read(); { ACK }
    devid_byte := mouse_read(); { Device ID }
    if devid_byte = 3 then begin
        HasScrollWheel := true;
        PacketSize := 4;
        console.outputln('PS/2 MOUSE', 'Scroll wheel enabled (IntelliMouse).');
    end else begin
        HasScrollWheel := false;
        PacketSize := 3;
        console.outputln('PS/2 MOUSE', 'Standard mouse (no scroll wheel).');
    end;

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