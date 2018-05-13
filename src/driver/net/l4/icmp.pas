unit icmp;

interface

uses
    net, nettypes, netutils, ipv4, console;

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
    writestringlnWND('!', 0);
    Header:= PICMPHeader(p_data);
    case Header^.ICMP_Type of
        $08:Begin //Request
            contextMACSwitch(p_context);
            contextIPv4Switch(p_context);
            Header^.ICMP_Type:= 0;
            Header^.ICMP_CHK_Hi:= 0;
            Header^.ICMP_CHK_Lo:= 0;
            CHK:= calculateChecksum(puint16(p_data), sizeof(TICMPHeader));
            Header^.ICMP_CHK_Hi:= CHK SHR 8;
            Header^.ICMP_CHK_Lo:= CHK AND $FF;
            ipv4.send(p_data, p_len, p_context);    
        end;
        $00:begin //Reply
            
        end;
    end; 
end;

procedure register;
begin
    ipv4.registerProtocol($01, @recv);
end;

end.