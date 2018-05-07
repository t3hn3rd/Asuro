unit OHCI;

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

function load : boolean;

implementation

function load : boolean;
var
    devices : TDeviceArray;
    count   : uint32;
    i       : uint32;
    block   : uint32;
    MMR     : POHCI_MMR;

begin
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
    load:= true;
end;

end.