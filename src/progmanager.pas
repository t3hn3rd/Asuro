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
	ProgManager - Central initialization for terminal registered, baked-in programs.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit progmanager;

interface

uses
    tracer,
    //progs
    base64_prog, md5sum, dhclient, vbeinfo, meminfo;

{ Initialize all baked-in programs }
procedure init();

implementation

procedure init();
begin
    tracer.push_trace('progmanager.md5sum.init');
    md5sum.init();
    tracer.push_trace('progmanager.base64_prog.init');
    base64_prog.init();
    tracer.push_trace('progmanager.dhclient.init');
    dhclient.init();
    vbeinfo.init();
    meminfo.init();
end;

end.