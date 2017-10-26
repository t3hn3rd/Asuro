{ ************************************************
  * Asuro
  * Unit: Drivers/isr33
  * Description: Keyboard interrupt
  ************************************************
  * Author: Aaron Hance
  * Contributors: K Morris
  ************************************************ }

unit isr33;

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

procedure Main(); interrupt;
var
    i : integer;
    b : dword;

begin
    //writechar('!'); // Bug traces all the way back to here - when the keyboard randomly doesn't work, this inturrupt isn't even called...
                      // This needs further investigation... Is there something that can go wrong when setting up the PIC?
    CLI;
    b:= inb($60); 
    //console.writehexln(b);
    for i:=0 to MAX_HOOKS-1 do begin
        if uint32(Hooks[i]) <> 0 then begin 
            Hooks[i](void(b));
        end;
    end;
    outb($20, $20);
end;

procedure register();
begin
    memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
    IDT.set_gate(33, uint32(@Main), $08, ISR_RING_0);
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