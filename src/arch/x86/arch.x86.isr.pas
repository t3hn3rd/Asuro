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
	ISR Driver - Initialization (stub).
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit arch.x86.isr;

interface

uses
		boot.mgr;

procedure init();

implementation

uses
		arch.x86.util, arch.x86.isr.tmr0, arch.x86.bda;

procedure init();
begin
    STI;
    arch.x86.isr.tmr0.hook(uint32(@arch.x86.bda.tick_update));
end;

Initialization
		boot.mgr.registerBoot('asuro.x86.isr', @init, 'Enable Interrupts and Timer', 'driver.storage.*.mgr');

end.