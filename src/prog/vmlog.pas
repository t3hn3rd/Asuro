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