unit net;

interface

uses
    tracer,
    console,
    nettypes, netutils,
    netlog;

procedure init;
procedure registerNetworkCard(SendCallback : TNetSendCallback; _MAC : puint8);
procedure registerNextLayer(RecvCallback : TRecvCallback);
procedure send(p_data : void; p_len : uint16);
procedure recv(p_data : void; p_len : uint16);
function  getMAC : puint8;

implementation

uses
    ipv4, arp, eth2;

var
    CBSend : TNetSendCallback = nil;
    CBNext : TRecvCallback    = nil;
    MAC    : puint8           = nil;

procedure registerNetworkCard(SendCallback : TNetSendCallback; _MAC : puint8);
begin
    push_trace('net.registerNetworkCard');
    if CBSend = nil then begin
        CBSend:= SendCallback;
        MAC:= _MAC;
    end;    
    pop_trace;
end;

procedure registerNextLayer(RecvCallback : TRecvCallback);
begin
    push_trace('net.registerNextLayer');
    if CBNext = nil then begin
        CBNext:= RecvCallback;
    end;
    pop_trace;
end;

procedure send(p_data : void; p_len : uint16);
begin
    push_trace('net.send');
    if getNetlogHWND <> 0 then writestringlnWND('net.send', getNetlogHWND);
    if CBSend <> nil then CBSend(p_data, p_len);
    pop_trace;
end;

procedure recv(p_data : void; p_len : uint16);
var
    context : PPacketContext;

begin
    push_trace('net.recv');
    if getNetlogHWND <> 0 then writestringlnWND('net.recv', getNetlogHWND);
    context:= newPacketContext;
    if CBNext <> nil then CBNext(p_data, p_len, context);
    freePacketContext(context);
    pop_trace;
end;

function getMAC : puint8;
begin
    push_trace('net.getMAC');
    getMAC:= MAC;
    pop_trace;
end;

procedure init;
begin
    push_trace('net.init');
    eth2.register;
    arp.register;
    ipv4.register;
    pop_trace;
end;

end.