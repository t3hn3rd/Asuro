unit dhcp;

interface

uses
    lmemorymanager, console,
    nettypes, netutils, udp, netlog, net,
    util, rand, lists;

type
    TDHCPOptions = PLinkedListBase;
    PDHCPOptions = ^PLinkedListBase;
    TDHCPOption = record
        Opcode          : TDHCPOpCode;
        Size            : uint32;
        Value           : void;
        Header_Location : void;
        Reverse_Endian  : boolean;
    end;
    PDHCPOption = ^TDHCPOption;

procedure register();
procedure DHCPDiscover();

implementation

var
    XID     : uint32;
    Socket  : PUDPBindContext;

procedure processPacket(p_data : void; p_len : uint16; context : PUDPPacketContext);
begin

end;

procedure DHCPDiscover();
begin

end;

procedure register();
begin
    console.outputln('DHCP', 'Register begin.');
    Socket:= PUDPBindContext(Kalloc(sizeof(TUDPBindContext)));
    Socket^.Port:= 68;
    Socket^.Callback:= @processPacket;
    Socket^.UID:= rand32;
    case UDP.bind(Socket) of
        tueOK:console.outputln('DHCP', 'Successfully bound port 68.');
        else console.outputln('DHCP', 'Failed to bind port 68.');
    end;
    console.outputln('DHCP', 'Register end.');
end;

end.