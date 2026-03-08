//  Copyright 2021 Aaron Hance & Kieron Morris
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
	Driver->HID->PS2_KEYBAORD_ISR - PS2 ISR Hook & Driver.
	
	@author(Aaron Hance <ah@aaronhance.me>)
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit arch.x86.isr.ps2keyboard;

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
    Hooks : Array[1..MAX_HOOKS] of pp_hook_method;
    Registered : Boolean = false;

procedure Main();
var
    i : integer;
    b : dword;

begin
    //writechar('!'); // Bug traces all the way back to here - when the driver.hid.keyboard randomly doesn't work, this inturrupt isn't even called...
                      // This needs further investigation... Is there something that can go wrong when setting up the PIC?
    CLI;
    b:= inb($60); 
    //console.writehexln(b);
    for i:=0 to MAX_HOOKS-1 do begin
        if uint32(Hooks[i]) <> 0 then begin 
            Hooks[i](void(b));
        end;
    end;
end;

procedure register();
begin
    if not Registered then begin
        Registered:= true;
        memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
        //arch.x86.idt.set_gate(33, uint32(@Main), $08, ISR_RING_0);
        arch.x86.isr.mgr.registerISR(33, @Main);
        inb($60); 
    end;
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
