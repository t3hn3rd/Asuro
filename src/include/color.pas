unit color;

interface

type
    TRGB32 = bitpacked record
        B : uint8;
        G : uint8;
        R : uint8;
        A : uint8;
    end;

    TRGB16 = bitpacked record
        B : UBit5;
        G : UBit6;
        R : UBit5;
    end;

    TRGB8 = bitpacked record
        B : UBit2;
        G : UBit4;
        R : UBit2;
    end;

implementation

end.