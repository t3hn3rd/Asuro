{ 
	Driver->Bus->XHCI - eXtensible Host Controller Interface Driver.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit XHCI;

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

function load : boolean;

implementation

function load : boolean;
var
    devices : TDeviceArray;
    count   : uint32;
    i       : uint32;

begin
    tracer.push_trace('XHCI.load');
    devices:= PCI.getDeviceInfo($0C, $03, $30, count);
    console.output('USB-XHCI Driver', 'Found ');
    console.writeint(count);
    console.writestringln(' USB Controller(s).');
    if count > 0 then begin
        for i:=0 to count-1 do begin
            console.output('USB-XHCI Driver', 'Controller[');
            console.writeint(i);
            console.writestring(']: ');
            console.writehex(devices[i].device_id);
            console.writestring(' ');
            console.writehex(devices[i].vendor_id);
            console.writestring(' ');
            console.writehexln(devices[i].prog_if);
        end;
    end;
    load:= true;
end;

end.