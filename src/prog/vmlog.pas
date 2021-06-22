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
	Prog->VMLog - Virtual Machine Event Log.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit vmlog;

interface

uses
    console, terminal, keyboard, util, strings, tracer;

procedure init();
function  getVMLogHWND : HWND;

implementation

var
    Handle  : HWND = 0;

function getVMLogHWND : HWND;
begin
    getVMLogHWND:= Handle;
end;

procedure OnClose();
begin
    Handle:= 0;
end;

procedure run(Params : PParamList);
begin
    if Handle = 0 then begin
        Handle:= newWindow(20, 40, 63, 14, 'VMLOG');
        clearWND(Handle);
        registerEventHandler(Handle, EVENT_CLOSE, void(@OnClose));
    end;
end;

procedure init();
begin
    tracer.push_trace('vmlog.init');
    terminal.registerCommand('VMLOG', @Run, 'View virtual-machine event log.');
end;

end.