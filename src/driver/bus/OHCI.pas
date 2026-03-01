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
	Driver->Bus->OHCI - Open Host Controller Interface Driver.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit OHCI;

interface

uses
    tracer,
    syslog,
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
    tracer.push_trace('OHCI.load');
    devices:= PCI.getDeviceInfo($0C, $03, $10, count);
    syslog.log('USB-OHCI Driver', 'Found ');
    syslog.writeint(count);
    syslog.writestringln(' USB Controller(s).');
    if count > 0 then begin
        for i:=0 to count-1 do begin
            syslog.log('USB-OHCI Driver', 'Controller[');
            syslog.writeint(i);
            syslog.writestring(']: ');
            syslog.writehex(devices[i].device_id);
            syslog.writestring(' ');
            syslog.writehex(devices[i].vendor_id);
            syslog.writestring(' ');
            syslog.writehexln(devices[i].prog_if);
            block:= devices[i].address0 SHR 22;
            force_alloc_block(block, 0);
            map_page(block, block);
            MMR:= POHCI_MMR(devices[i].address0);
        end;
    end;
    load:= true;
end;

end.