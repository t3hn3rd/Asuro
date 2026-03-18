unit driver.storage.fs.fat32.vol;

{
    Volume lifecycle functions for the FAT32 filesystem driver.
    Handles volume detection, identification, and formatting.
}

interface

uses
    driver.storage.types,
    driver.storage.fs.fat32.types;

procedure FAT32VolInit(fs : PFilesystem);
procedure detect_volumes(disk : PStorage_Device);
function  identify_volume(volume : PStorage_Volume) : boolean;
procedure create_volume(volume : PStorage_Volume; sectors : uint32; start : uint32; config : PFSFormatParams);
procedure create_volume_async(volume : PStorage_Volume; sectors : uint32; start : uint32;
    config : PFSFormatParams; callback : TIOCallback; callbackData : pointer);

implementation

uses
    io.syslog,
    debug.tracer,
    memory.heap,
    core.util, arch.x86.util,
    driver.storage.mgr,
    driver.storage.vol.mgr,
    driver.storage.fs.fat32.core;

{ ===================== Types ===================== }

type
    TFmtStep = (fmtBootSector, fmtZeroFAT, fmtFATEntries, fmtRootDir, fmtSystemDir, fmtDone);

    PFmtContext = ^TFmtContext;
    TFmtContext = record
        Volume       : PStorage_Volume;
        Disk         : PStorage_Device;
        SectorStart  : uint32;
        RootCluster  : uint32;
        Callback     : TIOCallback;
        CallbackData : pointer;
        Buffer       : puint32;
        ZeroBuffer   : puint32;
        SPC          : uint32;
        FATSize      : uint32;
        FATStart     : uint32;
        DataStart    : uint32;
        BatchSize    : uint32;
        BatchPos     : uint32;
        Step         : TFmtStep;
    end;

{ ===================== Module state ===================== }

var
    fat32FilesystemPtr : PFilesystem = nil;

{ ===================== Private helpers ===================== }

function bootSectorHasSignature(buffer : puint32) : boolean;
begin
    bootSectorHasSignature := (puint8(uint32(buffer) + 510)^ = $55) and
                              (puint8(uint32(buffer) + 511)^ = $AA);
end;

function clusterToLBA(dataStart : uint32; spc : uint32; cluster : uint32) : uint32;
begin
    if cluster < 2 then
        clusterToLBA := dataStart
    else
        clusterToLBA := dataStart + ((cluster - 2) * spc);
end;

function fatDefaultSPC(sectors : uint32; sectorSize : uint32) : uint32;
begin
    if sectorSize = 0 then begin
        fatDefaultSPC := 1;
        exit;
    end;
    fatDefaultSPC := 4096 div sectorSize;
    if fatDefaultSPC = 0 then
        fatDefaultSPC := 1;
    if fatDefaultSPC > 64 then
        fatDefaultSPC := 64;
end;

function fatComputeFATSize(sectors : uint32; spc : uint32; sectorSize : uint32) : uint32;
var
    clusterCount : uint32;
    fatBytes     : uint32;
begin
    if spc = 0 then spc := 1;
    if sectorSize = 0 then begin
        fatComputeFATSize := 0;
        exit;
    end;
    clusterCount := (sectors + spc - 1) div spc;
    fatBytes := clusterCount * 4;
    fatComputeFATSize := (fatBytes + sectorSize - 1) div sectorSize;
    if fatComputeFATSize = 0 then
        fatComputeFATSize := 1;
end;

function fatFormatConfigSPC(config : PFSFormatParams; sectors : uint32; sectorSize : uint32) : uint32;
begin
    fatFormatConfigSPC := 0;
    if (config <> nil) and
       (config^.Version = FS_FORMAT_PARAMS_VERSION_1) and
       ((config^.Flags and FS_FORMAT_PARAM_CLUSTER_SIZE) <> 0) then
        fatFormatConfigSPC := config^.ClusterSize;
    if fatFormatConfigSPC = 0 then
        fatFormatConfigSPC := fatDefaultSPC(sectors, sectorSize);
    if fatFormatConfigSPC = 0 then
        fatFormatConfigSPC := 1;
