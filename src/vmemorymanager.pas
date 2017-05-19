unit vmemorymanager;

interface

type
    {PPageTableEntry = ^TPageTableEntry;
    TPageTableEntry = bitpacked record
        Present, 
        Writable, 
        UserMode, 
        WriteThrough,
        NotCacheable, 
        Accessed, 
        Dirty, 
        AttrIndex,
        GlobalPage: Boolean;
        Available: UBit3;
        FrameAddress: UBit20;
    end;}

    PPageDirEntry = ^TPageDirEntry;
    TPageDirEntry = bitpacked record
        Present, 
        Writable, 
        UserMode, 
        WriteThrough,
        NotCacheable, 
        Accessed, 
        Reserved, 
        PageSize,
        GlobalPage: Boolean;
        Available: UBit3;
        TableAddress: UBit20;
    end;

    TPageDirectory = Array[1..1024] of TPageDirEntry;
    PPageDirectory = ^TPageDirectory;

Var
    PageDirectory : TPageDirectory; external name '_PageDirectory';

implementation

end.