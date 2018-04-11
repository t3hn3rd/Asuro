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
    drivermanagement;

type
    POHCI_MMR = ^TOHCI_MMR;
    TOHCI_MMR = packed record
        HcRevision : uint32;
        HcControl  : uint32;
        HcCommandStatus : uint32;
        HcIntStatus  : uint32;
        HcIntEnable  : uint32;
        HcIntDisable : uint32;
        HcHCCA : uint32;
        HcPeriodCurrentED : uint32;
        HcControlHeadED : uint32;
        HcControlCurrentED : uint32;
        HcBulkHeadED : uint32;
        HcBulkCurrentED : uint32;
        HcDoneHead : uint32;
        HcFmRemaining : uint32;
        HcFmNumber : uint32;
        HcPeriodicStart : uint32;
        HcLSThreshold : uint32;
        HcRhDescriptorA : uint32;
        HcRhDescriptorB : uint32;
        HcRhStatus : uint32;
    end;

procedure init;

implementation

function loadOHCI(ptr : void) : boolean;
var
    devices : TDeviceArray;
    count   : uint32;
    i       : uint32;
    block   : uint32;
    MMR     : POHCI_MMR;

begin
    push_trace('USB.loadOHCI');
    devices:= PCI.getDeviceInfo($0C, $03, $10, count);
    console.output('USB-OHCI Driver', 'Found ');
    console.writeint(count);
    console.writestringln(' USB Controller(s).');
    if count > 0 then begin
        for i:=0 to count-1 do begin
            console.output('USB-OHCI Driver', 'Controller[');
            console.writeint(i);
            console.writestring(']: ');
            console.writehex(devices[i].device_id);
            console.writestring(' ');
            console.writehex(devices[i].vendor_id);
            console.writestring(' ');
            console.writehexln(devices[i].prog_if);
            block:= devices[i].address0 SHR 22;
            force_alloc_block(block, 0);
            map_page(block, block);
            MMR:= POHCI_MMR(devices[i].address0);
        end;
    end;
    loadOHCI:= true;
    pop_trace;
end;

function loadUHCI(ptr : void) : boolean;
var
    devices : TDeviceArray;
    count   : uint32;
    i       : uint32;

begin
    push_trace('USB.loadUHCI');
    devices:= PCI.getDeviceInfo($0C, $03, $00, count);
    console.output('USB-UHCI Driver','Found ');
    console.writeint(count);
    console.writestringln(' USB Controller(s).');
    if count > 0 then begin
        for i:=0 to count-1 do begin
            console.output('USB-UHCI Driver','Controller[');
            console.writeint(i);
            console.writestring(']: ');
            console.writehex(devices[i].device_id);
            console.writestring(' ');
            console.writehex(devices[i].vendor_id);
            console.writestring(' ');
            console.writehexln(devices[i].prog_if);
        end;
    end;
    loadUHCI:= true;
    pop_trace;
end;

procedure init;
var
    UHCI_ID, OHCI_ID : TDeviceIdentifier;

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

    drivermanagement.register_driver('USB-UHCI Driver', @UHCI_ID, @loadUHCI);
    drivermanagement.register_driver('USB-OHCI Driver', @OHCI_ID, @loadOHCI);

    console.outputln('USB Driver', 'INIT END.');
    pop_trace;
end;

end.