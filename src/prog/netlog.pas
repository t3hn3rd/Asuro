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
    end;
end;

procedure init();
begin
    tracer.push_trace('netlog.init');
    terminal.registerCommand('NETLOG', @Run, 'View network event log.');
end;

end.