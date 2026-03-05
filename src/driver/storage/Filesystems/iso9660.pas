{
    Driver->Storage->ISO9660 - Read-only ISO 9660 (CDFS) filesystem driver.

    Supports reading files and directories from ISO 9660 formatted media
    (CD-ROMs, DVD-ROMs, boot ISOs). No Joliet/Rock Ridge extensions yet —
    filenames are plain ISO 9660 (8.3 uppercase with version suffix).

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit iso9660;

interface

uses
    syslog,
    filesystemmanager,
    lists,
    lmemorymanager,
    storagemanager,
    storagetypes,
    strings,
    tracer,
    util,
    volumemanager;

type
    { ISO 9660 Primary Volume Descriptor (subset of fields we care about) }
    TPVD = packed record
        vdType          : uint8;         { 1 = Primary }
        stdIdent        : array[0..4] of char; { 'CD001' }
        vdVersion       : uint8;
        unused1         : uint8;
        systemId        : array[0..31] of char;
        volumeId        : array[0..31] of char;
        unused2         : array[0..7] of uint8;
        volumeSpaceSizeLSB : uint32;     { total sectors (LE) }
        volumeSpaceSizeMSB : uint32;     { total sectors (BE) }
        unused3         : array[0..31] of uint8;
        volumeSetSize   : array[0..3] of uint8;
        volumeSeqNum    : array[0..3] of uint8;
        logicalBlockSizeLSB : uint16;    { sector size (LE) }
        logicalBlockSizeMSB : uint16;
        pathTableSizeLSB : uint32;
        pathTableSizeMSB : uint32;
        pathTableLocLSB  : uint32;
        optPathTableLSB  : uint32;
        pathTableLocMSB  : uint32;
        optPathTableMSB  : uint32;
        rootDirRecord   : array[0..33] of uint8; { root directory record }
    end;
    PPVD = ^TPVD;

    { ISO 9660 Directory Record (variable-length on disk, this is the fixed part) }
    TDirRecord = packed record
        recLen          : uint8;
        extAttrLen      : uint8;
        extentLBA_LSB   : uint32;
        extentLBA_MSB   : uint32;
        dataLen_LSB     : uint32;
        dataLen_MSB     : uint32;
        recDate         : array[0..6] of uint8;
        fileFlags       : uint8;
        fileUnitSize    : uint8;
        interleaveGap   : uint8;
        volSeqNum_LSB   : uint16;
        volSeqNum_MSB   : uint16;
        fileIdLen       : uint8;
        { fileId follows immediately — variable length }
    end;
    PDirRecord = ^TDirRecord;

var
    filesystem : TFilesystem;

procedure init();

implementation

const
    PVD_SECTOR = 16;  { Primary Volume Descriptor is always at sector 16 }

{ ==================== Helpers ==================== }

{ Read 'count' device sectors starting at 'lba' from the volume's device.
  Caller must free the returned buffer. }
function readSectors(device : PStorage_Device; lba : uint32; count : uint32) : puint32;
var
    buf : puint32;
begin
    buf := puint32(kalloc(count * device^.sectorSize));
    memset(uint32(buf), 0, count * device^.sectorSize);
    storagemanager.storage_read(device, lba, count, buf);
    readSectors := buf;
end;

{ Check whether raw bytes at offset 1..5 of a PVD equal 'CD001' }
function isPVD(buf : puint32) : boolean;
var
    pvd : PPVD;
begin
    pvd := PPVD(buf);
    isPVD := (pvd^.vdType = 1)
         and (pvd^.stdIdent[0] = 'C')
         and (pvd^.stdIdent[1] = 'D')
         and (pvd^.stdIdent[2] = '0')
         and (pvd^.stdIdent[3] = '0')
         and (pvd^.stdIdent[4] = '1');
end;

{ Extract root directory extent LBA from the 34-byte root dir record in the PVD }
function rootLBA(pvd : PPVD) : uint32;
var
    rec : PDirRecord;
begin
    rec := PDirRecord(@pvd^.rootDirRecord[0]);
    rootLBA := rec^.extentLBA_LSB;
end;

{ Extract root directory data length from the PVD root dir record }
function rootLen(pvd : PPVD) : uint32;
var
    rec : PDirRecord;
begin
    rec := PDirRecord(@pvd^.rootDirRecord[0]);
    rootLen := rec^.dataLen_LSB;
end;

{ Strip the ISO 9660 version suffix (;1) and trailing dots from a filename.
  Also converts to uppercase for comparison. Returns a new allocated string that
  the caller must free. }
function cleanISOName(raw : pchar; len : uint8) : pchar;
var
    s    : pchar;
    i    : uint32;
    semi : sint32;
begin
    s := stringNew(len + 1);
    memcpy(uint32(raw), uint32(s), len);
    puint8(uint32(s) + len)^ := 0;

    { Find and truncate at semicolon (version separator) }
    semi := -1;
    for i := 0 to len - 1 do begin
        if puint8(uint32(s) + i)^ = ord(';') then begin
            semi := i;
            break;
        end;
    end;
    if semi >= 0 then
        puint8(uint32(s) + uint32(semi))^ := 0;

    { Strip trailing dot (ISO 9660 directories sometimes have it) }
    i := stringSize(s);
    if (i > 0) and (puint8(uint32(s) + i - 1)^ = ord('.')) then
        puint8(uint32(s) + i - 1)^ := 0;

    cleanISOName := s;
end;

{ Case-insensitive comparison }
function equalsIgnoreCase(a : pchar; b : pchar) : boolean;
var
    i    : uint32;
    la, lb : uint32;
    ca, cb : uint8;
begin
    la := stringSize(a);
    lb := stringSize(b);
    if la <> lb then begin
        equalsIgnoreCase := false;
        exit;
    end;
    for i := 0 to la - 1 do begin
        ca := puint8(uint32(a) + i)^;
        cb := puint8(uint32(b) + i)^;
        { Convert lowercase to uppercase }
        if (ca >= ord('a')) and (ca <= ord('z')) then ca := ca - 32;
        if (cb >= ord('a')) and (cb <= ord('z')) then cb := cb - 32;
        if ca <> cb then begin
            equalsIgnoreCase := false;
            exit;
        end;
    end;
    equalsIgnoreCase := true;
end;

{ Read the full extent of a directory (may span multiple sectors). 
  Returns a buffer with dataLen bytes. Caller must free. }
function readExtent(device : PStorage_Device; lba : uint32; dataLen : uint32) : puint32;
var
    sectorCount : uint32;
begin
    sectorCount := (dataLen + device^.sectorSize - 1) div device^.sectorSize;
    readExtent := readSectors(device, lba, sectorCount);
end;

{ Walk a directory extent buffer looking for a named entry.
  Sets outLBA and outLen to the found entry's extent LBA and data length.
  Returns true if found, false otherwise. isDir is set if the entry is a directory. }
function findEntry(dirBuf : puint32; dirLen : uint32; name : pchar;
                   pOutLBA : puint32; pOutLen : puint32; pIsDir : puint32) : boolean;
var
    offset : uint32;
    rec    : PDirRecord;
    entryName : pchar;
begin
    findEntry := false;
    offset := 0;

    while offset < dirLen do begin
        rec := PDirRecord(uint32(dirBuf) + offset);

        { A zero record length means we've hit padding — skip to next sector boundary }
        if rec^.recLen = 0 then begin
            offset := ((offset div 2048) + 1) * 2048;
            continue;
        end;

        { Skip '.' and '..' entries (fileIdLen = 1, fileId = 0 or 1) }
        if (rec^.fileIdLen = 1) then begin
            offset := offset + rec^.recLen;
            continue;
        end;

        entryName := cleanISOName(pchar(uint32(rec) + 33), rec^.fileIdLen);

        if equalsIgnoreCase(entryName, name) then begin
            pOutLBA^ := rec^.extentLBA_LSB;
            pOutLen^ := rec^.dataLen_LSB;
            if (rec^.fileFlags and $02) <> 0 then
                pIsDir^ := 1
            else
                pIsDir^ := 0;
            kfree(void(entryName));
            findEntry := true;
            exit;
        end;

        kfree(void(entryName));
        offset := offset + rec^.recLen;
    end;
end;

{ Resolve a full path (e.g. '/BOOT/DATA') starting from the root directory.
  Returns the extent LBA and length of the final path component.
  path should use '/' separators. }
function resolvePath(device : PStorage_Device; pvd : PPVD; path : pchar;
                     pOutLBA : puint32; pOutLen : puint32; pIsDir : puint32) : boolean;
var
    curLBA, curLen : uint32;
    dirBuf : puint32;
    i, start, pathLen : uint32;
    component : pchar;
    compLen   : uint32;
    foundLBA, foundLen : uint32;
    foundDir  : uint32;
begin
    resolvePath := false;

    curLBA := rootLBA(pvd);
    curLen := rootLen(pvd);

    pathLen := stringSize(path);
    if pathLen = 0 then begin
        pOutLBA^ := curLBA;
        pOutLen^ := curLen;
        pIsDir^  := 1;
        resolvePath := true;
        exit;
    end;

    { Skip leading slash }
    i := 0;
    if puint8(uint32(path))^ = ord('/') then i := 1;

    foundDir := 1;
    while i <= pathLen do begin
        { Find next slash or end of path }
        start := i;
        while (i < pathLen) and (puint8(uint32(path) + i)^ <> ord('/')) do
            i := i + 1;
        compLen := i - start;
        if compLen = 0 then begin
            i := i + 1;
            continue;
        end;

        { Extract component }
        component := stringNew(compLen + 1);
        memcpy(uint32(path) + start, uint32(component), compLen);
        puint8(uint32(component) + compLen)^ := 0;

        { Read current directory extent }
        dirBuf := readExtent(device, curLBA, curLen);

        if not findEntry(dirBuf, curLen, component, @foundLBA, @foundLen, @foundDir) then begin
            kfree(void(component));
            kfree(dirBuf);
            exit;
        end;

        kfree(void(component));
        kfree(dirBuf);

        curLBA := foundLBA;
        curLen := foundLen;

        { Skip the slash }
        i := i + 1;
    end;

    pOutLBA^ := curLBA;
    pOutLen^ := curLen;
    pIsDir^  := foundDir;
    resolvePath := true;
end;

{ ==================== Filesystem callbacks ==================== }

{ Identify: check for 'CD001' at sector 16 }
function identify_volume(volume : PStorage_Volume) : boolean;
var
    buf : puint32;
    pvd : PPVD;
begin
    identify_volume := false;
    if volume^.device = nil then exit;
    if (volume^.device^.readCallback = nil) and (volume^.device^.readCallbackAsync = nil) then exit;

    buf := readSectors(volume^.device, volume^.sectorStart + PVD_SECTOR, 1);
    identify_volume := isPVD(buf);
    kfree(buf);
end;

{ Detect: create a whole-device volume for ATAPI/CD-ROM devices }
procedure detect_volumes(disk : PStorage_Device);
var
    buf    : puint32;
    pvd    : PPVD;
    volume : PStorage_Volume;
begin
    if disk = nil then exit;
    if (disk^.readCallback = nil) and (disk^.readCallbackAsync = nil) then exit;

    buf := readSectors(disk, PVD_SECTOR, 1);
    if not isPVD(buf) then begin
        kfree(buf);
        exit;
    end;

    pvd := PPVD(buf);

    volume := PStorage_Volume(kalloc(sizeof(TStorage_Volume)));
    memset(uint32(volume), 0, sizeof(TStorage_Volume));
    volume^.device      := disk;
    volume^.sectorStart := 0;
    volume^.sectorSize  := disk^.sectorSize;
    volume^.sectorCount := pvd^.volumeSpaceSizeLSB;
    volume^.freeSectors := 0;
    volume^.filesystem  := @filesystem;
    volume^.isBootDrive := false;

    volumemanager.register_volume(disk, volume);

    kfree(buf);
end;

{ ReadDir: list entries in a directory }
function readDirectoryEntries(volume : PStorage_Volume; directory : pchar; status : puint32) : PLinkedListBase;
var
    buf    : puint32;
    pvd    : PPVD;
    dirLBA, dirLen : uint32;
    isDirFlag : uint32;
    offset : uint32;
    rec    : PDirRecord;
    entries : PLinkedListBase;
    elm     : void;
    dirEntry : PDirectory_Entry;
    entryName : pchar;
begin
    status^ := ord(eNone);
    entries := LL_New(sizeof(TDirectory_Entry));

    if volume^.device = nil then begin
        status^ := ord(eUnknown);
        readDirectoryEntries := entries;
        exit;
    end;

    { Read PVD }
    buf := readSectors(volume^.device, volume^.sectorStart + PVD_SECTOR, 1);
    if not isPVD(buf) then begin
        status^ := ord(eUnknown);
        kfree(buf);
        readDirectoryEntries := entries;
        exit;
    end;
    pvd := PPVD(buf);

    { Resolve the requested directory path }
    if (directory = nil) or (stringSize(directory) = 0) or
       ((stringSize(directory) = 1) and (puint8(directory)^ = ord('/'))) then begin
        { Root directory }
        dirLBA := rootLBA(pvd);
        dirLen := rootLen(pvd);
    end else begin
        if not resolvePath(volume^.device, pvd, directory, @dirLBA, @dirLen, @isDirFlag) then begin
            status^ := ord(eDirectoryDoesNotExist);
            kfree(buf);
            readDirectoryEntries := entries;
            exit;
        end;
        if isDirFlag = 0 then begin
            status^ := ord(eNotADirectory);
            kfree(buf);
            readDirectoryEntries := entries;
            exit;
        end;
    end;

    kfree(buf);

    { Read the directory extent }
    buf := readExtent(volume^.device, dirLBA, dirLen);

    offset := 0;
    while offset < dirLen do begin
        rec := PDirRecord(uint32(buf) + offset);

        if rec^.recLen = 0 then begin
            offset := ((offset div 2048) + 1) * 2048;
            continue;
        end;

        { Skip '.' (0x00) and '..' (0x01) }
        if (rec^.fileIdLen = 1) and
           ((puint8(uint32(rec) + 33)^ = 0) or (puint8(uint32(rec) + 33)^ = 1)) then begin
            offset := offset + rec^.recLen;
            continue;
        end;

        entryName := cleanISOName(pchar(uint32(rec) + 33), rec^.fileIdLen);

        elm := LL_Add(entries);
        dirEntry := PDirectory_Entry(elm);
        dirEntry^.fileName := entryName;
        if (rec^.fileFlags and $02) <> 0 then
            dirEntry^.entryType := TDirectory_Entry_Type.directoryEntry
        else
            dirEntry^.entryType := TDirectory_Entry_Type.fileEntry;

        offset := offset + rec^.recLen;
    end;

    kfree(buf);
    readDirectoryEntries := entries;
end;

{ ReadFile: read file contents into buffer.
  directory = parent directory path (e.g. '/' or '/BOOT')
  fileName = file name (e.g. 'README.TXT')
  buffer = destination buffer (caller allocates)
  bytecount = pointer to uint32 receiving bytes read
  Returns 0 on success, 1 on file not found. }
function readFile(volume : PStorage_Volume; directory : pchar; fileName : pchar;
                  buffer : puint32; bytecount : puint32) : uint32;
var
    buf     : puint32;
    pvd     : PPVD;
    dirLBA, dirLen : uint32;
    fileLBA, fileLen : uint32;
    isDirFlag : uint32;
    dirBuf  : puint32;
    fileBuf : puint32;
    fullPath : pchar;
    dirSize, nameSize : uint32;
begin
    readFile := 1;

    if volume^.device = nil then exit;

    { Read PVD }
    buf := readSectors(volume^.device, volume^.sectorStart + PVD_SECTOR, 1);
    if not isPVD(buf) then begin
        kfree(buf);
        exit;
    end;
    pvd := PPVD(buf);

    { Resolve the parent directory }
    if (directory = nil) or (stringSize(directory) = 0) or
       ((stringSize(directory) = 1) and (puint8(directory)^ = ord('/'))) then begin
        dirLBA := rootLBA(pvd);
        dirLen := rootLen(pvd);
    end else begin
        if not resolvePath(volume^.device, pvd, directory, @dirLBA, @dirLen, @isDirFlag) then begin
            kfree(buf);
            exit;
        end;
    end;

    kfree(buf);

    { Read the directory and find the file }
    dirBuf := readExtent(volume^.device, dirLBA, dirLen);

    if not findEntry(dirBuf, dirLen, fileName, @fileLBA, @fileLen, @isDirFlag) then begin
        kfree(dirBuf);
        exit;
    end;
    kfree(dirBuf);

    if isDirFlag <> 0 then exit;

    { Read the file data — store pointer in buffer^ for the VFS to own }
    fileBuf := readExtent(volume^.device, fileLBA, fileLen);
    buffer^ := uint32(fileBuf);
    bytecount^ := fileLen;

    readFile := 0;
end;

{ ==================== Init ==================== }

procedure init();
begin
    push_trace('iso9660.init()');
    filesystem.sName           := 'ISO9660';
    filesystem.system_id       := $05;
    filesystem.readDirCallback := @readDirectoryEntries;
    filesystem.readCallback    := @readFile;
    filesystem.detectCallback  := @detect_volumes;
    filesystem.identifyCallback := @identify_volume;
    filesystem.writeCallback   := nil;
    filesystem.createCallback  := nil;
    filesystem.createDirCallback := nil;
    filesystem.deleteFileCallback := nil;
    filesystem.deleteDirCallback := nil;

    filesystemmanager.register_filesystem(@filesystem);
end;

end.
