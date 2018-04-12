{ ************************************************
  * Asuro
  * Unit: Drivers/ISR45
  * Description: Mouse ISR (IRQ12)
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit PS2_MOUSE_ISR;

interface

uses
    tracer,
    util,
    console,
    isr_types,
    isrmanager,
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
    Registered : Boolean = false;

procedure mouse_wait(w_type : uint8);
var
    timeout : uint32;

begin
    push_trace('isr44.mouse_wait');
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
    pop_trace;
end;

procedure mouse_write(value : uint8);
begin
    push_trace('isr44.mouse_write');
    mouse_wait(1);
    outb($64, $D4);
    mouse_wait(1);
    outb($60, value);
    pop_trace;
end;

function mouse_read : uint8;
begin
    push_trace('isr44.mouse_read');
    mouse_wait(0);
    mouse_read:= inb($60);
    pop_trace;
end;

procedure Main();
var
    i : integer;
    b : byte;
    
begin
    {push_trace('isr44.main');
    b:= mouse_read;
    push_trace('isr44.main1');
    if Cycle = 0 then begin
        push_trace('isr44.main2');
        if (b AND $08) = $08 then begin
            push_trace('isr44.main3');
            Mouse_Byte[Cycle]:= b;
            push_trace('isr44.main4');
            inc(Cycle);
        end;
    end else begin
        push_trace('isr44.main5');
        Mouse_Byte[Cycle]:= b;
        push_trace('isr44.main6');
        inc(Cycle);
    end;
    push_trace('isr44.main7');
    if Cycle > 2 then begin
        Cycle:= 0;
        push_trace('isr44.main8');
        // console.writestring('Packet[0]: ');
        // console.writeintln(Mouse_Byte[0]);
        // console.writestring('Packet[1]: ');
        // console.writeintln(Mouse_Byte[1]);
        // console.writestring('Packet[2]: ');
        // console.writeintln(Mouse_Byte[2]);
        push_trace('isr44.main9');
        Packet:= (Mouse_Byte[0] SHL 24) OR (Mouse_Byte[1] SHL 16) OR (Mouse_Byte[2] SHL 8) OR ($FF);
        push_trace('isr44.main10');
        for i:=0 to MAX_HOOKS-1 do begin
            if uint32(Hooks[i]) <> 0 then Hooks[i](void(Packet));
        end;
        push_trace('isr44.main11');
    end;
    push_trace('isr44.main12');
    outb($20, $20);
    outb($A0, $20);
    pop_trace;}
end;

procedure register();
var
    status : uint8;
    bm     : PBitMask;
    ak     : uint8;

begin
    push_trace('isr44.register');
    if not Registered then begin
        Registered:= true;
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
        isrmanager.registerISR(44, @Main);
        //IDT.set_gate(44, uint32(@Main), $08, ISR_RING_0);
    end;
    pop_trace;
end;

procedure hook(hook_method : uint32);
var
    i : uint32;
    cont : boolean; 

begin
    push_trace('isr44.hook');    
    cont:= true;
    for i:=0 to MAX_HOOKS-1 do begin
        if uint32(Hooks[i]) = hook_method then begin
            cont:= false;
            break;
        end;
    end;
    if cont then begin
        for i:=0 to MAX_HOOKS-1 do begin
            if uint32(Hooks[i]) = 0 then begin
                Hooks[i]:= pp_hook_method(hook_method);
                break;
            end;
        end;
    end;
    pop_trace;
end;

procedure unhook(hook_method : uint32);
var
    i : uint32;
begin
    push_trace('isr44.unhook');
    for i:=0 to MAX_HOOKS-1 do begin
        If uint32(Hooks[i]) = hook_method then Hooks[i]:= nil;
        break;
    end;
    pop_trace;
end;

end.