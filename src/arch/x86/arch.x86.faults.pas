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
unit arch.x86.faults;

interface

uses
    arch.x86.fault.ace, arch.x86.fault.bpe, arch.x86.fault.btsse, arch.x86.fault.cfe, arch.x86.fault.csoe, arch.x86.fault.dbge, arch.x86.fault.dbz, arch.x86.fault.dfe, arch.x86.fault.gpf, arch.x86.fault.idoe, arch.x86.fault.iope, arch.x86.fault.mce,
    arch.x86.fault.nce, arch.x86.fault.nmie, arch.x86.fault.oobe, arch.x86.fault.pf, arch.x86.fault.sfe, arch.x86.fault.snpe, arch.x86.fault.uie;

procedure init;

implementation

procedure init;
begin
    arch.x86.fault.ace.register();
    arch.x86.fault.bpe.register();
    arch.x86.fault.btsse.register();
    arch.x86.fault.cfe.register();
    arch.x86.fault.csoe.register();
    arch.x86.fault.dbge.register();
    arch.x86.fault.dbz.register();
    arch.x86.fault.dfe.register();
    arch.x86.fault.gpf.register();
    arch.x86.fault.idoe.register();
    arch.x86.fault.iope.register();
    arch.x86.fault.mce.register();
    arch.x86.fault.nce.register();
    arch.x86.fault.nmie.register();
    arch.x86.fault.oobe.register();
    arch.x86.fault.pf.register();
    arch.x86.fault.sfe.register();
    arch.x86.fault.snpe.register();
    arch.x86.fault.uie.register();
end;

end.