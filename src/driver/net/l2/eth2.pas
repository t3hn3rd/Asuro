unit eth2;

interface

uses
    tracer,
    nettypes, netutils, 
    net,
    console;

procedure registerType(eType : uint16; RecvCB : TRecvCallback);
procedure register;

implementation

var
    Registered : Boolean = false;
    EthTypes   : Array[0..65535] of TRecvCallback;
    MAC        : puint8;

procedure registerType(eType : uint16; RecvCB : TRecvCallback);
begin
    push_trace('eth2.registerType');
    register;
    if EthTypes[eType] = nil then EthTypes[eType]:= RecvCB;
    pop_trace;
end;

procedure recv(p_data : void; p_len : uint16; p_context : PPacketContext);
var
    Header     : PEthernetHeader;
    proto_type : uint16;
    buf        : puint8;

begin
    push_trace('eth2.recv');
    //console.outputln('net.eth2', 'RECV.');
    buf:= puint8(p_data);
    
    Header:= PEthernetHeader(buf);
    
    //console.output('net.eth2', 'DEST: ');
    //writeMACAddress(@Header^.dst[0]);
    //console.output('net.eth2', 'SRC: ');
    //writeMACAddress(@Header^.src[0]);

    proto_type:= Header^.EthTypeHi SHL 8;
    proto_type:= proto_type + Header^.EthTypeLo;
    //console.output('net.eth2', 'PROTO: ');
    //console.writehexln(proto_type);

    buf:= buf + 14;

    copyMAC(@Header^.src[0], @p_context^.MAC.Source[0]);
    copyMAC(@Header^.dst[0], @p_context^.MAC.Destination[0]);

    if MACEqual(@Header^.dst[0], @Header^.src[0]) or MACEqual(@Header^.dst[0], @BROADCAST_MAC[0]) then begin
        //console.outputln('net.eth2', 'MAC HIT');
        if EthTypes[proto_type] <> nil then begin
            EthTypes[proto_type](void(buf), p_len - 14, p_context);
        end;    
    end;
    pop_trace;
end;

procedure register;
var
    i : uint16;

begin
    push_trace('eth2.register');
    if not Registered then begin
        for i:=0 to 65535 do begin
            EthTypes[i]:= nil;
        end;
        net.registerNextLayer(@recv);
        MAC:= net.getMAC;
        Registered:= true;
    end;
    pop_trace;
end;

end.