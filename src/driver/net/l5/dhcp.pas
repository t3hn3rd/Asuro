unit dhcp;

interface

uses
    lmemorymanager, console,
    nettypes, netutils, udp, netlog, net,
    util, rand, lists, tracer, ipv4;

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

type
    TFlipExclude = Array[0..255] of boolean;
    PFlipExclude = ^TFlipExclude;

var
    XID         : uint32;
    Socket      : PUDPBindContext;
    FlipExclude : PFlipExclude;

function newHeader : PDHCPHeader;
begin
    tracer.push_trace('dhcp.newHeader');
    newHeader:= PDHCPHeader(kalloc(sizeof(TDHCPHeader)));
end;

function newOption(DHCPOptions : PDHCPOptions; Opcode : TDHCPOpCode; Data : void; Length : uint32; SwapEndian : Boolean) : PDHCPOption;
var
    Option : PDHCPOption;

begin
    tracer.push_trace('dhcp.newOption');
    Option:= PDHCPOption(LL_Add(PLinkedListBase(DHCPOptions)));
    Option^.Opcode:= Opcode;
    Option^.Size:= Length;
    Option^.Reverse_Endian:= SwapEndian;
    if Length > 0 then begin
        Option^.Value:= kalloc(Length);
        memcpy(uint32(Data), uint32(Option^.Value), Length);
    end else begin
        Option^.Value:= nil;
    end;
    newOption:= Option;
end;

procedure deleteOption(DHCPOptions : PDHCPOptions; idx : uint32);
var
    Option : PDHCPOption;

begin
    tracer.push_trace('dhcp.deleteOptions');
    Option:= PDHCPOption(LL_Get(PLinkedListBase(DHCPOptions), idx));
    if Option <> nil then begin
        if Option^.Value <> nil then begin
            kfree(Option^.Value);
        end;
        LL_Delete(PLinkedListBase(DHCPOptions), idx);
    end;
end;

function getOption(DHCPOptions : PDHCPOptions; idx : uint32) : PDHCPOption;
begin
    tracer.push_trace('dhcp.getOption');
    getOption:= PDHCPOption(LL_Get(PLinkedListBase(DHCPOptions),idx));
end;

function newOptions : PDHCPOptions;
begin
    tracer.push_trace('dhcp.newOptions');
    newOptions:= PDHCPOptions(LL_New(sizeof(TDHCPOption)));
end;

procedure freeOptions(Options : PDHCPOptions);
begin
    tracer.push_trace('dhcp.freeOptions');
    if Options <> nil then begin
        while LL_Size(PLinkedListBase(Options)) > 0 do begin
            deleteOption(Options, 0);
        end;
        LL_Free(PLinkedListBase(Options));
    end;
end;

function getOptionsCount(Options : PDHCPOptions) : uint32;
begin
    tracer.push_trace('dhcp.getOptionsCount');
    getOptionsCount:= LL_Size(PLinkedListBase(Options));
end;    

function calculateOptionsSize(Options : PDHCPOptions) : uint16;
var
    i : uint32;
    Option : PDHCPOption;
    OptionsSize : uint16;

begin
    tracer.push_trace('dhcp.calculateOptionsSize');
    OptionsSize := 0;
    for i:=0 to getOptionsCount(Options)-1 do begin
        Option:= PDHCPOption(LL_Get(PLinkedListBase(Options),i));
        case Option^.Opcode of
            PAD,END_VENDOR_OPTIONS : inc(OptionsSize,1);
            else inc(OptionsSize, 2 + Option^.Size);
        end;
    end;
    calculateOptionsSize:= OptionsSize;
end;

function getEndianCorrectValue16(Option : PDHCPOption) : uint16;
var
    Value : uint16;

begin
    tracer.push_trace('dhcp.getEndianCorrectValue16');
    Value:= PuInt16(Option^.Value)^;
    if Option^.Reverse_Endian then 
        getEndianCorrectValue16:= switchendian16(Value) 
    else 
        getEndianCorrectValue16:= Value;
end;

function getEndianCorrectValue32(Option : PDHCPOption) : uint32;
var
    Value : uint32;
begin
    tracer.push_trace('dhcp.getEndianCorrectValue32');
    Value:= puint32(Option^.Value)^;
    if Option^.Reverse_Endian then
        getEndianCorrectValue32:= switchendian32(Value)
    else
        getEndianCorrectValue32:= Value;
end;

function writeOptions(Header : PDHCPHeader; Options : PDHCPOptions; newLength : puint16) : PDHCPHeader;
var
    OptionsSize : uint16;
    TotalSize   : uint16;
    NewBuffer   : void;
    NewHeader   : PDHCPHeader;
    buffer      : puint8;
    read8       : puint8;
    read16      : puint16;
    read32      : puint32;
    Option      : PDHCPOption;
    i           : uint32;

