{ ************************************************
  * Asuro
  * Unit: Drivers/ISR45
  * Description: Mouse ISR (IRQ12)
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr44;

interface

uses
    util,
    console,
    isr_types,
    IDT;

procedure register();
procedure hook(hook_method : uint32);
procedure unhook(hook_method : uint32);

implementation

var
    Hooks : Array[1..MAX_HOOKS] of pp_hook_method;
    Cycle : uint32 = 0;
    Mouse_Byte : Array[0..2] of uint8;
    Packet : uint32;

procedure mouse_wait(w_type : uint8);
var
    timeout : uint32;

begin
    timeout:= 100000;
    if (w_type = 0) then begin
        while (timeout > 0) do begin
            if ((inb($64) AND $01) = $01) then exit;
            timeout:= timeout-1;
        end;
    end else begin
        while (timeout > 0) do begin
            if ((inb($64) AND 2) = 0) then exit;
            timeout := timeout - 1;
        end;
    end;
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

procedure Main(); interrupt;
var
    i : integer;
    b : byte;
    
begin
    b:= mouse_read;
    if Cycle = 0 then begin
        if (b AND $08) = $08 then begin
            Mouse_Byte[Cycle]:= b;
            inc(Cycle);
        end;
    end else begin
        Mouse_Byte[Cycle]:= b;
        inc(Cycle);
    end;
    if Cycle > 2 then begin
        Cycle:= 0;
        // console.writestring('Packet[0]: ');
        // console.writeintln(Mouse_Byte[0]);
        // console.writestring('Packet[1]: ');
        // console.writeintln(Mouse_Byte[1]);
        // console.writestring('Packet[2]: ');
        // console.writeintln(Mouse_Byte[2]);
        Packet:= (Mouse_Byte[0] SHL 24) OR (Mouse_Byte[1] SHL 16) OR (Mouse_Byte[2] SHL 8) OR ($FF);
        for i:=0 to MAX_HOOKS-1 do begin
            if uint32(Hooks[i]) <> 0 then Hooks[i](void(Packet));
        end;
    end;
    outb($20, $20);
    outb($A0, $20);
end;

procedure register();
var
    status : uint8;
    bm     : PBitMask;
    ak     : uint8;

begin
    memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
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
    IDT.set_gate(44, uint32(@Main), $08, ISR_RING_0);
end;

procedure hook(hook_method : uint32);
var
    i : uint32;

begin
    for i:=0 to MAX_HOOKS-1 do begin
        if uint32(Hooks[i]) = hook_method then exit;
    end;
    for i:=0 to MAX_HOOKS-1 do begin
        if uint32(Hooks[i]) = 0 then begin
            Hooks[i]:= pp_hook_method(hook_method);
            exit;
        end;
    end;
end;

procedure unhook(hook_method : uint32);
var
    i : uint32;
begin
    for i:=0 to MAX_HOOKS-1 do begin
        If uint32(Hooks[i]) = hook_method then Hooks[i]:= nil;
        exit;
    end;
end;

end.