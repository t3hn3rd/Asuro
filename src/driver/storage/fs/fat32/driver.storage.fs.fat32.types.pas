unit driver.storage.fs.fat32.types;

interface

uses
    driver.storage.types;

type
    TBootRecord = bitpacked record
        jmp2boot        : ubit24;
        OEMName         : array[0..7] of char;
        sectorSize      : uint16;
        spc             : uint8;
        rsvSectors      : uint16;
        numFats         : uint8;
        numDirEnt       : uint16;
        numSectors      : uint16;
        mediaDescp      : uint8;
        sectorsPerFat   : uint16;
        sectorsPerTrack : uint16;
        heads           : uint16;
        hiddenSectors   : uint32;
        manySectors     : uint32;
        FATSize         : uint32;
        flags           : uint16;
        FATVersion      : uint16;
        rootCluster     : uint32;
        FSInfoCluster   : uint16;
        backupCluster   : uint16;
        reserved0       : array[0..11] of uint8;
        driveNumber     : uint8;
        reserved1       : uint8;
        bsignature      : uint8;
        volumeID        : uint32;
        volumeLabel     : array[0..10] of uint8;
        identString     : array[0..7] of char;
    end;
    PBootRecord = ^TBootRecord;

    TFATExtArray = array[0..2] of char;

    TDirectory = packed record
        fileName      : array[0..7] of char;
        fileExtension : TFATExtArray;
        attributes    : uint8;
        reserved0     : uint8;
        timeFine      : uint8;
        time          : uint16;
        date          : uint16;
        accessTime    : uint16;
        clusterHigh   : uint16;
        modifiedTime  : uint16;
        modifiedDate  : uint16;
        clusterLow    : uint16;
        byteSize      : uint32;
    end;
    PDirectory = ^TDirectory;

    TFilesystemInfo = record
        leadSignature   : uint32;
        reserved0       : array[0..479] of uint8;
        structSignature : uint32;
        freeSectors     : uint32;
        nextFreeSector  : uint32;
        reserved1       : array[0..11] of uint8;
        trailSignature  : uint32;
    end;

const
    FAT_CACHE_SETS = 512;
    FAT_CACHE_WAYS = 2;
    FAT_CACHE_LINES = FAT_CACHE_SETS * FAT_CACHE_WAYS;
    FAT_TRANSFER_POOL_CAPACITY = 64;
    FAT_ALLOC_HINT_SLOTS = 8;
    FAT_DIR_HINT_SLOTS = 16;
    FAT_WRITE_PREALLOC_BYTES = 16 * 1024 * 1024;
    FAT_WRITE_PREALLOC_MAX_CLUSTERS = 2048;
    FAT_WRITE_PREALLOC_MIN_CLUSTERS = 64;
    FAT_MAX_IO_SECTORS = 2048;

type
    TFATCacheLine = record
        SectorIdx : uint32;
        Dirty     : boolean;
        Valid     : boolean;
        LRU       : uint8;
    end;

    PFATCache = ^TFATCache;
    TFATCache = record
        Lines    : array[0..FAT_CACHE_LINES - 1] of TFATCacheLine;
        Data     : puint32;
        EvictBuf : puint32;
        Busy     : boolean;
        FatStart : uint32;
        Device   : PStorage_Device;
    end;

    PFATRun = ^TFATRun;
    TFATRun = record
        StartCluster : uint32;
        ClusterCount : uint32;
    end;

    TFATAllocHint = record
        Valid        : boolean;
        StartCluster : uint32;
        ClusterCount : uint32;
        Stamp        : uint32;
    end;

    TFATDirHint = record
        Valid         : boolean;
        ParentCluster : uint32;
        SectorLBA     : uint32;
        EntryIdx      : uint32;
        Stamp         : uint32;
    end;

    TFATRunMap = record
        Runs         : PFATRun;
        Count        : uint32;
        Capacity     : uint32;
        TotalClusters: uint32;
    end;

    PFATVolumeInfo = ^TFATVolumeInfo;
    TFATVolumeInfo = record
        BootRecord      : TBootRecord;
        DataStart       : uint32;
        BytesPerCluster : uint32;
        MaxCluster      : uint32;
    end;

    TFATDirEntryLocation = record
        Valid         : boolean;
        ParentCluster : uint32;
        SectorLBA     : uint32;
        EntryIdx      : uint32;
    end;

    TFATOpenCursor = record
        Valid            : boolean;
        RunIdx           : uint32;
        FileClusterStart : uint32;
    end;

    PFATOpenFile = ^TFATOpenFile;
    TFATOpenFile = record
        Volume        : PStorage_Volume;
        VolumeInfo    : PFATVolumeInfo;
        FirstCluster  : uint32;
        ByteSize      : uint32;
        AllocClusters : uint32;
        RunMap        : TFATRunMap;
        Cursor        : TFATOpenCursor;
        ScratchSector : puint32;
        ScratchSize   : uint32;
        CleanName     : byteArray8;
        ExtPart       : pchar;
        DirLoc        : TFATDirEntryLocation;
        Exists        : boolean;
        FatDirty      : boolean;
        MetaDirty     : boolean;
    end;

    TFATTransferMode = (ftmRead, ftmWrite);
    TFATTransferPhase = (
        ftpIdle,
        ftpAwaitDirect,
        ftpAwaitScratchRead,
        ftpAwaitScratchWrite,
        ftpComplete,
        ftpError
    );

    PFATVolumeCtx = ^TFATVolumeCtx;
    PFATTransferCtx = ^TFATTransferCtx;

    TFATTransferCtx = record
        Next                 : PFATTransferCtx;
        VolumeCtx            : PFATVolumeCtx;
        Mode                 : TFATTransferMode;
        Phase                : TFATTransferPhase;
        Volume               : PStorage_Volume;
        OpenFile             : PFATOpenFile;
        Buffer               : puint32;
        Offset               : uint32;
        ByteCount            : uint32;
        BytesDone            : uint32;
        BytesOut             : puint32;
        Callback             : TIOCallback;
        CallbackData         : pointer;
        PendingLBA           : uint32;
        PendingSectors       : uint32;
        PendingAdvanceBytes  : uint32;
        PendingScratchOffset : uint32;
        PendingScratchBytes  : uint32;
        PendingBufferOffset  : uint32;
        ScratchSector        : puint32;
        ScratchSize          : uint32;
        RunHintValid         : boolean;
        RunHintIndex         : uint32;
        RunHintFileCluster   : uint32;
        LastError            : TError;
    end;

    TFATVolumeCtx = record
        Cache             : TFATCache;
        Info              : TFATVolumeInfo;
        InfoValid         : boolean;
        TransferPoolBuf   : pointer;
        TransferScratchBuf: pointer;
        TransferFreeList  : pointer;
        HintStamp         : uint32;
        AllocHints        : array[0..FAT_ALLOC_HINT_SLOTS - 1] of TFATAllocHint;
        DirHints          : array[0..FAT_DIR_HINT_SLOTS - 1] of TFATDirHint;
    end;

implementation

end.
