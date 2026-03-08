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
	Driver->Timer->arch.x86.isr.tmr0 - 8khz Timer Driver.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit arch.x86.isr.tmr0;

interface

uses
    core.util, arch.x86.util,
    arch.x86.isr.types,
    arch.x86.isr.mgr,
    arch.x86.idt;

procedure register();
procedure hook(hook_method : uint32);
procedure unhook(hook_method : uint32);

implementation

var
    Hooks : Array[0..MAX_HOOKS-1] of pp_hook_method;
    Registered : boolean = false;

procedure Main; //IRQ0, ~8001hz
var
    i : integer;

begin
    CLI;
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
            mov ax, 149
            out $40, al
            mov al, ah
            out $40, al
        end;
        memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
        arch.x86.isr.mgr.registerISR(32, @Main);
        Registered:= true;
    end;
    //arch.x86.idt.set_gate(32, uint32(@Main), $08, ISR_RING_0);
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
        If uint32(Hooks[i]) = hook_method then begin
            Hooks[i]:= nil;
            exit;
        end;
    end;
end;

end.
