unit net;

interface

uses
    console,
    nettypes, netutils;

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
    if CBSend = nil then begin
        CBSend:= SendCallback;
        MAC:= _MAC;
    end;    
end;

procedure registerNextLayer(RecvCallback : TRecvCallback);
begin
    if CBNext = nil then begin
        CBNext:= RecvCallback;
    end;
end;

procedure send(p_data : void; p_len : uint16);
begin
    if CBSend <> nil then CBSend(p_data, p_len);
end;

procedure recv(p_data : void; p_len : uint16);
var
    context : PPacketContext;

begin
    //console.outputln('net', 'RECV.');
    context:= newPacketContext;
    if CBNext <> nil then CBNext(p_data, p_len, context);
    freePacketContext(context);
end;

function getMAC : puint8;
begin
    getMAC:= MAC;
end;

procedure init;
begin
    eth2.register;
    arp.register;
    ipv4.register;
end;

end.