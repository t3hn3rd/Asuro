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
	Fault->PF - Page Fault.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit PF;

interface

uses
    util,
    console,
    isr_types,
    isrmanager,
    IDT;

procedure register();

implementation

procedure Main();
var
    i : integer;
    faulting_addr : uint32;
    
begin
    CLI;
    { Read CR2 — the linear address that caused the page fault }
    asm
        MOV EAX, CR2
        MOV faulting_addr, EAX
    end;
    correctInterruptRegisters(true);
    console.writestring('[PF] Faulting address: ');
    console.writehexln(faulting_addr);
    if IntSpec <> nil then begin
        console.writestring('[PF] Faulting EIP: ');
        console.writehexln(IntSpec^.EIP);
    end;
    if IntErr <> nil then begin
        console.writestring('[PF] Error code: ');
        console.writehexln(IntErr^.Error);
    end;
    BSOD('PF', 'Page Fault.');
    console.writestringln('Page Fault.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    isrmanager.registerISR(14, @Main);
    //memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
    //IDT.set_gate(14, uint32(@Main), $08, ISR_RING_0);
end;

end.