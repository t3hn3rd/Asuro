unit nettypes;

interface

type
    TNetSendCallback = function(p_data : void; p_len : uint16) : sint32;
    TRecvCallback    = procedure(p_data : void; p_len : uint16);

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

const
    BROADCAST_MAC : Array[0..5] of uint8 = ($FF, $FF, $FF, $FF, $FF, $FF);

implementation

end.