begin
    tracer.push_trace('dhcp.writeOptions');
    OptionsSize := calculateOptionsSize(Options);
    TotalSize:= OptionsSize + SizeOf(TDHCPHeader);
    NewBuffer:= kalloc(TotalSize);

    //Copy over Header
    NewHeader:= PDHCPHeader(buffer);
    memcpy(uint32(Header), uint32(NewHeader), sizeof(TDHCPHeader));

    //Write all options
    buffer:= puint8(NewBuffer);
    inc(buffer, SizeOf(TDHCPHeader));
    for i:=0 to getOptionsCount(Options)-1 do begin
        Option:= getOption(Options, i);
        case Option^.Opcode of
            PAD,END_VENDOR_OPTIONS:begin
                buffer^:= Ord(Option^.Opcode);
                inc(buffer);
            end;
            else begin
                buffer^:= Ord(Option^.OpCode);
                inc(buffer);
                buffer^:= Option^.Size;
                inc(buffer);
                case Option^.Size of
                    2:begin
                        read16:= puint16(buffer);
                        read16^:= getEndianCorrectValue16(Option);
                    end;
                    4:begin
                        read32:= puint32(buffer);
                        read32^:= getEndianCorrectValue32(Option);
                    end;
                    else begin
                        memcpy(uint32(Option^.Value), uint32(buffer), Option^.Size);
                    end;
                end;
                inc(buffer, Option^.Size);
            end;
        end;
    end;
    newLength^:= TotalSize;
    writeOptions:= PDHCPHeader(NewBuffer);
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
    read32 : puint32;
    read16 : puint16;
    Option : PDHCPOption;

begin
    tracer.push_trace('dhcp.register');
    HeaderSize:= sizeOf(TDHCPHeader);
    bufferEnd:= puint8(uint32(p_data) + p_len);
    bufferStart:= puint8(uint32(p_data) + headerSize);
    buffer:= bufferStart;
    HaveOp:= false;
    HaveLen:= false;
    while (uint32(buffer) < uint32(bufferEnd)) do begin
        if HaveLen then begin
            Option:= newOption(DHCPOptions, Opcode, void(buffer), Length, not FlipExclude^[ord(Opcode)]);
            if Length = 2 then begin
                if Option^.Reverse_Endian then begin
                    read16:= puint16(Option^.Value);
                    read16^:= switchendian16(read16^);
                end;
            end;
            if Length = 4 then begin
                if Option^.Reverse_Endian then begin
                    read32:= puint32(Option^.Value);
                    read32^:= switchendian32(read32^);
                end;
            end;
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
                PAD,END_VENDOR_OPTIONS:begin
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
var
    Header : PDHCPHeader;
    Options : PDHCPOptions;

begin
    tracer.push_trace('dhcp.processPacket');
    Header:= PDHCPHeader(p_data);
    Options:= newOptions;
    readOptions(Options, p_data, p_len);
end;

procedure DHCPDiscover();
var
    Header      : PDHCPHeader;
    NewHeader   : PDHCPHeader;
    HeaderSize  : Puint32; 
    Options     : PDHCPOptions;
    MsgType     : uint8;

begin
    tracer.push_trace('dhcp.DHCPDiscover');
    Header:= newHeader;
    Options:= newOptions;
    XID:= rand32();
    
    //Setup header
    Header^.Message_Type:= $01;
    Header^.Hardware_Type:= $01;
    Header^.Hardware_Address_Length:= $06;
    Header^.Hops:= $00;
    Header^.Transaction_ID:= switchendian32(XID);
    Header^.Seconds_Elapsed:= $0000;
    CopyIPv4(@NULL_IP[0], @Header^.Client_IP[0]);
    CopyIPv4(@NULL_IP[0], @Header^.Your_IP[0]);
    CopyIPv4(@NULL_IP[0], @Header^.Server_IP[0]);
    CopyIPv4(@NULL_IP[0], @Header^.Relay_Agent_IP[0]);
    CopyMAC(@getMAC[0], @Header^.Client_MAC[0]);
    memset(uint32(@Header^.Padding[0]), 0, 10);
    memset(uint32(@Header^.Server_Hostname[0]), 0, 64);
    memset(uint32(@Header^.Boot_File[0]), 0, 128);
    memcpy(uint32(@DHCP_MAGIC[0]), uint32(@Header^.Magic_Cookie[0]), 4);

    //Setup options
    MsgType:= Ord(TDHCPMessageType.DISCOVER);
    newOption(Options, DHCP_MESSAGE_TYPE, void(@MsgType), 1, false);

    NewOption(Options, END_VENDOR_OPTIONS, nil, 0, false);

    getIPv4Config^.UP:= true;

end;

procedure register();
var
    i : uint8;

