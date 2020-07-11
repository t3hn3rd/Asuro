unit dhcp;

interface

uses
    lmemorymanager, console,
    nettypes, netutils, udp, netlog, net,
    util, rand, lists, tracer;

type
    TDHCPOptions = PLinkedListBase;
    PDHCPOptions = ^PLinkedListBase;
    TDHCPOption = record
        Opcode          : TDHCPOpCode;
        Size            : uint32;
        Value           : void;
        Reverse_Endian  : boolean;
    end;
    PDHCPOption = ^TDHCPOption;

procedure register();
procedure DHCPDiscover();

implementation

var
    XID         : uint32;
    Socket      : PUDPBindContext;
    FlipExclude : bitpacked Array[0..255] of boolean;

procedure newOption(DHCPOptions : PDHCPOptions; Opcode : TDHCPOpCode; Data : void; Length : uint32; SwapEndian : Boolean);
var
    Option : PDHCPOption;
    read32 : puint32;
    read16 : puint16;

begin
    Option:= PDHCPOption(LL_Add(PLinkedListBase(DHCPOptions)));
    Option^.Opcode:= Opcode;
    Option^.Size:= Length;
    Option^.Reverse_Endian:= SwapEndian;
    if Length > 0 then begin
        Option^.Value:= kalloc(Length);
        memcpy(uint32(Data), uint32(Option^.Value), Length);
        if Length = 2 then begin
            if SwapEndian then begin
                read16:= puint16(Option^.Value);
                read16^:= switchendian16(read16^);
            end;
        end;
        if Length = 4 then begin
            if SwapEndian then begin
                read32:= puint32(Option^.Value);
                read32^:= switchendian32(read32^);
            end;
        end;
    end else begin
        Option^.Value:= nil;
    end;
end;

procedure deleteOption(DHCPOptions : PDHCPOptions; idx : uint32);
var
    Option : PDHCPOption;

begin
    Option:= PDHCPOption(LL_Get(PLinkedListBase(DHCPOptions), idx));
    if Option <> nil then begin
        if Option^.Value <> nil then begin
            kfree(Option^.Value);
        end;
        LL_Delete(PLinkedListBase(DHCPOptions), idx);
    end;
end;

function newOptions : PDHCPOptions;
begin
    newOptions:= PDHCPOptions(LL_New(sizeof(TDHCPOption)));
end;

procedure freeOptions(Options : PDHCPOptions);
begin
    if Options <> nil then begin
        while LL_Size(PLinkedListBase(Options)) > 0 do begin
            deleteOption(Options, 0);
        end;
        LL_Free(PLinkedListBase(Options));
    end;
end;

function writeOptions(Header : PDHCPHeader; Options : PDHCPOptions; newLength : puint16) : PDHCPHeader;
begin

end;

procedure readOptions(DHCPOptions : PDHCPOptions; p_data : void; p_len : uint16);
var
    headerSize : uint32;
    
    buffer     : puint8;

    bufferEnd   : puint8;
    bufferStart : puint8;

    HaveOp      : boolean;
    HaveLen     : boolean;

    Opcode      : TDHCPOpCode;
    Length      : uint8;

begin
    HeaderSize:= sizeOf(TDHCPHeader);
    bufferEnd:= puint8(uint32(p_data) + p_len);
    bufferStart:= puint8(uint32(p_data) + headerSize);
    buffer:= bufferStart;
    HaveOp:= false;
    HaveLen:= false;
    while (uint32(buffer) < uint32(bufferEnd)) do begin
        if HaveLen then begin
            newOption(DHCPOptions, Opcode, void(buffer), Length, not FlipExclude[ord(Opcode)]);
            inc(buffer, Length);
            HaveOp:= false;
            HaveLen:= false;
        end else if HaveOp then begin
            Length:= buffer^;
            HaveLen:= true;
            inc(buffer);
        end else begin
            Opcode:= TDHCPOpCode(buffer^);
            case opcode of
                PAD:begin
                    Length:= 0;
                    haveLen:= true;
                end;
                END_VENDOR_OPTIONS:begin
                    Length:= 0;
                    haveLen:= true;
                end;
            end;
            HaveOp:= true;
            inc(buffer)
        end;
    end;
end;

procedure processPacket(p_data : void; p_len : uint16; context : PUDPPacketContext);
begin

end;

procedure DHCPDiscover();
begin

end;

procedure register();
var
    i : uint8;