end;

{ Counts free FAT clusters by scanning the FAT directly (no cache).
  Used during detect/identify to compute freeSectors. }
function countFreeFATClusters(volume : PStorage_Volume; bootRecord : PBootRecord) : uint32;
var
    fatStart       : uint32;
    maxCluster     : uint32;
    entriesPerSect : uint32;
    sectorIdx      : uint32;
    entryIdx       : uint32;
    clusterNum     : uint32;
    freeCount      : uint32;
    fatSectors     : uint32;
    fatBuffer      : puint32;
begin
    countFreeFATClusters := 0;
    if (bootRecord^.sectorSize = 0) or (bootRecord^.FATSize = 0) then exit;

    fatStart := volume^.sectorStart + bootRecord^.rsvSectors;
    maxCluster := (bootRecord^.FATSize * bootRecord^.sectorSize) div 4;
    entriesPerSect := bootRecord^.sectorSize div 4;
    fatSectors := bootRecord^.FATSize;

    fatBuffer := puint32(kalloc(bootRecord^.sectorSize));
    if fatBuffer = nil then exit;
    freeCount := 0;

    if fatSectors > 0 then
    for sectorIdx := 0 to fatSectors - 1 do begin
        if sectorIdx * entriesPerSect >= maxCluster then break;
        driver.storage.mgr.storage_read(volume^.device, fatStart + sectorIdx, 1, fatBuffer);
        if entriesPerSect > 0 then
        for entryIdx := 0 to entriesPerSect - 1 do begin
            clusterNum := sectorIdx * entriesPerSect + entryIdx;
            if clusterNum < 2 then continue;
            if clusterNum >= maxCluster then break;
            if fatBuffer[entryIdx] = 0 then
                freeCount := freeCount + 1;
        end;
    end;

    kfree(fatBuffer);
    countFreeFATClusters := freeCount;
end;

{ ===================== Async format state machine ===================== }

procedure fmt_run_next(ctx : PFmtContext); forward;

procedure fmt_step_complete(error : TError; userdata : pointer);
var
    ctx : PFmtContext;
begin
    ctx := PFmtContext(userdata);
    if error <> eNone then begin
        io.syslog.logln('FAT32', 'fmt_step_complete: I/O error — aborting format');
        if ctx^.Buffer <> nil then kfree(ctx^.Buffer);
        if ctx^.ZeroBuffer <> nil then kfree(ctx^.ZeroBuffer);
        if ctx^.Callback <> nil then
            ctx^.Callback(error, ctx^.CallbackData);
        kfree(puint32(ctx));
        exit;
    end;

    case ctx^.Step of
        fmtBootSector: begin
            ctx^.Step    := fmtZeroFAT;
            ctx^.BatchPos := 0;
        end;
        fmtZeroFAT: begin
            ctx^.BatchPos := ctx^.BatchPos + ctx^.BatchSize;
        end;
        fmtFATEntries: begin
            ctx^.Step := fmtRootDir;
        end;
        fmtRootDir: begin
            ctx^.Step := fmtSystemDir;
        end;
        fmtSystemDir: begin
            ctx^.Step := fmtDone;
        end;
    end;
    fmt_run_next(ctx);
end;

procedure fmt_run_next(ctx : PFmtContext);
var
    writeCount : uint32;
