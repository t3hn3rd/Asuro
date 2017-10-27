unit USB;

interface

uses
    Console,
    PCI,
    drivertypes,
    pmemorymanager,
    vmemorymanager;

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

procedure init;
var
    devices : TDeviceArray;
    count   : uint32;
    i       : uint32;
    block   : uint32;
    MMR     : POHCI_MMR;

begin
    console.writestringln('USB: INIT BEGIN.');
    
    devices:= PCI.getDeviceInfo($0C, $03, $00, count);
    console.writestring('USB-UHCI: Found ');
    console.writeint(count);
    console.writestringln(' USB Controller(s).');
    if count > 0 then begin
        for i:=0 to count-1 do begin
            console.writestring('USB: Controller[');
            console.writeint(i);
            console.writestring(']: ');
            console.writehex(devices[i].device_id);
            console.writestring(' ');
            console.writehex(devices[i].vendor_id);
            console.writestring(' ');
            console.writehexln(devices[i].prog_if);
        end;
    end;

    devices:= PCI.getDeviceInfo($0C, $03, $10, count);
    console.writestring('USB-OHCI: Found ');
    console.writeint(count);
    console.writestringln(' USB Controller(s).');
    if count > 0 then begin
        for i:=0 to count-1 do begin
            console.writestring('USB: Controller[');
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
            console.writestring('HcRevision? ');
            console.writeintln(MMR^.HcRevision);
        end;
    end;

    console.writestringln('USB: INIT END.');
end;

end.