begin
    tracer.push_trace('dhcp.register');
    console.outputln('DHCP', 'Register begin.');
    for i:=0 to 255 do begin
        FlipExclude[i]:= false;
    end;
    // FlipExclude[ord(PAD)]:= true;
    // FlipExclude[ord(SUBNET_MASK)]:= true;
    // FlipExclude[ord(ROUTER)]:= true;
    // FlipExclude[ord(TIME_SERVER)]:= true;
    // FlipExclude[ord(NAME_SERVER)]:= true;
    // FlipExclude[ord(DNS_SERVER)]:= true;
    // FlipExclude[ord(LOG_SERVER)]:= true;
    // FlipExclude[ord(COOKIE_SERVER)]:= true;
    // FlipExclude[ord(LPR_SERVER)]:= true;
    // FlipExclude[ord(IMPRESS_SERVER)]:= true;
    // FlipExclude[ord(RESOURCE_LOCATION_SERVER)]:= true;
    // FlipExclude[ord(HOST_NAME)]:= true;
    // FlipExclude[ord(MERIT_DUMP_FILE)]:= true;
    // FlipExclude[ord(DOMAIN_NAME)]:= true;
    // FlipExclude[ord(SWAP_SERVER)]:= true;
    // FlipExclude[ord(ROOT_PATH)]:= true;
    // FlipExclude[ord(EXTENSIONS_PATH)]:= true;
    // FlipExclude[ord(END_VENDOR_OPTIONS)]:= true;
    // FlipExclude[ord(BROADCAST_ADDRESS)]:= true;
    // FlipExclude[ord(ROUTER_SOLICITATION_ADDRESS)]:= true;
    // FlipExclude[ord(STATIC_ROUTE)]:= true;
    // FlipExclude[ord(NETWORK_INFORMATION_SERVICE_DOMAIN)]:= true;
    // FlipExclude[ord(NETWORK_INFORMATION_SERVERS)]:= true;
    // FlipExclude[ord(NTP_SERVERS)]:= true;
    // FlipExclude[ord(VENDOR_SPECIFIC_INFORMATION)]:= true;
    // FlipExclude[ord(NETBIOS_OVER_TCP_NAME_SERVER)]:= true;
    // FlipExclude[ord(NETBIOS_OVER_TCP_DATAGRAM_DISTRIBUTION_SERVER)]:= true;
    // FlipExclude[ord(NETBIOS_OVER_TCP_SCOPE)]:= true;
    // FlipExclude[ord(X_WINDOW_SYSTEM_FONT_SERVER)]:= true;
    // FlipExclude[ord(X_WINDOW_SYSTEM_DISPLAY_MANAGER)]:= true;
    // FlipExclude[ord(NETWORK_INFORMATION_SERVICE_PLUS_DOMAIN)]:= true;
    // FlipExclude[ord(NETWORK_INFORMATION_SERVICE_PLUS_SERVERS)]:= true;
    // FlipExclude[ord(MOBILE_IP_HOME_AGENT)]:= true;
    // FlipExclude[ord(SMTP_SERVER)]:= true;
    // FlipExclude[ord(POP3_SERVER)]:= true;
    // FlipExclude[ord(NNTP_SERVER)]:= true;
    // FlipExclude[ord(DEFAULT_WWW_SERVER)]:= true;
    // FlipExclude[ord(DEFAULT_FINGER_SERVER)]:= true;
    // FlipExclude[ord(DEFAULT_IRC_SERVER)]:= true;
    // FlipExclude[ord(STREETTALK_SERVER)]:= true;
    // FlipExclude[ord(STDA_SERVER)]:= true;
    // FlipExclude[ord(REQUESTED_IP_ADDRESS)]:= true;
    // FlipExclude[ord(SERVER_IDENTIFIER)]:= true;
    // FlipExclude[ord(PARAMETER_REQUEST_LIST)]:= true;
    // FlipExclude[ord(VENDOR_CLASS_IDENTIFIER)]:= true;
    // FlipExclude[ord(CLIENT_IDENTIFIER)]:= true;
    // FlipExclude[ord(TFTP_SERVER_NAME)]:= true;
    // FlipExclude[ord(BOOTFILE_NAME)]:= true;
    // FlipExclude[ord(RELAY_AGENT_INFORMATION)]:= true;
    // FlipExclude[ord(NDS_SERVERS)]:= true;
    // FlipExclude[ord(NDS_TREE_NAME)]:= true;
    // FlipExclude[ord(NDS_CONTEXT)]:= true;
    // FlipExclude[ord(POSIX_TIMEZONE)]:= true;
    // FlipExclude[ord(TZ_TIMEZONE)]:= true;
    // FlipExclude[ord(DOMAIN_SEARCH)]:= true;
    // FlipExclude[ord(CLASSLESS_STATIC_ROUTE)]:= true;
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