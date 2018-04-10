unit nettypes;

interface

type


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

    PPacketContext = ^TPacketContext;
    TPacketContext = record
        MAC : TMACPair;
        IP  : TIPv4Pair;
    end;

    PIPv4Configuration = ^TIPv4Configuration;
    TIPv4Configuration = record
        Address   : array[0..3] of uint8;
        Gateway   : array[0..3] of uint8;
        Netmask   : array[0..3] of uint8;
        UP        : Boolean;
    end;

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

    PEthernetHeader = ^TEthernetHeader;
    TEthernetHeader = bitpacked record
        dst       : array[0..5] of uint8;
        src       : array[0..5] of uint8;
        EthTypeHi : uint8;
        EthTypeLo : uint8;
    end;

    PIPV4Header = ^TIPV4Header;
    TIPV4Header = bitpacked record
        version       : ubit4;
        header_len    : ubit4;
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

    TNetSendCallback = function(p_data : void; p_len : uint16) : sint32;
    TRecvCallback    = procedure(p_data : void; p_len : uint16; p_context : PPacketContext);

const
    BROADCAST_MAC : Array[0..5] of uint8 = ($FF, $FF, $FF, $FF, $FF, $FF);

implementation

end.