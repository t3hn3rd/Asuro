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
	Fault->arch.x86.fault.dfe - Double Fault Exception.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit arch.x86.fault.dfe;

interface

uses
    core.util, arch.x86.util,
    io.syslog,
    arch.x86.isr.types,
    arch.x86.isr.mgr,
    arch.x86.idt;

procedure register();

implementation

procedure Main();
var
    i : integer;
    
begin
    CLI;
    correctInterruptRegisters(true);
    BSOD('DF', 'Double Fault.');
    io.syslog.writestringln('Double Fault.');
    arch.x86.util.halt_and_catch_fire;
end;

procedure register();
begin
    arch.x86.isr.mgr.registerISR(8, @Main);
    //memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
    //arch.x86.idt.set_gate(8, uint32(@Main), $08, ISR_RING_0);
end;

end.
