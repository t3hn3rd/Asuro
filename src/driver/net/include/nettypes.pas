{ 
	Driver->Net->NetTypes - Structures & Types Shared Across Network Drivers.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit nettypes;

interface

type

    { Generic }

    TMACAddress  = Array[0..5] of uint8;
    TIPv4Address = Array[0..3] of uint8; 

    TMACPair = record
        Source      : TMACAddress;
        Destination : TMACAddress;
    end;

    TIPv4Pair = record
        Source      : TIPv4Address;
        Destination : TIPv4Address;
    end;

    TProtocol = record
        L1 : uint16;
        L2 : uint16;
        L3 : uint16;
        L4 : uint16;
    end;

    { Context }

    PPacketContext = ^TPacketContext;
    TPacketContext = record
        MAC : TMACPair;
        IP  : TIPv4Pair;
        Protocol : TProtocol;
        TTL : uint8;
    end;

    { Config }

    PIPv4Configuration = ^TIPv4Configuration;
    TIPv4Configuration = record
        Address   : array[0..3] of uint8;
        Gateway   : array[0..3] of uint8;
        Netmask   : array[0..3] of uint8;
        UP        : Boolean;
    end;

    { ICMP }

    PICMPHeader = ^TICMPHeader;
    TICMPHeader = record
        ICMP_Type   : uint8;
        ICMP_Code   : uint8;
        ICMP_CHK_Hi : uint8;
        ICMP_CHK_Lo : uint8;
        Identifier  : uint16;
        Sequence    : uint16;
    end;

    { ARP }

    TARPAbstractHeader = record
        Hardware_Type           : uint16;
        Protocol_Type           : uint16;
        Hardware_Address_Length : uint8;
        Protocol_Address_Length : uint8;
        Operation               : uint16;
        Source_Hardware         : TMACAddress;
        Source_Protocol         : TIPv4Address;
        Destination_Hardware    : TMACAddress;
        Destination_Protocol    : TIPv4Address;
    end;

    PARPHeader = ^TARPHeader;
    TARPHeader = bitpacked record
        Hardware_Type_Hi        : uint8;
        Hardware_Type_Lo        : uint8;
        Protocol_Type_Hi        : uint8;
        Protocol_Type_Lo        : uint8;
        Hardware_Address_Length : uint8;
        Protocol_Address_Length : uint8;
        Operation_Hi            : uint8;
        Operation_Lo            : uint8;
        Source_Hardware         : TMACAddress;
        Source_Protocol         : TIPv4Address;
        Destination_Hardware    : TMACAddress;
        Destination_Protocol    : TIPv4Address;
    end;

    { ETH2 }

    PEthernetHeader = ^TEthernetHeader;
    TEthernetHeader = bitpacked record
        dst       : array[0..5] of uint8;
        src       : array[0..5] of uint8;
        EthTypeHi : uint8;
        EthTypeLo : uint8;
    end;

    { IPv4 }

    PIPV4Header = ^TIPV4Header;
    TIPV4Header = bitpacked record
        header_len    : ubit4;
        version       : ubit4;
        ToS           : uint8;
        total_len_Hi  : uint8;
        total_len_Lo  : uint8;
        identifier_Hi : uint8;
        identifier_Lo : uint8;
        Flags         : ubit3; 
        Fragment_Off  : ubit13;
        TTL           : uint8;
        Protocol      : uint8;
        HDR_CHK_Hi    : uint8;
        HDR_CHK_Lo    : uint8;
        Src           : Array[0..3] of uint8;
        Dst           : Array[0..3] of uint8;
        Options       : ubit24;
        Padding       : uint8;
    end;

    TTCPFlags = record
        RS : Boolean;
        DF : Boolean;
        MF : Boolean;
    end;

    TIPV4AbstractHeader = record
        version       : uint8;
        header_len    : uint8;
        ToS           : uint8;
        total_len     : uint16;
        identifier    : uint16;
        Flags         : TTCPFlags;
        Fragment_Off  : uint16;
        TTL           : uint8;
        Protocol      : uint8;
        HDR_CHK       : uint16;
        Src           : Array[0..3] of uint8;
        Dst           : Array[0..3] of uint8;
        Options       : uint32;
    end;

    { UDP }
    TUDPError = (tueOK, tuePortInUse, tuePortRestricted, tuePortNotFound, tueInvalidUID, tueGenericError);
    PUDPPacketContext = ^TUDPPacketContext;
    TUDPRecieveCallback = procedure(p_data : void; p_len : uint16; context : PUDPPacketContext);
    TUDPPacketContext = record
        SrcPort       : uint16;
        DstPort       : uint16;
        ChecksumValid : Boolean;
        Length        : uint16;
        PacketContext : PPacketContext;
    end;
    PUDPBindContext = ^TUDPBindContext;
    TUDPBindContext = record
        Port          : uint16;
        Callback      : TUDPRecieveCallback;
        UID           : uint32;
    end;
    PUDPHeader = ^TUDPHeader;
    TUDPHeader = packed record
        SrcPort  : uint16;
        DstPort  : uint16;
        Length   : uint16;
        Checksum : uint16;
    end;
    TUDPSendContext = record
        DstPort : uint16;
        socket  : PUDPBindContext;
        context : PPacketContext;
    end;
    PUDPSendContext = ^TUDPSendContext;
    TUDPPseudoHeader = packed record
        Source_IP       : uint32;
        Destination_IP  : uint32;
        Protocol        : uint16;
        Length          : uint16;
        UDP_Source      : uint16;
        UDP_Destination : uint16;
        UDP_Length      : uint16;
    end;
    PUDPPseudoHeader = ^TUDPPseudoHeader;

    { DHCP }
    TDHCPHeader = packed record
        Message_Type            : uint8;
        Hardware_Type           : uint8;
        Hardware_Address_Length : uint8;
        Hops                    : uint8;
        Transaction_ID          : uint32;
        Seconds_Elapsed         : uint16;
        Bootp_Flags             : uint16;
        Client_IP               : TIPv4Address;
        Your_IP                 : TIPv4Address;
        Server_IP               : TIPV4Header;
        Relay_Agent_IP          : TIPV4Header;
        Client_MAC              : TMACAddress;
        Padding                 : Array[0..9] of uint8;
        Server_Hostname         : Array[0..63] of uint8;
        Boot_File               : Array[0..127] of uint8;
        Magic_Cookie            : Array[0..3] of uint8;
    end;
    PDHCPHeader = ^TDHCPHeader;
    TDHCPOpCode = (
        //BootTP Vendor Information Extensions
        PAD:= 0,
        SUBNET_MASK:= 1,
        TIME_OFFSET:= 2,
        ROUTER:= 3,
        TIME_SERVER:= 4,
        NAME_SERVER:= 5,
        DNS_SERVER:= 6,
        LOG_SERVER:= 7,
        COOKIE_SERVER:= 8,
        LPR_SERVER:= 9,
        IMPRESS_SERVER:= 10,
        RESOURCE_LOCATION_SERVER:= 11,
        HOST_NAME:= 12,
        BOOT_FILE_SIZE:= 13,
        MERIT_DUMP_FILE:= 14,
        DOMAIN_NAME:= 15,
        SWAP_SERVER:= 16,
        ROOT_PATH:= 17,
        EXTENSIONS_PATH:= 18,
        END_VENDOR_OPTIONS:= 255,
        //IP Layer Parameters Per Host
        IP_FORWARDING:= 19,
        NONLOCAL_SOURCE_ROUTING:= 20,
        POLICY_FILTER:= 21,
        MAXIMUM_DATAGRAM_REASSEMBLY_SIZE:= 22,
        DEFAULT_IP_TTL:= 23,
        PATH_MTU_AGING_TIMEOUT:= 24,
        PATH_MTU_PLATEAU_TABLE:= 25,
        //IP Layer Parameters Per Interface
        INTERFACE_MTU:= 26,
        ALL_SUBNETS_ARE_LOCAL:= 27,
        BROADCAST_ADDRESS:= 28,
        PERFORM_MASK_DISCOVERY:= 29,
        MASK_SUPPLIER:= 30,
        PERFORM_ROUTER_DISCOVERY:= 31,
        ROUTER_SOLICITATION_ADDRESS:= 32,
        STATIC_ROUTE:= 33,
        //Link Layer Parameters Per Interface
        TRAILER_ENCAPSULATION_OPTION:= 34,
        ARP_CACHE_TIMEOUT:= 35,
        ETHERNET_ENCAPSULATION:= 36,
        //TCP Parameters
        TCP_DEFAULT_TTL:= 37,
        TCP_KEEPALIVE_INTERVAL:= 38,
        TCP_KEEPALIVE_GARBAGE:= 39,
        //Application and Service Parameters
        NETWORK_INFORMATION_SERVICE_DOMAIN:= 40,
        NETWORK_INFORMATION_SERVERS:= 41,
        NTP_SERVERS:= 42,
        VENDOR_SPECIFIC_INFORMATION:= 43,
        NETBIOS_OVER_TCP_NAME_SERVER:= 44,
        NETBIOS_OVER_TCP_DATAGRAM_DISTRIBUTION_SERVER:= 45,
        NETBIOS_OVER_TCP_NODE_TYPE:= 46,
        NETBIOS_OVER_TCP_SCOPE:= 47,
        X_WINDOW_SYSTEM_FONT_SERVER:= 48,
        X_WINDOW_SYSTEM_DISPLAY_MANAGER:= 49,
        NETWORK_INFORMATION_SERVICE_PLUS_DOMAIN:= 64,
        NETWORK_INFORMATION_SERVICE_PLUS_SERVERS:= 65,
        MOBILE_IP_HOME_AGENT:= 68,
        SMTP_SERVER:= 69,
        POP3_SERVER:= 70,
        NNTP_SERVER:= 71,
        DEFAULT_WWW_SERVER:= 72,
        DEFAULT_FINGER_SERVER:= 73,
        DEFAULT_IRC_SERVER:= 74,
        STREETTALK_SERVER:= 75,
        STDA_SERVER:= 76,
        //DHCP Extensions
        REQUESTED_IP_ADDRESS:= 50,
        IP_ADDRESS_LEASE_TIME:= 51,
        OPTION_OVERLOAD:= 52,
        DHCP_MESSAGE_TYPE:= 53,
        SERVER_IDENTIFIER:= 54,
        PARAMETER_REQUEST_LIST:= 55,
        MESSAGE:= 56,
        MAXIMUM_DHCP_MESSAGE_SIZE:= 57,
        RENEWAL_T1_TIME_VALUE:= 58,
        REBINDING_T2_TIME_VALUE:= 59,
        VENDOR_CLASS_IDENTIFIER:= 60,
        CLIENT_IDENTIFIER:= 61,
        TFTP_SERVER_NAME:= 66,
        BOOTFILE_NAME:= 67,
        //Misc
        RELAY_AGENT_INFORMATION:= 82,
        NDS_SERVERS:= 85,
        NDS_TREE_NAME:= 86,
        NDS_CONTEXT:= 87,
        POSIX_TIMEZONE:= 100,
        TZ_TIMEZONE:= 101,
        DOMAIN_SEARCH:= 119,
        CLASSLESS_STATIC_ROUTE:= 121
    );
    TDHCPMessageType = (
        DISCOVER    := 1,
        OFFER       := 2,
        REQUEST     := 3,
        DECLINE     := 4,
        PACK        := 5,
        NAK         := 6,
        RELEASE     := 7,
        INFORM      := 8
    );

    { Callback Types }

    TNetSendCallback = function(p_data : void; p_len : uint16) : sint32;
    TRecvCallback    = procedure(p_data : void; p_len : uint16; p_context : PPacketContext);

{ Constants }

const
    { DHCP Magic }
    DHCP_MAGIC : Array[0..3] of uint8 = ($63, $82, $53, $63);

    { MACs }
    BROADCAST_MAC : Array[0..5] of uint8 = ($FF, $FF, $FF, $FF, $FF, $FF);
    NULL_MAC      : Array[0..5] of uint8 = ($00, $00, $00, $00, $00, $00);
    FORCE_MAC     : Array[0..5] of uint8 = ($08, $00, $27, $E6, $3F, $81);

    { IPs }
    BROADCAST_IP  : Array[0..3] of uint8 = ($FF, $FF, $FF, $FF);
    NULL_IP       : Array[0..3] of uint8 = ($00, $00, $00, $00);

    { ICMP Data }
    ICMP_DATA_GENERIC : Array[0..31] of uint8 = ( $61, $62, $63, $64, $65, $66, $67, $68, 
                                                  $69, $6a, $6b, $6c, $6d, $6e, $6f, $70, 
                                                  $71, $72, $73, $74, $75, $76, $77, $61, 
                                                  $62, $63, $64, $65, $66, $67, $68, $69 );

    { UDP Test Data }
    UDPT_S_IP : Array[0..3] of uint8 = ($C0, $A8, $00, $1F);
    UDPT_D_IP : Array[0..3] of uint8 = ($C0, $A8, $00, $1E);
    UDPT_DATA : Array[0..1] of uint8 = ($48, $69);


implementation

end.