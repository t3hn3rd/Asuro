unit driver.storage.fs.fat32.labels;

interface
uses driver.storage.types;
function normalize_label(text : pchar; var normalized : TVolumeLabel) : TError;
function read_label(volume : PStorage_Volume) : TError;
{ Caller owns the device metadata lock and has invalidated filesystem caches. }
function write_label(volume : PStorage_Volume; text : pchar) : TError;

implementation
uses driver.storage.fs.fat32.types, driver.storage.mgr, memory.heap, core.util;

function normalize_label(text : pchar; var normalized : TVolumeLabel) : TError;
var i, n, first : uint32; c : char;
begin
    normalize_label := eInvalidArgument;
    memset(uint32(@normalized[0]), 0, sizeof(normalized));
    if text = nil then exit;
    n := 0;
    while (n < 12) and (text[n] <> #0) do Inc(n);
    if n > 11 then exit;
    while (n > 0) and (text[n-1] = ' ') do Dec(n);
    first := 0; while (first < n) and (text[first] = ' ') do Inc(first);
    i := first;
    while i < n do begin
        c := text[i];
        if (ord(c) < 32) or (ord(c) > 126) then exit;
        case c of
            '"','*','+',',','.','/',':',';','<','=','>','?','[',']','\','|': exit;
        end;
        if (c >= 'a') and (c <= 'z') then c := char(ord(c)-32);
        normalized[i-first] := c; Inc(i);
    end;
    normalize_label := eNone;
end;

procedure unpack_label(src : pchar; var dest : TVolumeLabel);
var n, i : uint32;
begin
    memset(uint32(@dest[0]), 0, sizeof(dest));
    n := 11; while (n > 0) and ((src[n-1] = ' ') or (src[n-1] = #0)) do Dec(n);
    for i := 0 to 10 do if i < n then dest[i] := src[i];
end;

procedure pack_label(src : pchar; dest : pchar);
var i : uint32;
begin
    for i := 0 to 10 do dest[i] := ' ';
    i := 0; while (i < 11) and (src[i] <> #0) do begin dest[i] := src[i]; Inc(i); end;
end;

function load_boot(volume : PStorage_Volume; buffer : puint32) : TError;
var br : PBootRecord; lim : uint32;
begin
    load_boot := eInvalidArgument;
    if (volume = nil) or (volume^.device = nil) then exit;
    if (volume^.device^.sectorSize <> 512) or (volume^.sectorCount = 0) or
       (volume^.sectorStart >= volume^.device^.maxSectorCount) or
       (volume^.sectorCount > volume^.device^.maxSectorCount-volume^.sectorStart) then exit;
    load_boot := storage_read(volume^.device,volume^.sectorStart,1,buffer);
    if load_boot <> eNone then exit;
    br := PBootRecord(buffer); lim := FAT32ClusterLimit(br);
    if (lim <= 2) or (br^.manySectors = 0) or (br^.manySectors > volume^.sectorCount) or
       (br^.rootCluster < 2) or (br^.rootCluster >= lim) or
       (puint16(uint32(buffer)+510)^ <> $AA55) then load_boot := eCorruptFilesystem;
end;

{ Bounded walk of the root FAT chain. A label is authoritative when present.
  Also remembers the first reusable slot; never scans beyond the end marker. }
function locate_label(volume : PStorage_Volume; br : PBootRecord; scratch : puint32;
                      var sector, offset : uint32; var found : boolean) : TError;
var cluster, next, limit, steps, ds, i, lba, dataStart, fatStart : uint32;
    freeSector, freeOffset : uint32; entry : PDirectory;
begin
    locate_label := eNone; sector := 0; offset := 0; found := false;
    freeSector := 0; freeOffset := 0; limit := FAT32ClusterLimit(br);
    dataStart := volume^.sectorStart + br^.rsvSectors + br^.numFats*br^.FATSize;
    fatStart := volume^.sectorStart + br^.rsvSectors;
    if (br^.flags and $80) <> 0 then begin
        i := br^.flags and $0F;
        if i >= br^.numFats then begin locate_label := eCorruptFilesystem; exit; end;
        fatStart := fatStart+i*br^.FATSize;
    end;
    cluster := br^.rootCluster; steps := 0;
    while steps < limit-2 do begin
        if (cluster < 2) or (cluster >= limit) then begin locate_label := eCorruptFilesystem; exit; end;
        lba := dataStart+(cluster-2)*br^.spc;
        for ds := 0 to br^.spc-1 do begin
            locate_label := storage_read(volume^.device,lba+ds,1,scratch);
            if locate_label <> eNone then exit;
            for i := 0 to 15 do begin
                entry := @PDirectory(scratch)[i];
                if (entry^.fileName[0] = #0) or (entry^.fileName[0] = char($E5)) then begin
                    if freeSector = 0 then begin freeSector := lba+ds; freeOffset := i*32; end;
                    if entry^.fileName[0] = #0 then begin sector := freeSector; offset := freeOffset; exit; end;
                end else if (entry^.attributes and $3F) = $08 then begin
                    sector := lba+ds; offset := i*32; found := true; exit;
                end;
            end;
        end;
        locate_label := storage_read(volume^.device,fatStart+cluster div 128,1,scratch);
        if locate_label <> eNone then exit;
        next := scratch[cluster mod 128] and $0FFFFFFF;
        if next >= $0FFFFFF8 then begin sector := freeSector; offset := freeOffset; exit; end;
        cluster := next; Inc(steps);
    end;
    locate_label := eCorruptFilesystem;
end;

function read_label(volume : PStorage_Volume) : TError;
var mem, boot, scratch : puint32; sector, offset, i : uint32; found, noName : boolean;
    value : TVolumeLabel;
begin
    mem := puint32(kalloc(1024));
    if mem = nil then begin read_label := eOutOfMemory; exit; end;
    boot := mem; scratch := puint32(uint32(mem)+512);
    read_label := load_boot(volume,boot);
    if read_label = eNone then begin
        read_label := locate_label(volume,PBootRecord(boot),scratch,sector,offset,found);
        if read_label = eNone then begin
            if found then unpack_label(pchar(uint32(scratch)+offset),value)
            else begin
                unpack_label(pchar(@PBootRecord(boot)^.volumeLabel[0]),value);
                noName := true;
                for i := 0 to 10 do
                    if pchar(@PBootRecord(boot)^.volumeLabel[0])[i] <> pchar('NO NAME    ')[i] then noName := false;
                if noName then value[0] := #0;
            end;
            volume^.labelText := value;
        end;
    end;
    kfree(mem);
end;

function write_label(volume : PStorage_Volume; text : pchar) : TError;
var mem, boot, scratch, rootOld, backupOld, bootOld : puint32;
    br : PBootRecord; value : TVolumeLabel; sector, offset, backup : uint32;
    found, bootWritten, backupWritten, rootWritten : boolean; entry : PDirectory;
begin
    write_label := normalize_label(text,value); if write_label <> eNone then exit;
    if (volume = nil) or (volume^.device = nil) then begin write_label := eInvalidArgument; exit; end;
    if not volume^.device^.writable then begin write_label := eReadOnly; exit; end;
    mem := puint32(kalloc(5*512));
    if mem = nil then begin write_label := eOutOfMemory; exit; end;
    boot := mem; scratch := puint32(uint32(mem)+512); rootOld := puint32(uint32(mem)+1024);
    backupOld := puint32(uint32(mem)+1536); bootOld := puint32(uint32(mem)+2048);
    bootWritten := false; backupWritten := false; rootWritten := false; backup := 0;
    repeat
        write_label := load_boot(volume,boot); if write_label <> eNone then break;
        br := PBootRecord(boot);
        write_label := locate_label(volume,br,scratch,sector,offset,found);
        if write_label <> eNone then break;
        if (sector = 0) and (value[0] <> #0) then begin write_label := eDiskFull; break; end;
        if sector <> 0 then begin
            write_label := storage_read(volume^.device,sector,1,scratch); if write_label <> eNone then break;
            memcpy(uint32(scratch),uint32(rootOld),512);
            entry := PDirectory(uint32(scratch)+offset);
            if value[0] = #0 then begin
                if found then entry^.fileName[0] := char($E5);
            end else begin
                if entry^.fileName[0] = #0 then begin
                    { Retain an end marker after a newly inserted label. }
                    if offset = 480 then begin write_label := eDiskFull; break; end;
                    puint8(uint32(entry)+32)^ := 0;
                end;
                memset(uint32(entry),0,32); pack_label(@value[0],@entry^.fileName[0]); entry^.attributes := $08;
            end;
        end;
        if (br^.backupCluster <> 0) and (br^.backupCluster <> $FFFF) then begin
            if br^.backupCluster >= br^.rsvSectors then begin write_label := eCorruptFilesystem; break; end;
            backup := volume^.sectorStart+br^.backupCluster;
            write_label := storage_read(volume^.device,backup,1,backupOld); if write_label <> eNone then break;
        end;
        memcpy(uint32(boot),uint32(bootOld),512);
        if value[0] = #0 then pack_label('NO NAME',pchar(@br^.volumeLabel[0]))
        else pack_label(@value[0],pchar(@br^.volumeLabel[0]));
        bootWritten := true;
        write_label := storage_write(volume^.device,volume^.sectorStart,1,boot);
        if write_label <> eNone then break;
        bootWritten := true;
        if backup <> 0 then begin
            { Preserve backup-specific bytes; only update its label. }
            memcpy(uint32(backupOld),uint32(boot),512);
            if value[0] = #0 then pack_label('NO NAME',pchar(@br^.volumeLabel[0]))
            else pack_label(@value[0],pchar(@br^.volumeLabel[0]));
            backupWritten := true;
            write_label := storage_write(volume^.device,backup,1,boot);
            if write_label <> eNone then break;
            backupWritten := true;
        end;
        if (sector <> 0) and (found or (value[0] <> #0)) then begin
            rootWritten := true;
            write_label := storage_write(volume^.device,sector,1,scratch);
        end;
    until true;
    if write_label = eNone then volume^.labelText := value
    else begin
        { Best-effort rollback on I/O failure; preserve the original error. }
        if rootWritten then storage_write(volume^.device,sector,1,rootOld);
        if backupWritten then storage_write(volume^.device,backup,1,backupOld);
        if bootWritten then storage_write(volume^.device,volume^.sectorStart,1,bootOld);
    end;
    kfree(mem);
end;
end.
