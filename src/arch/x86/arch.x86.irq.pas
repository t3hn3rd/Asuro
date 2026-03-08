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
	Interrupt Request Line - Initialization & Remapping.
	
	@author(Aaron Hance <ah@aaronhance.me>)
}
unit arch.x86.irq;

interface

uses core.util, arch.x86.util, io.syslog;

procedure init();

implementation

procedure init();
begin
    io.syslog.logln('IRQ','INIT START.');
    outb($20, $11);
    io_wait;
    outb($A0, $11);
    io_wait;
    outb($21, $20);
    io_wait;
    outb($A1, $28);
    io_wait;
    outb($21, $04);
    io_wait;
    outb($A1, $02);
    io_wait;
    outb($21, $01);
    io_wait;
    outb($A1, $01);
    io_wait;
    outb($21, $00);
    io_wait;
    outb($A1, $00);
    io_wait;
    io.syslog.logln('IRQ','INIT END.');
end;

end.