unit USB;

interface

uses
    tracer,
    Console,
    PCI,
    drivertypes,
    pmemorymanager,
    vmemorymanager,
    util,
    drivermanagement,
    OHCI, UHCI, EHCI;

procedure init;

implementation

function loadEHCI(ptr : void) : boolean;
begin
    push_trace('USB.loadEHCI');
    loadEHCI:= EHCI.load;
end;

function loadOHCI(ptr : void) : boolean;
begin
    push_trace('USB.loadOHCI');
    loadOHCI:= OHCI.load;
end;

function loadUHCI(ptr : void) : boolean;
begin
    push_trace('USB.loadUHCI');
    loadUHCI:= UHCI.load;
end;

procedure init;
var
    UHCI_ID, OHCI_ID, EHCI_ID: TDeviceIdentifier;

begin
    push_trace('USB.init');
    console.outputln('USB Driver', 'INIT BEGIN.');
    
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

    drivermanagement.register_driver('USB-UHCI Driver', @UHCI_ID, @loadUHCI);
    drivermanagement.register_driver('USB-OHCI Driver', @OHCI_ID, @loadOHCI);
    drivermanagement.register_driver('USB-EHCI Driver', @EHCI_ID, @loadEHCI);

    console.outputln('USB Driver', 'INIT END.');
    pop_trace;
end;

end.