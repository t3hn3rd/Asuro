unit eth2;

interface

uses
    lmemorymanager, util,
    tracer,
    nettypes, netutils, terminal,
    net,
    netlog,
    console,
    crc;

procedure send(p_data : void; p_len : uint16; eth_type : uint16; p_context : PPacketContext);
procedure registerType(eType : uint16; RecvCB : TRecvCallback);
procedure register;

implementation

uses
    arp;

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

procedure send(p_data : void; p_len : uint16; eth_type : uint16; p_context : PPacketContext);
var
    buffer : void;
    hdr    : TEthernetHeader;
    pad    : sint32;
    size   : uint32;
    FCS    : puint32;

begin
    pad:= 46 - p_len;
    if pad < 0 then pad:= 0;
    push_trace('eth2.send');
    writeToLogLn('    L2: eth2.send');
    if p_context <> nil then begin
        size:= sizeof(TEthernetHeader) + p_len;// + pad;// + 4;
        buffer:= kalloc(size);
        copyMAC(@p_context^.MAC.Source[0], @hdr.src[0]);
        copyMAC(@p_context^.MAC.Destination[0], @hdr.dst[0]);
        hdr.EthTypeHi:= eth_type SHR 8;
        hdr.EthTypeLo:= eth_type AND $FF;
        memcpy(uint32(@hdr), uint32(buffer), sizeof(TEthernetHeader));
        memcpy(uint32(p_data), uint32(buffer)+sizeof(TEthernetHeader), p_len);
        //FCS:= puint32((uint32(buffer) + size) - 4);
        //FCS^:= crc32(puint8(buffer), size - 4);
        net.send(buffer, size);
        kfree(buffer);
    end;
end;

procedure recv(p_data : void; p_len : uint16; p_context : PPacketContext);
var
    Header     : PEthernetHeader;
    proto_type : uint16;
    buf        : puint8;

begin
    push_trace('eth2.recv');
    writeToLogLn('    L2: eth2.recv');
    buf:= puint8(p_data);
    
    Header:= PEthernetHeader(buf);
    proto_type:= Header^.EthTypeHi SHL 8;
    proto_type:= proto_type + Header^.EthTypeLo;
    buf:= buf + 14;

    copyMAC(@Header^.src[0], @p_context^.MAC.Source[0]);
    copyMAC(@Header^.dst[0], @p_context^.MAC.Destination[0]);

    if MACEqual(@Header^.dst[0], @Header^.src[0]) or MACEqual(@Header^.dst[0], @BROADCAST_MAC[0]) then begin
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