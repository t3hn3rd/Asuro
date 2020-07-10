{ 
	Driver->Net->L1->Net - Network Card<->Driver Interface.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit net;

interface

uses
    tracer,
    console,
    nettypes, netutils,
    netlog,
    RTC;

procedure init;
procedure registerNetworkCard(SendCallback : TNetSendCallback; _MAC : puint8);
procedure registerNextLayer(RecvCallback : TRecvCallback);
procedure send(p_data : void; p_len : uint16);
procedure recv(p_data : void; p_len : uint16);
function  getMAC : puint8;
procedure writeToLog(str : pchar);
procedure writeToLogLn(str : pchar);

implementation

uses
    terminal,   
    e1000,              //dev
    eth2,               //L2
    arp, ipv4,          //L3
    icmp, tcp, udp,     //L4
    dhcp;               //L5

var
    CBSend : TNetSendCallback = nil;
    CBNext : TRecvCallback    = nil;
    MAC     : puint8          = @NULL_MAC[0];

procedure writeToLog(str : pchar);
var
    DateTime : TDateTime;

begin
    if getNetlogHWND <> 0 then begin
        DateTime:= getDateTime;
        writeStringWND('[', getNetlogHWND);

        if DateTime.Hours < 10 then writeIntWND(0, getNetlogHWND);
        writeIntWND(DateTime.Hours, getNetlogHWND);
        writeStringWND(':', getNetlogHWND);
        
        if DateTime.Minutes < 10 then writeIntWND(0, getNetlogHWND);
        writeIntWND(DateTime.Minutes, getNetlogHWND);
        writeStringWND(':', getNetlogHWND);

        if DateTime.Seconds < 10 then writeIntWND(0, getNetlogHWND);
        writeIntWND(DateTime.Seconds, getNetlogHWND);
        writeStringWND('] ', getNetlogHWND); 

        writeStringWND(str, getNetlogHWND);
    end;
end;

procedure writeToLogLn(str : pchar);
begin
    writeToLog(str);
    if getNetlogHWND <> 0 then begin
        writestringlnWND(' ', getNetlogHWND);
    end;
end;

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
    writeToLogLn('L1: net.send');
    if CBSend <> nil then CBSend(p_data, p_len);
    pop_trace;
end;

procedure recv(p_data : void; p_len : uint16);
var
    context : PPacketContext;

begin
    push_trace('net.recv');
    writeToLogLn('L1: net.recv');
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
    //l2
    eth2.register;
    //l3
    arp.register;
    ipv4.register;
    //l4
    icmp.register;
    udp.register;
    //l5
    dhcp.register;
    pop_trace;
end;

end.