begin
    case ctx^.Step of
        fmtBootSector: begin
            io.syslog.logln('FAT32', 'fmt: fmtBootSector');
            driver.storage.mgr.storage_write_async(ctx^.Disk, ctx^.SectorStart, 1,
                ctx^.Buffer, @fmt_step_complete, pointer(ctx));
        end;

        fmtZeroFAT: begin
            { Transition to next step once the FAT is fully zeroed }
            if ctx^.BatchPos >= ctx^.FATSize then begin
                io.syslog.logln('FAT32', 'fmt: FAT zero complete, moving to fmtFATEntries');
                kfree(ctx^.ZeroBuffer);
                ctx^.ZeroBuffer := nil;
                kfree(ctx^.Buffer);
                ctx^.Buffer := puint32(kalloc(ctx^.Disk^.sectorSize));
                memset(uint32(ctx^.Buffer), 0, ctx^.Disk^.sectorSize);
                { FAT entries: [0]=media end-of-partition, [1]=EOC, [2]=root cluster EOC, [3]=SYSTEM EOC }
                puint32(ctx^.Buffer)[0] := $0FFFFFF8;
                puint32(ctx^.Buffer)[1] := $0FFFFFFF;
                puint32(ctx^.Buffer)[2] := $0FFFFFF8;
                puint32(ctx^.Buffer)[3] := $0FFFFFF8;
                ctx^.Step := fmtFATEntries;
                fmt_run_next(ctx);
                exit;
            end;
            if (ctx^.FATSize - ctx^.BatchPos) >= ctx^.BatchSize then
                writeCount := ctx^.BatchSize
            else
                writeCount := ctx^.FATSize - ctx^.BatchPos;
            driver.storage.mgr.storage_write_async(ctx^.Disk,
                ctx^.FATStart + ctx^.BatchPos, writeCount, ctx^.ZeroBuffer,
                @fmt_step_complete, pointer(ctx));
        end;

        fmtFATEntries: begin
            io.syslog.logln('FAT32', 'fmt: fmtFATEntries');
            driver.storage.mgr.storage_write_async(ctx^.Disk, ctx^.FATStart, 1,
                ctx^.Buffer, @fmt_step_complete, pointer(ctx));
        end;

        fmtRootDir: begin
            io.syslog.logln('FAT32', 'fmt: fmtRootDir');
            memset(uint32(ctx^.Buffer), 0, ctx^.Disk^.sectorSize);
            { '.' entry — volume label }
            PDirectory(ctx^.Buffer)[0].fileName[0] := '.';
            PDirectory(ctx^.Buffer)[0].fileName[1] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[2] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[3] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[4] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[5] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[6] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[7] := ' ';
            PDirectory(ctx^.Buffer)[0].attributes := $08;
            PDirectory(ctx^.Buffer)[0].clusterLow := ctx^.RootCluster;
            { '..' entry }
            PDirectory(ctx^.Buffer)[1].fileName[0] := '.';
            PDirectory(ctx^.Buffer)[1].fileName[1] := '.';
            PDirectory(ctx^.Buffer)[1].fileName[2] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[3] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[4] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[5] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[6] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[7] := ' ';
            PDirectory(ctx^.Buffer)[1].attributes := $10;
            PDirectory(ctx^.Buffer)[1].clusterLow := ctx^.RootCluster;
            { Pre-allocated SYSTEM dir entry (cluster 3) }
            PDirectory(ctx^.Buffer)[2].fileName[0] := 'S';
            PDirectory(ctx^.Buffer)[2].fileName[1] := 'Y';
            PDirectory(ctx^.Buffer)[2].fileName[2] := 'S';
            PDirectory(ctx^.Buffer)[2].fileName[3] := 'T';
            PDirectory(ctx^.Buffer)[2].fileName[4] := 'E';
            PDirectory(ctx^.Buffer)[2].fileName[5] := 'M';
            PDirectory(ctx^.Buffer)[2].fileName[6] := ' ';
            PDirectory(ctx^.Buffer)[2].fileName[7] := ' ';
            PDirectory(ctx^.Buffer)[2].attributes := $10;
            PDirectory(ctx^.Buffer)[2].clusterLow := 3;
            driver.storage.mgr.storage_write_async(ctx^.Disk,
                clusterToLBA(ctx^.DataStart, ctx^.SPC, ctx^.RootCluster), 1, ctx^.Buffer,
                @fmt_step_complete, pointer(ctx));
        end;

        fmtSystemDir: begin
            io.syslog.logln('FAT32', 'fmt: fmtSystemDir');
            memset(uint32(ctx^.Buffer), 0, ctx^.Disk^.sectorSize);
            PDirectory(ctx^.Buffer)[0].fileName[0] := '.';
            PDirectory(ctx^.Buffer)[0].fileName[1] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[2] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[3] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[4] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[5] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[6] := ' ';
            PDirectory(ctx^.Buffer)[0].fileName[7] := ' ';
            PDirectory(ctx^.Buffer)[0].attributes := $10;
            PDirectory(ctx^.Buffer)[0].clusterLow := 3;
            PDirectory(ctx^.Buffer)[1].fileName[0] := '.';
            PDirectory(ctx^.Buffer)[1].fileName[1] := '.';
            PDirectory(ctx^.Buffer)[1].fileName[2] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[3] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[4] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[5] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[6] := ' ';
            PDirectory(ctx^.Buffer)[1].fileName[7] := ' ';
            PDirectory(ctx^.Buffer)[1].attributes := $10;
            PDirectory(ctx^.Buffer)[1].clusterLow := ctx^.RootCluster;
            driver.storage.mgr.storage_write_async(ctx^.Disk,
                clusterToLBA(ctx^.DataStart, ctx^.SPC, 3), 1, ctx^.Buffer,
                @fmt_step_complete, pointer(ctx));
        end;

        fmtDone: begin
            io.syslog.logln('FAT32', 'fmt: fmtDone — format complete');
            kfree(ctx^.Buffer);
            ctx^.Buffer := nil;
            if ctx^.Callback <> nil then
                ctx^.Callback(eNone, ctx^.CallbackData);
            kfree(puint32(ctx));
        end;
    end;
