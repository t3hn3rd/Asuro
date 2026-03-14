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
	Driver->Bus->driver.bus.usb - Universal Serial Bus Driver/Interface.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.bus.usb;

interface

uses
    boot.mgr,
    debug.tracer,
    io.syslog,
    driver.bus.pci,
    driver.types,
    arch.x86.memory.physical,
    arch.x86.memory.virtual,
    core.util, arch.x86.util,
    driver.mgr,
    driver.bus.usb.types,
    driver.bus.usb.core,
    driver.bus.usb.hub,
    driver.hid.usb.keyboard,
    driver.hid.usb.mouse,
    driver.storage.ctl.usb,
    driver.bus.usb.ohci, driver.bus.usb.uhci, driver.bus.usb.ehci, driver.bus.usb.xhci;

procedure init;

implementation

function loadXHCI(ptr : void) : boolean;
begin
    push_trace('USB.loadXHCI');
    loadXHCI:= driver.bus.usb.xhci.load;
    pop_trace;
end;

function loadEHCI(ptr : void) : boolean;
begin
    push_trace('USB.loadEHCI');
    loadEHCI:= driver.bus.usb.ehci.load;
    pop_trace;
end;

function loadOHCI(ptr : void) : boolean;
begin
    push_trace('USB.loadOHCI');
    loadOHCI:= driver.bus.usb.ohci.load;
    pop_trace;
end;

function loadUHCI(ptr : void) : boolean;
begin
    push_trace('USB.loadUHCI');
    loadUHCI:= driver.bus.usb.uhci.load;
    pop_trace;
end;

procedure init;
var
    UHCI_ID, 
    OHCI_ID, 
    EHCI_ID,
    XHCI_ID: TDeviceIdentifier;

begin
    push_trace('USB.init');
    io.syslog.logln('driver.bus.usb Driver', 'INIT BEGIN.');

    { Initialize driver.bus.usb core (HC list, etc.) }
    driver.bus.usb.core.init;

    { Initialize hub driver (registers class driver for $09) }
    driver.bus.usb.hub.init;

    // { Initialize HID class drivers }
    // driver.hid.usb.keyboard.init;
    // driver.hid.usb.mouse.init;

    // { Initialize storage class driver }
    // driver.storage.ctl.usb.init;
    
    UHCI_ID.Bus:= biPCI;
    UHCI_ID.id0:= idANY;
    UHCI_ID.id1:= $0000000C;
    UHCI_ID.id2:= $00000003;
    UHCI_ID.id3:= $00000000;
    UHCI_ID.id4:= $FFFFFFFF;
    UHCI_ID.ex:= nil;

    OHCI_ID.Bus:= biPCI;
    OHCI_ID.id0:= idANY;
    OHCI_ID.id1:= $0000000C;
    OHCI_ID.id2:= $00000003;
    OHCI_ID.id3:= $00000010;
    OHCI_ID.id4:= $FFFFFFFF;
    OHCI_ID.ex:= nil;

    EHCI_ID.Bus:= biPCI;
    EHCI_ID.id0:= idANY;
    EHCI_ID.id1:= $0000000C;
    EHCI_ID.id2:= $00000003;
    EHCI_ID.id3:= $00000020;
    EHCI_ID.id4:= $FFFFFFFF;
    EHCI_ID.ex:= nil;

    XHCI_ID.Bus:= biPCI;
    XHCI_ID.id0:= idANY;
    XHCI_ID.id1:= $0000000C;
    XHCI_ID.id2:= $00000003;
    XHCI_ID.id3:= $00000030;
    XHCI_ID.id4:= $FFFFFFFF;
    XHCI_ID.ex:= nil;

    driver.mgr.register_driver('driver.bus.usb-driver.bus.usb.uhci Driver', @UHCI_ID, @loadUHCI);
    driver.mgr.register_driver('driver.bus.usb-driver.bus.usb.ohci Driver', @OHCI_ID, @loadOHCI);
    driver.mgr.register_driver('driver.bus.usb-driver.bus.usb.ehci Driver', @EHCI_ID, @loadEHCI);
    driver.mgr.register_driver('driver.bus.usb-driver.bus.usb.xhci Driver', @XHCI_ID, @loadXHCI);

    io.syslog.logln('driver.bus.usb Driver', 'INIT END.');
    pop_trace;
end;

Initialization
    boot.mgr.registerBoot('driver.bus.usb', @init, 'USB Bus Driver', BOOT_MGR_BARRIER_BUS);

end.