begin
    tracer.push_trace('dhcp.register');
    console.outputln('DHCP', 'Register begin.');
    FlipExclude:= PFlipExclude(kalloc(sizeof(TFlipExclude)));
    for i:=0 to 255 do begin
        FlipExclude^[i]:= false;
    end;
    FlipExclude^[ord(PAD)]:= true;
    FlipExclude^[ord(SUBNET_MASK)]:= true;
    FlipExclude^[ord(ROUTER)]:= true;
    FlipExclude^[ord(TIME_SERVER)]:= true;
    FlipExclude^[ord(NAME_SERVER)]:= true;
    FlipExclude^[ord(DNS_SERVER)]:= true;
    FlipExclude^[ord(LOG_SERVER)]:= true;
    FlipExclude^[ord(COOKIE_SERVER)]:= true;
    FlipExclude^[ord(LPR_SERVER)]:= true;
    FlipExclude^[ord(IMPRESS_SERVER)]:= true;
    FlipExclude^[ord(RESOURCE_LOCATION_SERVER)]:= true;
    FlipExclude^[ord(HOST_NAME)]:= true;
    FlipExclude^[ord(MERIT_DUMP_FILE)]:= true;
    FlipExclude^[ord(DOMAIN_NAME)]:= true;
    FlipExclude^[ord(SWAP_SERVER)]:= true;
    FlipExclude^[ord(ROOT_PATH)]:= true;
    FlipExclude^[ord(EXTENSIONS_PATH)]:= true;
    FlipExclude^[ord(END_VENDOR_OPTIONS)]:= true;
    FlipExclude^[ord(BROADCAST_ADDRESS)]:= true;
    FlipExclude^[ord(ROUTER_SOLICITATION_ADDRESS)]:= true;
    FlipExclude^[ord(STATIC_ROUTE)]:= true;
    FlipExclude^[ord(NETWORK_INFORMATION_SERVICE_DOMAIN)]:= true;
    FlipExclude^[ord(NETWORK_INFORMATION_SERVERS)]:= true;
    FlipExclude^[ord(NTP_SERVERS)]:= true;
    FlipExclude^[ord(VENDOR_SPECIFIC_INFORMATION)]:= true;
    FlipExclude^[ord(NETBIOS_OVER_TCP_NAME_SERVER)]:= true;
    FlipExclude^[ord(NETBIOS_OVER_TCP_DATAGRAM_DISTRIBUTION_SERVER)]:= true;
    FlipExclude^[ord(NETBIOS_OVER_TCP_SCOPE)]:= true;
    FlipExclude^[ord(X_WINDOW_SYSTEM_FONT_SERVER)]:= true;
    FlipExclude^[ord(X_WINDOW_SYSTEM_DISPLAY_MANAGER)]:= true;
    FlipExclude^[ord(NETWORK_INFORMATION_SERVICE_PLUS_DOMAIN)]:= true;
    FlipExclude^[ord(NETWORK_INFORMATION_SERVICE_PLUS_SERVERS)]:= true;
    FlipExclude^[ord(MOBILE_IP_HOME_AGENT)]:= true;
    FlipExclude^[ord(SMTP_SERVER)]:= true;
    FlipExclude^[ord(POP3_SERVER)]:= true;
    FlipExclude^[ord(NNTP_SERVER)]:= true;
    FlipExclude^[ord(DEFAULT_WWW_SERVER)]:= true;
    FlipExclude^[ord(DEFAULT_FINGER_SERVER)]:= true;
    FlipExclude^[ord(DEFAULT_IRC_SERVER)]:= true;
    FlipExclude^[ord(STREETTALK_SERVER)]:= true;
    FlipExclude^[ord(STDA_SERVER)]:= true;
    FlipExclude^[ord(REQUESTED_IP_ADDRESS)]:= true;
    FlipExclude^[ord(SERVER_IDENTIFIER)]:= true;
    FlipExclude^[ord(PARAMETER_REQUEST_LIST)]:= true;
    FlipExclude^[ord(VENDOR_CLASS_IDENTIFIER)]:= true;
    FlipExclude^[ord(CLIENT_IDENTIFIER)]:= true;
    FlipExclude^[ord(TFTP_SERVER_NAME)]:= true;
    FlipExclude^[ord(BOOTFILE_NAME)]:= true;
    FlipExclude^[ord(RELAY_AGENT_INFORMATION)]:= true;
    FlipExclude^[ord(NDS_SERVERS)]:= true;
    FlipExclude^[ord(NDS_TREE_NAME)]:= true;
    FlipExclude^[ord(NDS_CONTEXT)]:= true;
    FlipExclude^[ord(POSIX_TIMEZONE)]:= true;
    FlipExclude^[ord(TZ_TIMEZONE)]:= true;
    FlipExclude^[ord(DOMAIN_SEARCH)]:= true;
    FlipExclude^[ord(CLASSLESS_STATIC_ROUTE)]:= true;
    Socket:= PUDPBindContext(Kalloc(sizeof(TUDPBindContext)));
    Socket^.Port:= 68;
    Socket^.Callback:= @processPacket;
    Socket^.UID:= rand32;
    case UDP.bind(Socket) of
        tueOK:console.outputln('DHCP', 'Successfully bound port 68.');
        else console.outputln('DHCP', 'Failed to bind port 68.');
    end;
    DHCPDiscover;
    console.outputln('DHCP', 'Register end.');
end;

end.