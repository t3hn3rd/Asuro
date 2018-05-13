unit icmp;

interface

uses
    net, nettypes, netutils, ipv4, console, terminal;

procedure register;

implementation

procedure sendResponse(p_context : PPacketContext);
begin

end;

procedure sendRequest(ip : puint8);
begin

end;

procedure recv(p_data : void; p_len : uint16; p_context : PPacketContext);
var
    Header : PICMPHeader;
    CHK    : uint16;

begin
    writeToLogLn('            L4: icmp.recv');
    Header:= PICMPHeader(p_data);
    //writehexlnWND(Header^.ICMP_Type, getTerminalHWND); 
    case Header^.ICMP_Type of
        $08:Begin //Request
            writeToLogLn('            L4: icmp.request');
            contextMACSwitch(p_context);
            contextIPv4Switch(p_context);
            Header^.ICMP_Type:= 0;
            Header^.ICMP_CHK_Hi:= 0;
            Header^.ICMP_CHK_Lo:= 0;
            CHK:= calculateChecksum(puint16(p_data), p_len);
            Header^.ICMP_CHK_Hi:= CHK AND $FF;
            Header^.ICMP_CHK_Lo:= CHK SHR 8;
            p_context^.Protocol.L4:= $01;
            p_context^.TTL:= 128;
            ipv4.send(p_data, p_len, p_context);    
        end;
        $00:begin //Reply
            writeToLogLn('            L4: icmp.reply');
        end;
    end; 
end;

procedure register;
begin
    ipv4.registerProtocol($01, @recv);
end;

end.