//  Copyright 2021 Kieron Morris
//  Copyright 2026 Aaron Hance
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
	Interrupt Request Line - Initialization & Remapping.
	
	@author(Aaron Hance <ah@aaronhance.me>)
}
unit arch.x86.irq;

interface

uses
    boot.mgr, arch.common.legacyirq,
    core.util, arch.x86.util, io.syslog;

procedure init();

implementation

procedure init();
begin
    io.syslog.logln('IRQ','INIT START.');
    arch.common.legacyirq.remap(0, 0);
    io.syslog.logln('IRQ','INIT END.');
end;

initialization
    boot.mgr.registerBoot('arch.x86.irq', @init, 'Interrupt Request Line', 'arch.x86.idt');

end.