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
	Driver->Bus->USB - Universal Serial Bus Driver/Interface.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit USB;

interface

uses
    tracer,
    syslog,
    PCI,
    drivertypes,
    pmemorymanager,
    vmemorymanager,
    util,
    drivermanagement,
    usbtypes,
    usbcore,
    usbhub,
    usb_keyboard,
    usb_mouse,
    OHCI, UHCI, EHCI, XHCI;

procedure init;

implementation

function loadXHCI(ptr : void) : boolean;
begin
    push_trace('USB.loadXHCI');
    loadXHCI:= XHCI.load;
    pop_trace;
end;

function loadEHCI(ptr : void) : boolean;
begin
    push_trace('USB.loadEHCI');
    loadEHCI:= EHCI.load;
    pop_trace;
end;

function loadOHCI(ptr : void) : boolean;
begin
    push_trace('USB.loadOHCI');
    loadOHCI:= OHCI.load;
    pop_trace;
end;

function loadUHCI(ptr : void) : boolean;
begin
    push_trace('USB.loadUHCI');
    loadUHCI:= UHCI.load;
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
    syslog.logln('USB Driver', 'INIT BEGIN.');

    { Initialize USB core (HC list, etc.) }
    usbcore.init;

    { Initialize hub driver (registers class driver for $09) }
    usbhub.init;

    { Initialize HID class drivers }
    usb_keyboard.init;
    usb_mouse.init;
    
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

    drivermanagement.register_driver('USB-UHCI Driver', @UHCI_ID, @loadUHCI);
    drivermanagement.register_driver('USB-OHCI Driver', @OHCI_ID, @loadOHCI);
    drivermanagement.register_driver('USB-EHCI Driver', @EHCI_ID, @loadEHCI);
    drivermanagement.register_driver('USB-XHCI Driver', @XHCI_ID, @loadXHCI);

    syslog.logln('USB Driver', 'INIT END.');
    pop_trace;
end;

end.