end;

{ ===================== Exported procedures ===================== }

procedure FAT32VolInit(fs : PFilesystem);
begin
    fat32FilesystemPtr := fs;
end;

procedure detect_volumes(disk : PStorage_Device);
var
    buffer  : puint32;
    bufSize : uint32;
    volume  : PStorage_Volume;
    br      : PBootRecord;
begin
    push_trace('driver.storage.fs.fat32.detect_volumes');
    if fat32FilesystemPtr = nil then exit;

    bufSize := disk^.sectorSize;
    if bufSize < 512 then bufSize := 512;
    buffer := puint32(kalloc(bufSize));
    if buffer = nil then exit;
    memset(uint32(buffer), 0, bufSize);

    if disk^.dispatchRead = nil then begin
        io.syslog.logln('FAT32', 'detect_volumes: device has no read dispatch');
        kfree(buffer);
        exit;
    end;

    driver.storage.mgr.storage_read(disk, 0, 1, buffer);

    br := PBootRecord(buffer);
    if bootSectorHasSignature(buffer) and (br^.bsignature = $29) then begin
        io.syslog.logln('FAT32', 'detect_volumes: volume found');
        volume := PStorage_Volume(kalloc(sizeof(TStorage_Volume)));
        if volume = nil then begin
            kfree(buffer);
            exit;
        end;
        memset(uint32(volume), 0, sizeof(TStorage_Volume));
        volume^.device      := disk;
        volume^.sectorStart := 0;
        volume^.sectorSize  := br^.sectorSize;
        volume^.sectorCount := disk^.maxSectorCount;
        volume^.filesystem  := fat32FilesystemPtr;
        volume^.freeSectors := countFreeFATClusters(volume, br) * br^.spc;
        volume^.isBootDrive := false;
        driver.storage.vol.mgr.register_volume(disk, volume);
    end;

    kfree(buffer);
end;

function identify_volume(volume : PStorage_Volume) : boolean;
var
    buffer    : puint32;
    br        : PBootRecord;
    bufSize   : uint32;
    fatNameOk : boolean;
    spc       : uint8;
    i         : uint32;
