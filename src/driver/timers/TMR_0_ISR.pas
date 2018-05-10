{ ************************************************
  * Asuro
  * Unit: Drivers/isr32
  * Description: 1024hz Timer interrupt
  ************************************************
  * Author: Aaron Hance
  * Contributors: K Morris
  ************************************************ }

unit TMR_0_ISR;

interface

uses
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
    Registered : boolean = false;
    v : uint32 = 0;

procedure Main; //IRQ0, 1024.19hz aprox
var
    i : integer;

begin
    CLI;
    inc(v);
    if v = 1024 then begin
        console.redrawWindows;
        v:= 0;
    end;
    for i:=0 to MAX_HOOKS-1 do begin
        if uint32(Hooks[i]) <> 0 then begin 
            Hooks[i](nil);
        end;
    end;
end;

procedure register();
begin
    if not registered then begin
        asm
            mov al, $36
            out $46, al
            mov ax, 1165
            out $40, al
            mov al, ah
            out $40, al
        end;
        memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
        isrmanager.registerISR(32, @Main);
        Registered:= true;
    end;
    //IDT.set_gate(32, uint32(@Main), $08, ISR_RING_0);
end;

procedure hook(hook_method : uint32);
var
    i : uint32;

begin
    register();
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
