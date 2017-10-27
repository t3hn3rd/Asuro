unit USB;

interface

uses
    Console,
    PCI,
    drivertypes,
    pmemorymanager,
    vmemorymanager;

procedure init;

implementation

procedure init;
var
    devices : TDeviceArray;
    count   : uint32;
    i       : uint32;
    block   : uint32;

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
        end;
    end;

    console.writestringln('USB: INIT END.');
end;

end.