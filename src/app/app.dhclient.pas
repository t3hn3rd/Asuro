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
	Prog->DHClient - DHCP Configuration Management.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit app.dhclient;

interface

uses
    io.stdio, core.util, arch.x86.util, core.strings, debug.tracer, driver.net.dhcp;

procedure init();

implementation

procedure run(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin
    debug.tracer.push_trace('dhclient.run');
    DHCPDiscover();
end;

procedure init();
begin
    debug.tracer.push_trace('dhclient.init');
    io.stdio.registerCommand('DHClient', @Run, 'Run the DHCP configuration utility.');
end;

end.