unit driver.storage.fs.ext2.types;

interface
uses driver.storage.types;

const
    EXT2_MAGIC = $EF53;
    EXT2_DIR = $4000;
    EXT2_FILE = $8000;
    EXT2_ROOT = 2;

type
    TExt2Inode = packed record
        Mode, UID : uint16;
        Size, ATime, CTime, MTime, DTime : uint32;
        GID, Links : uint16;
        Sectors, Flags, OSData : uint32;
        Blocks : array[0..14] of uint32;
        Generation, ACL, SizeHigh, Fragment : uint32;
        OSExtra : array[0..11] of uint8;
    end;
    PExt2Inode = ^TExt2Inode;
    TExt2Group = packed record
        BlockBitmap, InodeBitmap, InodeTable : uint32;
        FreeBlocks, FreeInodes, Directories, Pad : uint16;
        Reserved : array[0..2] of uint32;
    end;
    PExt2Group = ^TExt2Group;
    TExt2Dirent = packed record
        Inode : uint32;
        Length : uint16;
        NameLength, FileType : uint8;
    end;
    PExt2Dirent = ^TExt2Dirent;
    PExt2Volume = ^TExt2Volume;
    PExt2File = ^TExt2File;
    TExt2Volume = record
        Volume : PStorage_Volume;
        Super, Groups : puint8;
        BlockSize, SectorsPerBlock, BlockCount, InodeCount : uint32;
        FirstBlock, BlocksPerGroup, InodesPerGroup, InodeSize : uint32;
        GroupCount, GDTBlocks, AllocGroup : uint32;
        Busy, Writable, Poisoned, FileTypes : boolean;
        Files : PExt2File;
    end;
    TExt2File = record
        Volume : PExt2Volume;
        Inode : uint32;
        Next : PExt2File;
    end;
    { One operation owns its buffers. No DMA destination is shared with another
      operation. The volume lock protects metadata and all read/modify/write. }
    TExt2Op = record
        V : PExt2Volume;
        Scratch, Data : puint8;
        Error : TError;
        Mutating : boolean;
    end;
    PExt2Op = ^TExt2Op;

implementation
end.
