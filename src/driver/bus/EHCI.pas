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
	Driver->Bus->EHCI - Enhanced Host Controller Interface Driver.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit EHCI;

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
    tracer.push_trace('EHCI.load');
    devices:= PCI.getDeviceInfo($0C, $03, $20, count);
    console.output('USB-EHCI Driver', 'Found ');
    console.writeint(count);
    console.writestringln(' USB Controller(s).');
    if count > 0 then begin
        for i:=0 to count-1 do begin
            console.output('USB-EHCI Driver', 'Controller[');
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