begin
    push_trace('driver.storage.fs.fat32.identify_volume');
    identify_volume := false;
    if volume = nil then exit;
    if volume^.device = nil then exit;
    if volume^.device^.dispatchRead = nil then exit;

    bufSize := volume^.device^.sectorSize;
    if bufSize < 512 then bufSize := 512;
    buffer := puint32(kalloc(bufSize));
    if buffer = nil then exit;
    memset(uint32(buffer), 0, bufSize);

    driver.storage.mgr.storage_read(volume^.device, volume^.sectorStart, 1, buffer);
    br := PBootRecord(buffer);

    fatNameOk := true;
    for i := 0 to 4 do
        if br^.identString[i] <> 'FAT32'[i + 1] then begin
            fatNameOk := false;
            break;
        end;

    spc := br^.spc;

    if bootSectorHasSignature(buffer) and
       (br^.bsignature = $29) and
       fatNameOk and
       (br^.sectorSize = volume^.device^.sectorSize) and
       (br^.sectorSize >= 512) and
       (spc <> 0) and
       ((spc and (spc - 1)) = 0) and
       (br^.rsvSectors > 0) and
       (br^.FATSize > 0) and
       (br^.numFats > 0) and
       (br^.rootCluster >= 2) then begin
        io.syslog.logln('FAT32', 'identify_volume: FAT32 signature matched');
        identify_volume := true;
        volume^.freeSectors := countFreeFATClusters(volume, br) * br^.spc;
    end else
        io.syslog.logln('FAT32', 'identify_volume: not a FAT32 volume');

    kfree(buffer);
end;

procedure create_volume(volume : PStorage_Volume; sectors : uint32; start : uint32; config : PFSFormatParams);
var
    buffer     : puint32;
    zeroBuffer : puint32;
    bootRecord : PBootRecord;
    dataStart  : uint32;
    fatStart   : uint32;
    FATSize    : uint32;
    batchSize  : uint32;
    batchPos   : uint32;
    rootCluster: uint32;
    spc        : uint32;
    disk       : PStorage_Device;
    status     : uint32;
