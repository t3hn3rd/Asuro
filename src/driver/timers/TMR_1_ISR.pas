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
	Driver->Timer->TMR_1_ISR - 1024/s Timer Driver.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit TMR_1_ISR;

interface

uses
    util,
    isr_types,
    IDT;

procedure register();
procedure hook(hook_method : uint32);
procedure unhook(hook_method : uint32);

implementation

var
    Hooks : Array[1..MAX_HOOKS] of pp_hook_method;
    Registered : boolean = false;

procedure Main; //IRQ0, called 1024 times a second.
var
    i : integer;

begin
    for i:=0 to MAX_HOOKS-1 do begin
        if uint32(Hooks[i]) <> 0 then Hooks[i](void(18));
    end;
end;

procedure register();
begin
    if not registered then begin
        memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
        isrmanager.registerISR(40, @Main);
        //IDT.set_gate(40, uint32(@Main), $08, ISR_RING_0);
        Registered:= true;
    end;
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
 