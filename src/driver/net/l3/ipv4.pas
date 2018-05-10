unit ipv4;

interface

uses
    tracer, lmemorymanager,
    util, console, terminal, strings,
    net, nettypes, netutils,
    netlog,
    lists,
    eth2;

procedure registerProtocol(Protocol_ID : uint8; recv_callback : TRecvCallback);
function  getIPv4Config : PIPv4Configuration;
procedure register;

implementation

uses
    arp;

var
    Registered : Boolean = false;
    Protocols  : Array[0..255] of TRecvCallback;
    Config     : TIPv4Configuration;

function  getIPv4Config : PIPv4Configuration;
begin
    getIPv4Config:= @Config;
end;

procedure recv(p_data : void; p_len : uint16; p_context : PPacketContext);
var
    Header  : PIPV4Header;
    AHeader : TIPV4AbstractHeader;
    i       : Integer;
    buf     : puint8;
    len     : uint16;

begin
    push_trace('ipv4.recv');
    writeToLogLn('        L3: ipv4.recv');
    Header:= PIPV4Header(p_data);
    AHeader.version:= Header^.version;
    AHeader.header_len:= Header^.header_len;
    AHeader.ToS:= Header^.ToS;
    AHeader.total_len:= (Header^.total_len_Hi SHL 8) + Header^.total_len_Lo;
    AHeader.identifier:= (Header^.identifier_Hi SHL 8) + Header^.identifier_Lo;
    AHeader.Flags.RS:= false;
    AHeader.Flags.DF:= (Header^.Flags AND $2) > 0;
    AHeader.Flags.MF:= (Header^.Flags AND $1) > 0;
    AHeader.Fragment_Off:= Header^.Fragment_Off;
    AHeader.TTL:= Header^.TTL;
    AHeader.Protocol:= Header^.Protocol;
    AHeader.HDR_CHK:= (Header^.HDR_CHK_Hi SHL 8) + Header^.HDR_CHK_Lo;
    for i:=0 to 3 do begin
        AHeader.Src[i]:= Header^.Src[i];
        AHeader.Dst[i]:= Header^.Dst[i];
    end;
    AHeader.Options:= Header^.Options;

    //console.output('net.ipv4', 'Source: ');
    //writeIPv4Address(puint8(@AHeader.Src[0]));
    //console.output('net.ipv4', 'Dest: ');
    //writeIPv4Address(puint8(@AHeader.Dst[0]));

    buf:= puint8(p_data);
    buf:= buf + AHeader.header_len;
    len:= p_len - AHeader.header_len;

    copyIPv4(@AHeader.Src[0], @p_context^.IP.Source[0]);
    copyIPv4(@AHeader.Dst[0], @p_context^.IP.Destination[0]);

    if (IPEqual(@Config.Address[0], @AHeader.Dst[0])) OR (AHeader.Dst[3] = 255) then begin
        if Protocols[AHeader.Protocol] <> nil then Protocols[AHeader.Protocol](void(buf), len, p_context);
    end;
    pop_trace;
end;

procedure terminal_command_ifconfig(params : PParamList);
var
    Command, Sub, Address, Gateway, Netmask : pchar;
    _Address, _Gateway, _Netmask : puint8;
    context : PPacketContext;

begin
    push_trace('ipv4.terminal_command_ifconfig');
    if paramCount(params) > 1 then begin
        Command:= GetParam(0, Params);
        if StringEquals(Command, 'set') then begin
            if paramCount(params) > 3 then begin
                Address:= GetParam(1, Params);
                Gateway:= GetParam(2, Params);
                Netmask:= GetParam(3, Params);
                _Address:= stringToIPv4(Address);
                _Gateway:= stringToIPv4(Gateway);
                _Netmask:= stringToIPv4(Netmask);
                copyIPv4(_Address, @Config.Address[0]);
                copyIPv4(_Gateway, @Config.Gateway[0]);
                copyIPv4(_Netmask, @Config.Netmask[0]);
                kfree(void(_Address));
                kfree(void(_Gateway));
                kfree(void(_Netmask));
            end else begin
                writestringlnWND('Invalid number of params to call ''set''.', getTerminalHWND);
            end;
        end;
        if StringEquals(Command, 'net') then begin
            Sub:= GetParam(1, Params);
            if StringEquals(Sub, 'up') then begin
                Config.UP:= true;
            end;
            if StringEquals(Sub, 'down') then begin
                Config.UP:= false;
            end;
        end;
        arp.sendGratuitous;
        context:= newPacketContext;
        CopyIPv4(@Config.Gateway[0], @context^.IP.Destination[0]);
        CopyIPv4(@Config.Address[0], @context^.IP.Source[0]);
        CopyMAC(GetMAC, @context^.MAC.Source[0]);
        //copyMAC(@FORCE_MAC[0], @context^.MAC.Source[0]);
        CopyMAC(@BROADCAST_MAC[0], @context^.MAC.Destination[0]);
        arp.send($1, $0800, $1, context);
        freePacketContext(context);
    end else begin
        writestringWND('   MAC:     ', getTerminalHWND);
        writeMACAddress(net.GetMAC, getTerminalHWND);
        writestringWND('   IPv4:    ', getTerminalHWND);
        writeIPv4Address(@Config.Address[0], getTerminalHWND);
        writestringWND('   Gateway: ', getTerminalHWND);
        writeIPv4Address(@Config.Gateway[0], getTerminalHWND);
        writestringWND('   Netmask: ', getTerminalHWND);
        writeIPv4Address(@Config.Netmask[0], getTerminalHWND);
        if Config.UP then 
            writestringlnWND('   NetUP:   true', getTerminalHWND) 
        else 
            writestringlnWND('   NetUP:   false', getTerminalHWND);
    end;
    pop_trace;
end;

procedure register;
var
    i : uint8;

begin
    push_trace('ipv4.register');
    if not Registered then begin
        for i:=0 to 255 do begin
            Protocols[i]:= nil;
        end;
        for i:=0 to 3 do begin
            Config.Address[i]:= 0;
            Config.Gateway[i]:= 0;
            Config.Netmask[i]:= 0;
        end;
        Config.UP:= false;
        eth2.registerType($0800, @recv);
        terminal.registerCommand('IFCONFIG', @terminal_command_ifconfig, 'Configure Network Settings.');
        Registered:= true;
    end;
    pop_trace;
end;

procedure registerProtocol(Protocol_ID : uint8; recv_callback : TRecvCallback);
begin
    push_trace('ipv4.registerProtocol');
    register;
    if Protocols[Protocol_ID] = nil then Protocols[Protocol_ID]:= recv_callback;
    pop_trace;
end;

end.