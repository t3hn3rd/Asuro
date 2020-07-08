{ 
	Prog->udpcat - Listen for UDP packets on a port.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit udpcat;

interface

uses
    console, terminal, keyboard, util, strings, tracer, udp, nettypes, lmemorymanager;

procedure init();

implementation

var
    Handle  : HWND = 0;
    context : PUDPBindContext;

procedure OnClose();
begin
    Handle:= 0;
    if context <> nil then begin
        udp.unbind(context);
        kfree(void(context));
        context:= nil;
    end;
end;

procedure OnReceive(p_data : void; p_len : uint16; p_context : PUDPPacketContext);
var
    c : pchar;
    i : uint16;

begin
    c:= pchar(p_data);
    for i:=0 to p_len-1 do begin
        writecharWND(c[i], Handle);
    end;
    writestringlnWND(' ', Handle);
end;

procedure run(Params : PParamList);
var
    sPort   : PChar;
    Port    : uint16;
    success : boolean;

begin
    if ParamCount(Params) > 0 then begin
        if Handle = 0 then begin
            Handle:= newWindow(20, 40, 63, 14, 'UDPCAT');
            clearWND(Handle);
            registerEventHandler(Handle, EVENT_CLOSE, void(@OnClose));

            sPort:= getParam(0, Params);
            Port:= stringToInt(sPort);
            context:= PUDPBindContext(kalloc(sizeof(TUDPBindContext)));
            context^.port:= Port;
            context^.Callback:= @OnReceive;
            context^.UID:= Handle;
            
            success:= false;

            case udp.bind(context) of
                tueOK:begin
                    success:= true;
                end;
                tuePortInUse:begin
                    writestringlnWND('The requested port is already in use.', getTerminalHWND);
                end;
                tuePortRestricted:begin
                    writestringlnWND('Can''t bind to a restricted port.', getTerminalHWND);
                end;
                tueGenericError:begin
                    writestringlnWND('An unknown error occured.', getTerminalHWND);
                end;
            end;
            if not success then begin
                closeWindow(Handle);
            end;          
        end;
    end else begin
        writestringlnWND('Invalid number of params, please use:', getTerminalHWND);
        writestringlnWND('udpcat <port>', getTerminalHWND);
    end;
end;

procedure init();
begin
    tracer.push_trace('udpcat.init');
    terminal.registerCommand('UDPCAT', @Run, 'Listen for UDP packets on a specific port.');
end;

end.