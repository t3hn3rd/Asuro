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
	Prog->NetLog - Network Driver Logs.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit netlog;

interface

uses
    console, terminal, keyboard, util, strings, tracer;

procedure init();
function  getNetlogHWND : HWND;

implementation

var
    Handle  : HWND = 0;

function  getNetlogHWND : HWND;
begin
    getNetlogHWND:= Handle;
end;

procedure OnClose();
begin
    Handle:= 0;
end;

procedure run(Params : PParamList);
begin
    if Handle = 0 then begin
        Handle:= newWindow(20, 40, 63, 14, 'NETLOG');
        clearWND(Handle);
        registerEventHandler(Handle, EVENT_CLOSE, void(@OnClose));
    end;
end;

procedure init();
begin
    tracer.push_trace('netlog.init');
    terminal.registerCommand('NETLOG', @Run, 'View network event log.');
end;

end.