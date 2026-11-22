unit driver.storage.fs.fat32.vol;

interface
uses driver.storage.types, driver.storage.fs.fat32.types;
procedure FAT32VolInit(fs : PFilesystem);
procedure detect_volumes(disk : PStorage_Device);
function identify_volume(volume : PStorage_Volume) : boolean;
function validate_format(volume : PStorage_Volume; sectors, start : uint32; config : PFSFormatParams) : TError;
function create_volume(volume : PStorage_Volume; sectors, start : uint32; config : PFSFormatParams) : TError;

implementation
uses io.syslog, debug.tracer, memory.heap, core.util, arch.x86.util,
     driver.storage.mgr, driver.storage.vol.mgr, driver.storage.fs.fat32.labels;
var fat32FilesystemPtr : PFilesystem = nil;

procedure FAT32VolInit(fs : PFilesystem);
begin fat32FilesystemPtr := fs; end;

function bootSectorHasSignature(buffer : puint32) : boolean;
begin
    bootSectorHasSignature := (puint8(uint32(buffer)+510)^ = $55) and
                              (puint8(uint32(buffer)+511)^ = $AA);
end;

function formatSPC(config : PFSFormatParams) : uint32;
begin
    formatSPC := 8;
    if (config <> nil) and ((config^.Flags and FS_FORMAT_PARAM_CLUSTER_SIZE) <> 0) then
        formatSPC := config^.ClusterSize;
end;

function formatFATSize(sectors, spc : uint32) : uint32;
begin
    { Conservative size includes reserved FAT entries; uint64 prevents wrap. }
    formatFATSize := uint32(((uint64(sectors - 32) div spc + 2) * 4 + 511) div 512);
end;

function validate_format(volume : PStorage_Volume; sectors, start : uint32; config : PFSFormatParams) : TError;
var spc, fat : uint32; dataClusters : uint64; labelValue : TVolumeLabel;
begin
    validate_format := eInvalidArgument;
    if (volume = nil) or (volume^.device = nil) then exit;
    if not volume^.device^.writable then begin validate_format := eReadOnly; exit; end;
    { Current FAT cache addresses 512-byte sectors. Reject unsupported geometry. }
    if volume^.device^.sectorSize <> 512 then exit;
    if (sectors <> volume^.sectorCount) or (start <> volume^.sectorStart) or
       (start >= volume^.device^.maxSectorCount) or
       (sectors > volume^.device^.maxSectorCount - start) or (sectors <= 32) then exit;
    if config <> nil then begin
        if (config^.Version <> FS_FORMAT_PARAMS_VERSION_1) or
           ((config^.Flags and (not (FS_FORMAT_PARAM_CLUSTER_SIZE or FS_FORMAT_PARAM_LABEL))) <> 0) then exit;
    end;
    if (config <> nil) and ((config^.Flags and FS_FORMAT_PARAM_LABEL) <> 0) then
        if normalize_label(@config^.LabelText[0],labelValue) <> eNone then exit;
    spc := formatSPC(config);
    if (spc = 0) or (spc > 128) or ((spc and (spc-1)) <> 0) then exit;
    fat := formatFATSize(sectors, spc);
    if uint64(32) + fat + uint64(spc)*2 > sectors then exit;
    dataClusters := (uint64(sectors) - 32 - fat) div spc;
    if dataClusters + 2 > $0FFFFFF0 then exit;
    validate_format := eNone;
end;

