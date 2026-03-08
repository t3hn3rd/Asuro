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
	Driver->Exp->TestDriver - Dummy Driver For Testing.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.exp.testdriver;

interface

uses
    debug.tracer, io.syslog, driver.mgr;

procedure init;

implementation

function load(ptr : void) : boolean;
begin
    push_trace('driver.exp.testdriver.load');
    io.syslog.logln('DUMMY DRIVER', 'LOADED.');
    pop_trace;
end;

procedure init;
var
    devID : TDeviceIdentifier;

begin
    push_trace('driver.exp.testdriver.init');
    devID.bus:= biPCI; { driver.bus.pci BUS }
    devID.id0:= idANY; { ANY DEVICE ID }
    devID.id1:= $00000006; { CLASS }
    devID.id2:= $00000000; { SUBCLASS }
    devID.id3:= $00000000; { PROGIF }
    devID.id4:= idANY;
    devID.ex:= nil; { NO EXTENDED INFO }
    driver.mgr.register_driver('DUMMY DRIVER', @devID, @load);
    pop_trace;
end;

end.