{ ************************************************
  * Asuro
  * Unit: Drivers/ISR13
  * Description: General Protection Fault
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr13;

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
    i    : uint32;
    Regs : PRegisters;

begin
    CLI;
    asm
        MOV EAX, EBP
        MOV Regs, EAX
    end;
    for i:=0 to MAX_HOOKS-1 do begin
        if uint32(Hooks[i]) <> 0 then Hooks[i](void(13));
    end;
    console.writestringln('General Protection Fault.');
    console.writestring('Flags: ');
    console.writehexln(Regs^.EFlags);
    console.writestring('EIP: ');
    console.writehexln(Regs^.EIP);
    console.writestring('CS: ');
    console.writehexln(Regs^.CS);
    console.writestring('Error Code: ');
    console.writehexln(Regs^.ErrorCode);
    util.halt_and_catch_fire;
end;

procedure register();
begin
    memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
    IDT.set_gate(13, uint32(@Main), $08, ISR_RING_0);
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