function countFreeFATClusters(volume : PStorage_Volume; br : PBootRecord) : uint32;
var limit, sectorIdx, entryIdx, clusterNum, count, sectors, batch : uint32; buffer : puint32;
begin
    countFreeFATClusters := $FFFFFFFF;
    limit := FAT32ClusterLimit(br);
    if limit <= 2 then exit;
    volume^.lifecycleFlags := volume^.lifecycleFlags and (not STORAGE_VOLUME_FLAG_FREE_UNKNOWN);
    { Match the USB storage transfer buffer: eight sectors per command instead
      of a CBW/data/CSW round trip for every 512 bytes of a large FAT. }
    buffer := puint32(kalloc(4096));
    if buffer = nil then exit;
    { FSInfo is optional, and its count is advisory. Validate every signature,
      the reserved-sector location, and the count before displaying it. }
    if (br^.FSInfoCluster > 0) and (br^.FSInfoCluster < br^.rsvSectors) then begin
        if storage_read(volume^.device, volume^.sectorStart + br^.FSInfoCluster, 1, buffer) = eNone then
            if (buffer[0] = $41615252) and (buffer[121] = $61417272) and
               (buffer[127] = $AA550000) and (buffer[122] <= limit - 2) then begin
                countFreeFATClusters := buffer[122]; kfree(buffer); exit;
            end;
    end;
    count := 0; sectorIdx := 0;
    sectors := (limit + 127) div 128;
    { Mounting must not wait for an O(disk-size) allocation scan. Small FATs
      remain cheap to count; larger volumes without FSInfo mount with unknown
      free space. Allocation always consults the actual FAT, never this hint. }
    if sectors > 16 then begin
        volume^.lifecycleFlags := volume^.lifecycleFlags or STORAGE_VOLUME_FLAG_FREE_UNKNOWN;
        countFreeFATClusters := 0;
        kfree(buffer); exit;
    end;
    while sectorIdx < sectors do begin
        batch := sectors - sectorIdx;
        if batch > 8 then batch := 8;
        if storage_read(volume^.device, volume^.sectorStart + br^.rsvSectors + sectorIdx, batch, buffer) <> eNone then begin
            kfree(buffer); exit;
        end;
        for entryIdx := 0 to batch * 128 - 1 do begin
            clusterNum := sectorIdx * 128 + entryIdx;
            if clusterNum >= limit then break;
            if (clusterNum >= 2) and ((buffer[entryIdx] and $0FFFFFFF) = 0) then Inc(count);
        end;
        Inc(sectorIdx, batch);
    end;
    kfree(buffer);
    countFreeFATClusters := count;
end;

procedure detect_volumes(disk : PStorage_Device);
var
    buffer  : puint32;
    bufSize : uint32;
    volume  : PStorage_Volume;
    br      : PBootRecord;
    freeClusters : uint32;
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

    if storage_read(disk, 0, 1, buffer) <> eNone then begin kfree(buffer); exit; end;

    br := PBootRecord(buffer);
    if bootSectorHasSignature(buffer) and (br^.bsignature = $29) and
       (FAT32ClusterLimit(br) > 2) and (br^.manySectors <= disk^.maxSectorCount) then begin
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
        freeClusters := countFreeFATClusters(volume, br);
        if freeClusters = $FFFFFFFF then begin kfree(void(volume)); kfree(buffer); exit; end;
        volume^.freeSectors := freeClusters * br^.spc;
        volume^.isBootDrive := false;
        if read_label(volume) <> eNone then begin kfree(void(volume)); kfree(buffer); exit; end;
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
    freeClusters : uint32;
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

    if storage_read(volume^.device, volume^.sectorStart, 1, buffer) <> eNone then begin kfree(buffer); exit; end;
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
       (br^.rootCluster >= 2) and (br^.rootCluster < FAT32ClusterLimit(br)) and
       (br^.manySectors <= volume^.sectorCount) then begin
        io.syslog.logln('FAT32', 'identify_volume: FAT32 signature matched');
        freeClusters := countFreeFATClusters(volume, br);
        if freeClusters <> $FFFFFFFF then begin
            identify_volume := read_label(volume) = eNone;
            volume^.freeSectors := freeClusters * br^.spc;
        end;
    end else
        io.syslog.logln('FAT32', 'identify_volume: not a FAT32 volume');

    kfree(buffer);
end;

{ Every write is checked; a valid boot signature is published last. }
function create_volume(volume : PStorage_Volume; sectors, start : uint32; config : PFSFormatParams) : TError;
var
    boot, buffer : puint32;
    br : PBootRecord;
    dir : PDirectory;
    spc, fat, fatStart, dataStart, pos, batch, i : uint32;
    err : TError;
    labelValue : TVolumeLabel;
    function writeSectors(lba, count : uint32; data : puint32) : boolean;
    begin
        if (lba < start) or (lba - start >= sectors) or (count > sectors - (lba - start)) then
            err := eInvalidArgument
        else err := storage_write(volume^.device, lba, count, data);
        writeSectors := err = eNone;
    end;
