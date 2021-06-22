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
	Faults - Fault Registration & Detouring.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit faults;

interface

uses
    ACE, BPE, BTSSE, CFE, CSOE, DBGE, DBZ, DFE, GPF, IDOE, IOPE, MCE,
    NCE, NMIE, OOBE, PF, SFE, SNPE, UIE;

procedure init;

implementation

procedure init;
begin
    ACE.register();
    BPE.register();
    BTSSE.register();
    CFE.register();
    CSOE.register();
    DBGE.register();
    DBZ.register();
    DFE.register();
    GPF.register();
    IDOE.register();
    IOPE.register();
    MCE.register();
    NCE.register();
    NMIE.register();
    OOBE.register();
    PF.register();
    SFE.register();
    SNPE.register();
    UIE.register();
end;

end.