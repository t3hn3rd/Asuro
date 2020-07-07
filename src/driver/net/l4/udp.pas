{ 
	Driver->Net->L4->UDP - User Datagram Protocol Driver.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit udp;

interface

uses
    lmemorymanager,
    nettypes, netutils,
    ipv4, netlog, net,
    util;

var
    Ports : Array[0..65535] of PUDPBindContext;

procedure register();

implementation

uses
    console, terminal;

function bind(bindContext : PUDPBindContext) : TUDPError;
var
    result  : TUDPError;
    context : PUDPBindContext;

begin
    result:= tueGenericError;
    if bindContext <> nil then begin
        if Ports[bindContext^.port] = nil then begin
            context:= PUDPBindContext(kalloc(sizeof(TUDPBindContext)));
            context^.Port:= bindContext^.port;
            context^.Callback:= bindContext^.Callback;
            context^.UID:= bindContext^.UID;
            Ports[context^.Port]:= context;
            result:= tueOK;
        end else begin
            result:= tuePortInUse;
        end;
    end;
    bind:= result;
end;

function unbind(bindContext : PUDPBindContext) : TUDPError;
var
    result : TUDPError;
    context : PUDPBindContext;

begin
    result:= tueGenericError;
    if bindContext <> nil then begin
        context:= Ports[bindContext^.port];
        if Ports[bindContext^.port] <> nil then begin
            if context^.UID = bindContext^.UID then begin
                kfree(void(context));
                Ports[bindContext^.port]:= nil;
                result:= tueOK;
            end else begin
                result:= tueInvalidUID;
            end;
        end else begin
            result:= tuePortNotFound;
        end;
    end;
end;

procedure UDPReceive(p_data : void; p_len : uint16; p_context : PPacketContext);
var
    header  : PUDPHeader;
    context : PUDPPacketContext;
    buf     : puint8;
    bind    : PUDPBindContext;

begin
    writeToLogLn('              L4: udp.recv');
    header:= PUDPHeader(p_data);
    if switchendian16(header^.SrcPort) = 22294 then WriteStringln('Src-E: 22294');
    if header^.SrcPort = 22294 then WriteStringln('Src: 22294');
    if switchendian16(header^.DstPort) = 22294 then WriteStringln('Dst-E: 22294');
    if header^.DstPort = 22294 then WriteStringln('Dst: 22294');
    if Ports[header^.DstPort] <> nil then begin
        bind:= Ports[header^.DstPort];
        context:= PUDPPacketContext(kalloc(sizeof(TUDPPacketContext)));
        context^.PacketContext:= p_context;
        context^.SrcPort:= header^.SrcPort;
        context^.DstPort:= header^.DstPort;
        context^.ChecksumValid:= false;
        context^.Length:= header^.Length;
        buf:= puint8(p_data);
        buf:= buf + (sizeof(TUDPHeader));
        bind^.Callback(void(buf), context^.Length, context);
    end;
end;

procedure TestRecv(p_data : void; p_len : uint16; context : PUDPPacketContext);
var
    Output : PChar;

begin
    Output:= PChar(kalloc(p_len+1));
    memcpy(uint32(p_data), uint32(Output), p_len);
    Output[p_len+1]:= Char(0);
    Writestringln(Output);
end;

procedure register();
var
    i : uint16;
    context : TUDPBindContext;
    r       : TUDPError;

begin
    for i:=0 to 65535 do begin
        Ports[i]:= nil;
    end;
    context.Port:= 22294;
    context.Callback:= @TestRecv;
    context.UID:= 4398724;
    r:= bind(@context);
    case r of
        tueOK:writestringln('22294 bind OK');
        tuePortInUse:writestringln('22294 port in use');
        tueGenericError:writestringln('22294 generic error');
        tuePortRestricted:writestringln('22294 restricted');
    end;
    ipv4.registerProtocol($11, @UDPReceive);
end;

end.