begin
    create_volume := validate_format(volume, sectors, start, config);
    if create_volume <> eNone then exit;
    memset(uint32(@labelValue[0]),0,sizeof(labelValue));
    if (config <> nil) and ((config^.Flags and FS_FORMAT_PARAM_LABEL) <> 0) then
        normalize_label(@config^.LabelText[0],labelValue);
    spc := formatSPC(config); fat := formatFATSize(sectors, spc);
    fatStart := start + 32; dataStart := fatStart + fat;
    boot := puint32(kalloc(512)); buffer := puint32(kalloc(128*512));
    if (boot = nil) or (buffer = nil) then begin
        if boot <> nil then kfree(boot);
        if buffer <> nil then kfree(buffer);
        create_volume := eOutOfMemory; exit;
    end;
    memset(uint32(boot), 0, 512); memset(uint32(buffer), 0, 128*512);
    br := PBootRecord(boot);
    br^.sectorSize := 512; br^.spc := uint8(spc); br^.rsvSectors := 32;
    br^.numFats := 1; br^.mediaDescp := $F8; br^.hiddenSectors := start;
    br^.manySectors := sectors; br^.FATSize := fat; br^.rootCluster := 2;
    br^.driveNumber := $80; br^.volumeID := 62; br^.bsignature := $29;
    memcpy(uint32(pchar('ASURO   ')), uint32(@br^.OEMName[0]), 8);
    memcpy(uint32(pchar('FAT32   ')), uint32(@br^.identString[0]), 8);
    memcpy(uint32(pchar('NO NAME    ')), uint32(@br^.volumeLabel[0]), 11);
    if labelValue[0] <> #0 then begin
        memset(uint32(@br^.volumeLabel[0]),ord(' '),11);
        i := 0; while (i < 11) and (labelValue[i] <> #0) do begin br^.volumeLabel[i] := ord(labelValue[i]); Inc(i); end;
    end;
    puint8(uint32(boot)+510)^ := $55; puint8(uint32(boot)+511)^ := $AA;
    err := eNone;
    repeat
        { Invalidate the old boot signature before modifying allocation metadata. }
        if not writeSectors(start, 32, buffer) then break;
        pos := 0;
        while (pos < fat) and (err = eNone) do begin
            batch := fat-pos; if batch > 128 then batch := 128;
            writeSectors(fatStart+pos, batch, buffer); pos := pos+batch;
        end;
        if err <> eNone then break;
        buffer[0] := $0FFFFFF8; buffer[1] := $0FFFFFFF;
        buffer[2] := $0FFFFFFF; buffer[3] := $0FFFFFFF;
        if not writeSectors(fatStart, 1, buffer) then break;
        memset(uint32(buffer), 0, 128*512);
        dir := PDirectory(buffer);
        if labelValue[0] <> #0 then begin
            memcpy(uint32(@br^.volumeLabel[0]),uint32(@dir^.fileName[0]),11);
            dir^.attributes := $08; dir := @PDirectory(buffer)[1];
        end;
        memcpy(uint32(pchar('SYSTEM     ')), uint32(@dir^.fileName[0]), 11);
        dir^.attributes := $10; dir^.clusterLow := 3;
        if not writeSectors(dataStart, spc, buffer) then break;
        memset(uint32(buffer), 0, 128*512);
        dir := PDirectory(buffer);
        memcpy(uint32(pchar('.          ')), uint32(@dir[0].fileName[0]), 11);
        dir[0].attributes := $10; dir[0].clusterLow := 3;
        memcpy(uint32(pchar('..         ')), uint32(@dir[1].fileName[0]), 11);
        dir[1].attributes := $10; dir[1].clusterLow := 0; { parent is root }
        if not writeSectors(dataStart+spc, spc, buffer) then break;
        writeSectors(start, 1, boot);
    until true;
    kfree(buffer); kfree(boot);
    create_volume := err;
end;

end.