begin
    push_trace('driver.storage.fs.fat32.create_volume');
    io.syslog.logln('FAT32', 'create_volume (sync): enter');

    disk := volume^.device;
    rootCluster := 2;
    spc := fatFormatConfigSPC(config, sectors, disk^.sectorSize);

    buffer := puint32(kalloc(disk^.sectorSize + 512));
    if buffer = nil then exit;
    memset(uint32(buffer), 0, disk^.sectorSize);

    bootRecord := PBootRecord(buffer);
    FATSize := fatComputeFATSize(sectors, spc, disk^.sectorSize);

    bootRecord^.jmp2boot        := $0;
    bootRecord^.OEMName[0]      := 'A';
    bootRecord^.OEMName[1]      := 'S';
    bootRecord^.OEMName[2]      := 'U';
    bootRecord^.OEMName[3]      := 'R';
    bootRecord^.OEMName[4]      := 'O';
    bootRecord^.OEMName[5]      := ' ';
    bootRecord^.OEMName[6]      := 'V';
    bootRecord^.OEMName[7]      := '1';
    bootRecord^.sectorSize      := disk^.sectorSize;
    bootRecord^.spc             := uint8(spc);
    bootRecord^.rsvSectors      := 32;
    bootRecord^.numFats         := 1;
    bootRecord^.mediaDescp      := $F8;
    bootRecord^.hiddenSectors   := start;
    bootRecord^.manySectors     := sectors;
    bootRecord^.FATSize         := FATSize;
    bootRecord^.rootCluster     := rootCluster;
    bootRecord^.FSInfoCluster   := 0;
    bootRecord^.driveNumber     := $80;
    bootRecord^.volumeID        := 62;
    bootRecord^.bsignature      := $29;
    bootRecord^.identString[0]  := 'F';
    bootRecord^.identString[1]  := 'A';
    bootRecord^.identString[2]  := 'T';
    bootRecord^.identString[3]  := '3';
    bootRecord^.identString[4]  := '2';
    bootRecord^.identString[5]  := ' ';
    bootRecord^.identString[6]  := ' ';
    bootRecord^.identString[7]  := ' ';

    puint8(uint32(buffer) + 510)^ := $55;
    puint8(uint32(buffer) + 511)^ := $AA;

    driver.storage.mgr.storage_write(disk, start, 1, buffer);
    io.syslog.logln('FAT32', 'create_volume (sync): boot sector written');

    fatStart  := start + 32;
    dataStart := fatStart + FATSize;

    if FATSize > 128 then
        batchSize := 128
    else
        batchSize := FATSize;

    zeroBuffer := puint32(kalloc(disk^.sectorSize * batchSize));
    if zeroBuffer = nil then begin
        kfree(buffer);
        exit;
    end;
    memset(uint32(zeroBuffer), 0, disk^.sectorSize * batchSize);

    batchPos := 0;
    while batchPos < FATSize do begin
        if (FATSize - batchPos) >= batchSize then
            driver.storage.mgr.storage_write(disk, fatStart + batchPos, batchSize, zeroBuffer)
        else
            driver.storage.mgr.storage_write(disk, fatStart + batchPos, FATSize - batchPos, zeroBuffer);
        batchPos := batchPos + batchSize;
    end;

    kfree(zeroBuffer);
    io.syslog.logln('FAT32', 'create_volume (sync): FAT zeroed');

    memset(uint32(buffer), 0, disk^.sectorSize);
    puint32(buffer)[0] := $0FFFFFF8;   { media descriptor / reserved }
    puint32(buffer)[1] := $0FFFFFFF;   { end-of-chain marker }
    puint32(buffer)[2] := $0FFFFFF8;   { root cluster 2 — end-of-chain }

    driver.storage.mgr.storage_write(disk, fatStart, 1, buffer);
    io.syslog.logln('FAT32', 'create_volume (sync): FAT entries written');

    { Write root dir: '.' and '..' entries }
    memset(uint32(buffer), 0, disk^.sectorSize);
    PDirectory(buffer)[0].fileName[0] := '.';
    PDirectory(buffer)[0].fileName[1] := ' ';
    PDirectory(buffer)[0].fileName[2] := ' ';
    PDirectory(buffer)[0].fileName[3] := ' ';
    PDirectory(buffer)[0].fileName[4] := ' ';
    PDirectory(buffer)[0].fileName[5] := ' ';
    PDirectory(buffer)[0].fileName[6] := ' ';
    PDirectory(buffer)[0].fileName[7] := ' ';
    PDirectory(buffer)[0].attributes := $08;
    PDirectory(buffer)[0].clusterLow := uint16(rootCluster);
    PDirectory(buffer)[1].fileName[0] := '.';
    PDirectory(buffer)[1].fileName[1] := '.';
    PDirectory(buffer)[1].fileName[2] := ' ';
    PDirectory(buffer)[1].fileName[3] := ' ';
    PDirectory(buffer)[1].fileName[4] := ' ';
    PDirectory(buffer)[1].fileName[5] := ' ';
    PDirectory(buffer)[1].fileName[6] := ' ';
    PDirectory(buffer)[1].fileName[7] := ' ';
    PDirectory(buffer)[1].attributes := $10;
    PDirectory(buffer)[1].clusterLow := uint16(rootCluster);
    driver.storage.mgr.storage_write(disk, clusterToLBA(dataStart, spc, rootCluster), 1, buffer);
    io.syslog.logln('FAT32', 'create_volume (sync): root dir written');

    kfree(buffer);

    { Create the SYSTEM directory via the normal FAT32 path }
    status := 0;
    FAT32CreateDirectory(volume, '', 'SYSTEM', $10, @status);
    io.syslog.logln('FAT32', 'create_volume (sync): done');
end;

procedure create_volume_async(volume : PStorage_Volume; sectors : uint32; start : uint32;
    config : PFSFormatParams; callback : TIOCallback; callbackData : pointer);
var
    ctx : PFmtContext;
    spc : uint32;
