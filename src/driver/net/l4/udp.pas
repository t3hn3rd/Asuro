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
    hex     : puint8;
    i       : uint32;
    size    : uint16;

begin
    writeToLogLn('              L4: udp.recv');
    header:= PUDPHeader(p_data);
    //writestringln('UDP Packet: ');
    //hex:= puint8(p_data);
    //for i:=0 to 7 do begin
    //    writehexpair(hex^);
    //    hex:= hex+1;
    //end;
    //writestringln(' ');
    //Writeintln(switchendian16(header^.SrcPort));
    //Writeintln(header^.SrcPort);
    //Writeintln(switchendian16(header^.DstPort));
    //Writeintln(header^.DstPort);
    //writestringln('');
    if Ports[switchendian16(header^.DstPort)] <> nil then begin
        context:= PUDPPacketContext(kalloc(sizeof(TUDPPacketContext)));
        context^.PacketContext:= p_context;
        context^.SrcPort:= switchendian16(header^.SrcPort);
        context^.DstPort:= switchendian16(header^.DstPort);
        context^.ChecksumValid:= false;
        context^.Length:= switchendian16(header^.Length);
        buf:= puint8(p_data);
        buf:= buf + sizeof(TUDPHeader);
        size:= context^.Length - sizeof(TUDPHeader);
        bind:= Ports[context^.DstPort];
        bind^.Callback(void(buf), size, context);
    end;
end;

procedure TestRecv(p_data : void; p_len : uint16; context : PUDPPacketContext);
var
    Output : PChar;
    i      : uint16;

begin
    Output:= PChar(p_data);
    for i:=0 to p_len-1 do begin
        writechar(Output[i]);
    end;
    writestringln(' ');
end;

procedure register();
var
    i : uint16;
    context : PUDPBindContext;
    r       : TUDPError;

begin
    for i:=0 to 65535 do begin
        Ports[i]:= nil;
    end;
    context:= PUDPBindContext(kalloc(sizeof(TUDPBindContext)));
    context^.Port:= 22294;
    context^.Callback:= @TestRecv;
    context^.UID:= 4398724;
    r:= bind(context);
    writestring('[TestBind] ');
    case r of
        tueOK:writestringln('22294 bind OK');
        tuePortInUse:writestringln('22294 port in use');
        tueGenericError:writestringln('22294 generic error');
        tuePortRestricted:writestringln('22294 restricted');
    end;
    ipv4.registerProtocol($11, @UDPReceive);
end;

end.