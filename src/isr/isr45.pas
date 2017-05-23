{ ************************************************
  * Asuro
  * Unit: Drivers/ISR45
  * Description: Mouse ISR (IRQ12)
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr45;

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
    
begin
    CLI;
    console.writestringln('Mouse INT');
    for i:=0 to MAX_HOOKS-1 do begin
        if uint32(Hooks[i]) <> 0 then Hooks[i](void($00000000));
    end;
end;

procedure register();
var
    status : uint8;
    bm     : PBitMask;

begin
    memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
    IDT.set_gate(45, uint32(@Main), $08, ISR_RING_0);
    outb($64, $20);
    status:= inb($64);
    bm:= PBitMask(@status);
    bm^.b1:= true;
    bm^.b5:= false;
    outb($64, $60);
    outb($60, status);
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