begin
    push_trace('driver.storage.fs.fat32.create_volume_async');
    io.syslog.logln('FAT32', 'create_volume_async: enter');

    ctx := PFmtContext(kalloc(sizeof(TFmtContext)));
    if ctx = nil then begin
        io.syslog.logln('FAT32', 'create_volume_async: OOM allocating context');
        if callback <> nil then callback(eOutOfMemory, callbackData);
        exit;
    end;
    memset(uint32(ctx), 0, sizeof(TFmtContext));

    ctx^.Volume       := volume;
    ctx^.Disk         := volume^.device;
    ctx^.SectorStart  := start;
    ctx^.RootCluster  := 2;
    ctx^.Callback     := callback;
    ctx^.CallbackData := callbackData;

    spc := fatFormatConfigSPC(config, sectors, ctx^.Disk^.sectorSize);
    ctx^.SPC      := spc;
    ctx^.FATSize  := fatComputeFATSize(sectors, spc, ctx^.Disk^.sectorSize);
    ctx^.FATStart := start + 32;
    ctx^.DataStart := ctx^.FATStart + ctx^.FATSize;

    ctx^.Buffer := puint32(kalloc(ctx^.Disk^.sectorSize + 512));
    if ctx^.Buffer = nil then begin
        if callback <> nil then callback(eOutOfMemory, callbackData);
        kfree(puint32(ctx));
        exit;
    end;
    memset(uint32(ctx^.Buffer), 0, ctx^.Disk^.sectorSize);

    { Write boot sector fields }
    PBootRecord(ctx^.Buffer)^.jmp2boot       := $0;
    PBootRecord(ctx^.Buffer)^.OEMName[0]     := 'A';
    PBootRecord(ctx^.Buffer)^.OEMName[1]     := 'S';
    PBootRecord(ctx^.Buffer)^.OEMName[2]     := 'U';
    PBootRecord(ctx^.Buffer)^.OEMName[3]     := 'R';
    PBootRecord(ctx^.Buffer)^.OEMName[4]     := 'O';
    PBootRecord(ctx^.Buffer)^.OEMName[5]     := ' ';
    PBootRecord(ctx^.Buffer)^.OEMName[6]     := 'V';
    PBootRecord(ctx^.Buffer)^.OEMName[7]     := '1';
    PBootRecord(ctx^.Buffer)^.sectorSize     := ctx^.Disk^.sectorSize;
    PBootRecord(ctx^.Buffer)^.spc            := uint8(spc);
    PBootRecord(ctx^.Buffer)^.rsvSectors     := 32;
    PBootRecord(ctx^.Buffer)^.numFats        := 1;
    PBootRecord(ctx^.Buffer)^.mediaDescp     := $F8;
    PBootRecord(ctx^.Buffer)^.hiddenSectors  := start;
    PBootRecord(ctx^.Buffer)^.manySectors    := sectors;
    PBootRecord(ctx^.Buffer)^.FATSize        := ctx^.FATSize;
    PBootRecord(ctx^.Buffer)^.rootCluster    := ctx^.RootCluster;
    PBootRecord(ctx^.Buffer)^.FSInfoCluster  := 0;
    PBootRecord(ctx^.Buffer)^.driveNumber    := $80;
    PBootRecord(ctx^.Buffer)^.volumeID       := 62;
    PBootRecord(ctx^.Buffer)^.bsignature     := $29;
    PBootRecord(ctx^.Buffer)^.identString[0] := 'F';
    PBootRecord(ctx^.Buffer)^.identString[1] := 'A';
    PBootRecord(ctx^.Buffer)^.identString[2] := 'T';
    PBootRecord(ctx^.Buffer)^.identString[3] := '3';
    PBootRecord(ctx^.Buffer)^.identString[4] := '2';
    PBootRecord(ctx^.Buffer)^.identString[5] := ' ';
    PBootRecord(ctx^.Buffer)^.identString[6] := ' ';
    PBootRecord(ctx^.Buffer)^.identString[7] := ' ';
    puint8(uint32(ctx^.Buffer) + 510)^ := $55;
    puint8(uint32(ctx^.Buffer) + 511)^ := $AA;

    if ctx^.FATSize > 128 then
        ctx^.BatchSize := 128
    else
        ctx^.BatchSize := ctx^.FATSize;
    ctx^.BatchPos := 0;

    ctx^.ZeroBuffer := puint32(kalloc(ctx^.Disk^.sectorSize * ctx^.BatchSize));
    if ctx^.ZeroBuffer = nil then begin
        kfree(ctx^.Buffer);
        if callback <> nil then callback(eOutOfMemory, callbackData);
        kfree(puint32(ctx));
        exit;
    end;
    memset(uint32(ctx^.ZeroBuffer), 0, ctx^.Disk^.sectorSize * ctx^.BatchSize);

    io.syslog.logln('FAT32', 'create_volume_async: kicking off fmtBootSector');
    ctx^.Step := fmtBootSector;
    fmt_run_next(ctx);
end;

end.
