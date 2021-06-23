unit color;

interface

type
    TRGB32 = bitpacked record
        B : uint8;
        G : uint8;
        R : uint8;
        A : uint8;
    end;

    TRGB24 = bitpacked record
        B : uint8;
        G : uint8;
        R : uint8;
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

const
    black : TRGB32 = (B: 000; G: 000; R: 000; A: 000);
    white : TRGB32 = (B: 255; G: 255; R: 255; A: 000);

implementation

end.