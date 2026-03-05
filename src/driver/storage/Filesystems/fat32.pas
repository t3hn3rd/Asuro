{ 
	Driver->storage->fat32 - fat32 filesystem driver
	
	@author(Aaron Hance <ah@aaronhance.me>)
}

unit FAT32;

interface

uses
    filesystemmanager,
    lists,
    lmemorymanager,
    rtc,
    stdio,
    storagemanager,
    storagetypes,
    strings,
    syslog,
    tracer,
    util,
    volumemanager;

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
        FATSize       : uint32;
        flags         : uint16;
        signature     : uint8;
        FATVersion    : uint16;
        rootCluster   : uint32;
        FSInfoCluster : uint16;
        backupCluster : uint16;
        reserved0     : array[0..11] of uint8;
        driveNumber   : uint8;
        reserved1     : uint8;
        bsignature     : uint8;// = $28;
        volumeID      : uint32;
        volumeLabel   : array[0..10] of uint8;
        identString   : array[0..7] of char;// = 'FAT32 ';
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

    TFatVolumeInfo = record
        sectorsPerCluster : uint8; // must be power of 2 and mult by sectorsize to max 32k
    end;
    PFatVolumeInfo = ^TFatVolumeInfo;

var
    filesystem : TFilesystem;

procedure init;
procedure create_volume(volume : PStorage_Volume; sectors : uint32; start : uint32; config : puint32);
procedure detect_volumes(disk : PStorage_Device);
//function writeDirectory(volume : PStorage_volume; directory : pchar; attributes : uint32) : uint8; // need to handle parent table cluster overflow, need to take attributes
//function readDirectory(volume : PStorage_volume; directory : pchar; listPtr : PLinkedListBase) : uint8; //returns: 0 = success, 1 = dir not exsist, 2 = not directory, 3 = error


implementation

{ Validate a FAT32 8.3 filename.
  fullName should be in "NAME.EXT" form.
  Returns true if valid: name part 1-8 chars, extension 0-3 chars,
  no illegal characters. }
function isValidFAT32Name(fullName : pchar) : boolean;
var
    i, fnLen, dotPos, nameLen, extLen : uint32;
    c : char;
begin
    isValidFAT32Name := false;
    if fullName = nil then exit;
    fnLen := stringSize(fullName);
    if fnLen = 0 then exit;

    { Find last dot position }
    dotPos := fnLen;
    for i := 0 to fnLen - 1 do begin
        if fullName[i] = '.' then
            dotPos := i;
    end;

    nameLen := dotPos;
    if dotPos < fnLen then
        extLen := fnLen - dotPos - 1
    else
        extLen := 0;

    { Name part must be 1-8 characters }
    if (nameLen < 1) or (nameLen > 8) then exit;
    { Extension part must be 0-3 characters }
    if extLen > 3 then exit;

    { Check all characters for validity }
    for i := 0 to fnLen - 1 do begin
        c := fullName[i];
        if i = dotPos then continue; { skip the dot separator }
        { Reject control characters (< 0x20) except we don't need to check 0 since stringSize stops there }
        if uint8(c) < $20 then exit;
        { Reject illegal FAT32 characters: " * / : < > ? \ | }
        case c of
            '"', '*', '/', ':', '<', '>', '?', '\', '|': exit;
        end;
    end;

    isValidFAT32Name := true;
end;

function load(ptr : void) : boolean;
begin
    syslog.logln('FAT32', 'LOADED.')
end;

function matchExtension(dirExt : TFATExtArray; ext : pchar) : boolean;
var
    j : uint32;
    c : char;
    extDone : boolean;
begin
    matchExtension:= true;
    extDone := false;
    for j:=0 to 2 do begin
        if (not extDone) and (ext <> nil) and (ext[j] <> char(0)) then begin
            c:= ext[j];
            { Uppercase a-z to A-Z for case-insensitive FAT32 matching }
            if (c >= 'a') and (c <= 'z') then
                c := char(uint8(c) - 32);
        end else begin
            c:= ' ';
            extDone := true;
        end;
        if dirExt[j] <> c then begin
            matchExtension:= false;
            break;
        end;
    end;
end;

function cleanString(str : pchar; status : puint32) : byteArray8;
var
    i : uint32;
    ii: uint32;
begin
    push_trace('cleanstring()');
    if str = nil then begin
        for i:=0 to 7 do cleanString[i]:= ' ';
        exit;
    end;
    for i:=0 to 7 do begin
        if str[i] = char(0) then begin
            for ii:=i to 7 do begin
                cleanString[ii]:= ' ';
            end;
            break;
        end else begin
            { Uppercase a-z to A-Z for FAT32 }
            if (str[i] >= 'a') and (str[i] <= 'z') then
                cleanString[i]:= char(uint8(str[i]) - 32)
            else
                cleanString[i]:= str[i];
        end;
    end;

end;

{ Split a full filename like 'README.TXT' into name and extension parts.
  Caller must free nameOut and extOut. }
procedure splitFileNameParts(fullName : pchar; var nameOut : pchar; var extOut : pchar);
var
    fnLen, dotPos, i : uint32;
begin
    push_trace('fat32.splitFileNameParts');
    nameOut := nil;
    extOut := nil;
    if fullName = nil then begin
        nameOut := stringNew(0);
        extOut := stringNew(0);
        exit;
    end;
    fnLen := stringSize(fullName);
    dotPos := fnLen;
    for i := 0 to fnLen - 1 do begin
        if fullName[i] = '.' then
            dotPos := i;
    end;
    nameOut := stringTrim(fullName, dotPos);
    if dotPos < fnLen then
        extOut := stringCopy(pchar(@fullName[dotPos + 1]))
    else
        extOut := stringNew(0);
end;    

function cleanStringCha(str : pchar) : pchar;
var
    i : uint32;
    ii: uint32;
begin
    cleanStringCha:= pchar(kalloc(10));
    memset(uint32(cleanstringcha), 0, 10);
    push_trace('cleanstringcha');
    if str = nil then begin
        for i:=0 to 7 do cleanStringCha[i]:= ' ';
        exit;
    end;
    for i:=0 to 7 do begin
        if str[i] = char(0) then begin
            for ii:=i to 7 do begin
                cleanStringCha[ii]:= ' ';
            end;
            break;
        end else begin
                        push_trace('cleanstringcha1.2');
            cleanstringcha[i]:= str[i];

        end;
    end;

end;

function readBootRecord(volume : PStorage_volume) : PBootRecord; // need write functions for boot record!
var
    buffer : puint32;
begin
    push_trace('fat32.readBootRecord.enter');
    buffer:= puint32(kalloc(512));
    memset(uint32(buffer), 0, 512);
    storagemanager.storage_read(volume^.device, volume^.sectorStart + 1, 1, buffer, nil, nil);
    readBootRecord:= PBootRecord(buffer);
end;

//TODO fat starts after reserved secotrs

function readFat(volume : PStorage_volume; cluster : uint32; bootRecord : PBootRecord) : uint32;
var
    buffer              : puint32;
    fatEntriesPerSector : uint32;
    sectorLocation      : uint32;
    dataStart : uint32;
begin
    push_trace('fat32.readFat.enter');
    buffer:= puint32(kalloc(bootRecord^.sectorsize));
    memset(uint32(buffer), 0, bootRecord^.sectorsize);
    fatEntriesPerSector:= bootRecord^.sectorsize div 4;
    sectorLocation:= cluster div fatEntriesPerSector;
    dataStart:= (volume^.sectorStart + 1 + bootRecord^.rsvSectors);

    storagemanager.storage_read(volume^.device, datastart + sectorLocation, 1, buffer, nil, nil); 
    readFat:= buffer[cluster - (sectorLocation * fatEntriesPerSector)];

    kfree(buffer);
end;

procedure writeFat(volume : PStorage_volume; cluster : uint32; value : uint32; bootRecord : PBootRecord);
var
    buffer              : puint32;
    fatEntriesPerSector : uint32;
    sectorLocation      : uint32;
    dataStart           : uint32;
begin
    push_trace('fat32.writeFat.enter');
    buffer:= puint32(kalloc(bootRecord^.sectorsize));
    memset(uint32(buffer), 0, bootRecord^.sectorsize);
    fatEntriesPerSector:= bootRecord^.sectorsize div 4;
    sectorLocation:= cluster div fatEntriesPerSector;
    dataStart:= (volume^.sectorStart + 1 + bootRecord^.rsvSectors);

    storagemanager.storage_read(volume^.device, dataStart + sectorLocation, 1, buffer, nil, nil);
    buffer[cluster - (sectorLocation * fatEntriesPerSector)]:= value;
    storagemanager.storage_write(volume^.device, dataStart + sectorLocation, 1, buffer, nil, nil);

    kfree(buffer);
end;

function getFatChain(volume : PStorage_volume; cluster : uint32; bootRecord : PBootRecord) : PLinkedListBase;
var
    currentCluster      : uint32;
    currentClusterValue : uint32;
    clusters            : PLinkedListBase;
    dirElm              : puint32;
begin
    push_trace('fat32.getFatChain.enter');
    clusters:= LL_New(sizeof(uint32));
    currentCluster:= cluster;
    currentClusterValue:= cluster;

    while true do begin
        currentClusterValue:= readFat(volume, currentClusterValue, bootRecord);

        if (currentClusterValue and $0FFFFFFF) = $0FFFFFF7 then begin
            push_trace('fat32.getFatChain.badCluster');
            break;
        end else if (currentClusterValue and $0FFFFFFF) >= $0FFFFFF8 then begin
            dirElm:= LL_add(clusters);
            dirElm^:= currentCluster;
            break;
        end else if currentClusterValue = 0 then begin
            push_trace('fat32.getFatChain.freeCluster');
            break;
        end else begin
            dirElm:= LL_add(clusters);
            dirElm^:= currentCluster;
        end;

        currentCluster := currentClusterValue;
    end;

    getFatChain:= clusters;
end;

//TODO improve with FSINFO
function findFreeClusters(volume : PStorage_volume; amount : uint32; bootRecord : PBootRecord) : PLinkedListBase;
var
    i                   : uint32 = 2;
    currentClusterValue : uint32;
    currentAmount       : uint32 = 0;
    maxCluster          : uint32;
    clusters            : PLinkedListBase;
    dirElm              : puint32;
begin
    push_trace('fat32.findFreeClusters.enter');
    clusters := LL_New(8);

    { Calculate total number of data clusters on this volume }
    if bootRecord^.sectorsize > 0 then
        maxCluster := (bootRecord^.FATSize * bootRecord^.sectorsize) div 4
    else
        maxCluster := 0;

    while (i < maxCluster) do begin

        if currentAmount = amount then break;

        currentClusterValue:= readFat(volume, i, bootRecord);

        if currentClusterValue = 0 then begin
            dirElm:= LL_add(clusters);
            dirElm^:= i;
            currentAmount+=1;
        end;

        i+=1;
    end;

    { If we couldn't find enough free clusters, the disk is full }
    if currentAmount < amount then begin
        LL_Free(clusters);
        findFreeClusters := nil;
        exit;
    end;

    findFreeClusters:= clusters;
end;

//TODO add optional attributes flag to refine what i return
function getDirEntries(volume : PStorage_volume; cluster : uint32; bootRecord : PBootRecord) : PLinkedListBase;
var
    buffer : puint32;
    bufferI : puint32;
    clusters : PLinkedListBase;
    directories : PLinkedListBase;
    i : uint32 = 0;
    maxEntries : uint32;
    datastart : uint32;
    sectorLocation : uint32;
    dirElm : puint32;
begin
    push_trace('fat32.getDirEntries.enter');
    directories:= LL_New(sizeof(TDirectory));

    clusters:= PLinkedListBase(getFatChain(volume, cluster, bootRecord));
    push_trace('fat32.getDirEntries.allocBuffer');
    buffer:= puint32(kalloc( (bootRecord^.sectorSize * bootRecord^.spc) * LL_size(clusters) ));
    memset(uint32(buffer), 0, (bootRecord^.sectorSize * bootRecord^.spc) * LL_size(clusters) );

    dataStart:= volume^.sectorStart + 1 + bootRecord^.rsvSectors + bootRecord^.FATSize;

    push_trace('fat32.getDirEntries.readSectors');
    for i:=0 to LL_size(clusters) - 1 do begin
        sectorLocation:= bootRecord^.spc * (i + cluster);
        bufferI:= puint32(uint32(buffer) + uint32(i * bootRecord^.spc * bootRecord^.sectorSize));
        storagemanager.storage_read(volume^.device, datastart + sectorLocation, bootRecord^.spc, bufferI, nil, nil); //datastart + spc(i + cluster)
    end;

    i:=0;
    maxEntries:= ((bootRecord^.sectorSize * bootRecord^.spc) * LL_size(clusters)) div sizeof(TDirectory);
    while i < maxEntries do begin
        if PDirectory(buffer)[i].fileName[0] = char(0) then break;

        dirElm:= LL_Add(directories);
        PDirectory(dirElm)^:= PDirectory(buffer)[i];
        i+=1;
    end;

    getDirEntries:= directories; //get last .
    LL_Free(clusters);
    kfree(buffer);
    push_trace('fat32.getDirEntries.exit');
end;

function compareByteArray8(str1 : byteArray8; str2 : byteArray8) : boolean;
var
    i : uint32;
begin
    push_trace('fat32.compareArray');
    compareByteArray8:= true;
    for i:=0 to 7 do begin
        if str1[i] <> str2[i] then begin
            compareByteArray8:= false;
            break;
        end;
    end;
end;

function fat2GenericEntries(list : PLinkedListBase) : PLinkedListBase;
var
    i        : uint32;
    entry    : PDirectory_Entry;
    dir      : PDirectory;
    dirElm   : puint32;
    nameBuf  : pchar;
    nameLen  : uint32;
    extLen   : uint32;
begin
    push_trace('fat32.fat2GenericEntries.enter');
    puint32(entry) := kalloc(sizeof(TDirectory_Entry));
    fat2GenericEntries:= LL_New(sizeof(TDirectory_Entry));

    if LL_size(list) > 0 then begin

        for i:= 0 to LL_Size(list) - 1 do begin
            dir := PDirectory(LL_get(list, i));

            { Trim trailing spaces from fileName (8 bytes) }
            nameLen := 8;
            while (nameLen > 0) and (dir^.fileName[nameLen - 1] = ' ') do
                nameLen := nameLen - 1;

            { Trim trailing spaces from extension (3 bytes) }
            extLen := 3;
            while (extLen > 0) and (dir^.fileExtension[extLen - 1] = ' ') do
                extLen := extLen - 1;

            { Build combined filename: NAME.EXT or just NAME }
            if extLen > 0 then begin
                nameBuf := pchar(kalloc(nameLen + 1 + extLen + 1));
                memcpy(uint32(@dir^.fileName[0]), uint32(nameBuf), nameLen);
                nameBuf[nameLen] := '.';
                memcpy(uint32(@dir^.fileExtension[0]), uint32(@nameBuf[nameLen + 1]), extLen);
                nameBuf[nameLen + 1 + extLen] := char(0);
            end else begin
                nameBuf := pchar(kalloc(nameLen + 1));
                memcpy(uint32(@dir^.fileName[0]), uint32(nameBuf), nameLen);
                nameBuf[nameLen] := char(0);
            end;

            entry^.fileName := nameBuf;

            if dir^.attributes = $10 then begin
                entry^.entryType:= TDirectory_Entry_Type.directoryEntry;
            end else begin
                entry^.entryType:= TDirectory_Entry_Type.fileEntry;
            end;

            //add to list
            dirElm:= LL_add(fat2GenericEntries);
            PDirectory_Entry(dirElm)^:= entry^;
        end;
    end;

    LL_Free(list);
    kfree(puint32(entry));
    push_trace('fat32.fat2GenericEntries.exit');
end;

//need to find out why having multiple dir stings isn't working, maybe the ls command? did I fix this?
function readDirectory(volume : PStorage_volume; directory : pchar; statusOut : puint32) : PLinkedListBase; //statusout: 0 = success, 1 = dir not exsist, 2 = not directory, 3 = invalid name, 4= already exists
var
    bootRecord       : PBootRecord;
    directoryStrings : PLinkedListBase;
    directories      : PLinkedListBase;
    cluster          : uint32;
    i                : uint32;
    ii               : uint32 = 0;
    dirEntry         : PDirectory;
    status : puint32;
begin
    status:= puint32(kalloc(sizeof(uint32)));
    push_trace('fat32.readDirectory.enter');
    status^:= ord(eNone);
    bootRecord:= readBootRecord(volume);
    directoryStrings:= LL_fromString(directory, '/');
    directories:= getDirEntries(volume, bootRecord^.rootCluster, bootRecord);

    if LL_size(directoryStrings) > 0 then begin
        for i:=0 to (LL_Size(directoryStrings) ) do begin /// maybe -1 will work
            ii:=0;

            while true do begin
                if ii > LL_Size(directories) - 1 then begin
                    status^:= ord(eDirectoryDoesNotExist);
                    break; 
                end;
                dirEntry:= PDirectory(LL_Get(directories, ii));

                if compareByteArray8( dirEntry^.fileName, cleanString( pchar(puint32(LL_Get(directoryStrings, i))^), status)) then begin
                    cluster:= uint32(dirEntry^.clusterLow);
                    cluster:= uint32(cluster) or uint32(dirEntry^.clusterHigh shl 16);
                    break;
                end;
                ii+=1;
            end;

            if status^ <> 0 then break;
            
            LL_Free(directories); 
            directories:= getDirEntries(volume, cluster, bootRecord);

            if i = LL_Size(directoryStrings) - 1 then break;
        end;
    end else begin
        while true do begin
            if ii > LL_Size(directories) - 1 then break;
            dirEntry:= PDirectory(LL_Get(directories, ii));
            ii+=1;
        end;
    end;

    readDirectory:= directories;

    if statusOut <> nil then statusOut^ := status^;
    kfree(status);
    LL_Free(directoryStrings);
    kfree(puint32(bootRecord));
    push_trace('fat32.readDirectory.exit');
end;

function readDirectoryGen(volume : PStorage_volume; directory : pchar; status : puint32) : PLinkedListBase; //returns: 0 = success, 1 = dir not exsist, 2 = not directory, 3 = invalid name, 4= already exists
begin
    push_trace('fat32.readDirectoryGen.enter');
    readDirectoryGen:= fat2GenericEntries(readDirectory(volume, directory, status));
    push_trace('fat32.readDirectoryGen.exit');
end;

//need to allow for setting file extension
function writeDirectory(volume : PStorage_volume; directory : pchar; dirName : pchar; attributes : uint32; statusOut : puint32) : uint32; // need to handle parent table cluster overflow, need to take attributes
var
    directories     : PLinkedListBase;
    parentDirectory : PDirectory;
    parentCluster   : uint32;
    clusters        : PLinkedListBase;
    cluster         : uint32;
    bootRecord      : PBootRecord;
    buffer          : puint32;
    bufferPointer   : PDirectory;
    dataStart       : uint32;
    EntriesPerSector : uint32;
    sectorLocation  : uint32;
    dataOffset      : uint32;
    i : uint32;

    thisArray     : byteArray8 = ('.',' ',' ',' ',' ',' ',' ',' ');
    parentArray   : byteArray8 = ('.','.',' ',' ',' ',' ',' ',' ');
    status : puint32;

    namePart : pchar;
    extPart  : pchar;
begin
    push_trace('fat32.writeDirectory.enter');
    writeDirectory := 0;
    status:= puint32(kalloc(sizeof(uint32)));
    status^:= ord(eNone);

    { Validate the directory name as a valid FAT32 8.3 name }
    if not isValidFAT32Name(dirName) then begin
        statusOut^:= ord(eInvalidFileName);
        kfree(status);
        exit;
    end;

    push_trace('fat32.writeDirectory.readDir');
    directories:= readDirectory(volume, directory, status);

    { If the parent directory does not exist, bail out }
    if status^ <> ord(eNone) then begin
        statusOut^:= status^;
        kfree(status);
        LL_Free(directories);
        exit;
    end;

    { Split dirName for duplicate checking }
    splitFileNameParts(dirName, namePart, extPart);

    if(LL_size(directories) > 1) then begin
        for i:=0 to LL_Size(directories) - 1 do begin
            if compareByteArray8(PDirectory(LL_get(directories, i))^.fileName, cleanString( namePart , status))
               and matchExtension(PDirectory(LL_get(directories, i))^.fileExtension, extPart) then begin
                status^:= ord(eDirectoryAlreadyExists);
            end;
        end;
    end;

    kfree(void(namePart));
    kfree(void(extPart));

    bootRecord:= readBootRecord(volume);
    datastart:= volume^.sectorStart + 1 + bootRecord^.FATSize + bootRecord^.rsvSectors;

    if status^ = ord(eNone) then begin
        push_trace('fat32.writeDirectory.createEntry');

        { Check if directory sector is full }
        EntriesPerSector:= uint32(bootRecord^.sectorSize) div uint32(sizeof(TDirectory));
        if LL_size(directories) >= EntriesPerSector then begin
            { Current sector is full — would need cluster chain extension (not yet supported) }
            statusOut^:= ord(eDirectoryFull);
            kfree(status);
            kfree(puint32(bootRecord));
            LL_Free(directories);
            exit;
        end;

        parentDirectory:= PDirectory(LL_Get(directories, 0));
        parentCluster:= uint32(parentDirectory^.clusterlow) or uint32(parentDirectory^.clusterhigh shl 16);

        clusters:= findFreeClusters(volume, 1, bootRecord);
        if clusters = nil then begin
            { No free clusters available — disk is full }
            statusOut^:= ord(eDiskFull);
            kfree(status);
            kfree(puint32(bootRecord));
            LL_Free(directories);
            exit;
        end;
        cluster:= uint32(LL_Get(clusters, 0)^);
        LL_Free(clusters);
        buffer:= puint32(kalloc(bootRecord^.sectorSize));

        if attributes = $10 then begin // if directory

            memset(uint32(buffer), 0, bootRecord^.sectorSize);

            bufferPointer:= @PDirectory(buffer)[0];
            bufferPointer^.fileName:= thisArray; //TODO implement time
            bufferPointer^.attributes:= attributes;
            bufferPointer^.clusterLow:= cluster;
            bufferPointer^.clusterHigh:= uint16((cluster shr 16) and $0000FFFF);
            
            bufferPointer:= @PDirectory(buffer)[1];
            bufferPointer^.fileName:= parentArray; //TODO implement time
            bufferPointer^.attributes:= attributes;
            bufferPointer^.clusterLow:= parentCluster;
            bufferPointer^.clusterHigh:= uint16((parentCluster shr 16) and $0000FFFF);

            //write to disk
            storagemanager.storage_write(volume^.device, dataStart + (cluster * bootRecord^.spc), 1, buffer, nil, nil);

            //write fat
            writeFat(volume, cluster, $FFFFFFF8, bootRecord);
        end;
        memset(uint32(buffer), 0, bootRecord^.sectorSize);
        //calculate write cluster using directories and parentCluster
        sectorLocation:= LL_size(directories) * sizeof(TDirectory) div bootRecord^.sectorSize;
        sectorLocation:= sectorLocation + (parentCluster * bootRecord^.spc);

        //dataOffset:= datastart + ( (LL_size(directories) * sizeof(PDirectory)) - (sizeUsed * bootRecord^.sectorSize));
        storagemanager.storage_read(volume^.device, dataStart + sectorLocation, 1, buffer, nil, nil);

        //construct my dir entry
        EntriesPerSector:= uint32(bootRecord^.sectorSize) div uint32(sizeof(TDirectory));
        bufferPointer:= @PDirectory(buffer)[LL_size(directories) - ((LL_size(directories) div EntriesPerSector) * EntriesPerSector)];

        { Split dirName into name + extension parts for FAT32 8.3 format }
        splitFileNameParts(dirName, namePart, extPart);
        bufferPointer^.fileName:= cleanString(namePart, status);
        bufferPointer^.attributes:= attributes;
        { Always initialize extension to spaces }
        bufferPointer^.fileExtension[0] := ' ';
        bufferPointer^.fileExtension[1] := ' ';
        bufferPointer^.fileExtension[2] := ' ';
        if attributes = 0 then begin
            { Copy extension characters for files }
            if (extPart <> nil) and (extPart[0] <> char(0)) then begin
                for i := 0 to 2 do begin
                    if extPart[i] = char(0) then break;
                    { Uppercase for FAT32 }
                    if (extPart[i] >= 'a') and (extPart[i] <= 'z') then
                        bufferPointer^.fileExtension[i] := char(uint8(extPart[i]) - 32)
                    else
                        bufferPointer^.fileExtension[i] := extPart[i];
                end;
            end;
        end;
        kfree(void(namePart));
        kfree(void(extPart));
        bufferPointer^.clusterLow:= cluster;
        bufferPointer^.clusterHigh:= uint16((cluster shr 16) and $0000FFFF);

        writeDirectory:= cluster;

        push_trace('fat32.writeDirectory.writeToDisk');
        //write to disk
        storagemanager.storage_write(volume^.device, dataStart + sectorLocation, 1, buffer, nil, nil);
        kfree(buffer);
    end;

    statusOut^:= status^;
    kfree(status);
    kfree(puint32(bootRecord));
    LL_Free(directories);

end;

procedure writeDirectoryGen(volume : PStorage_volume; directory : pchar; dirName : pchar; attributes : uint32; statusOut : puint32); // need to handle parent table cluster overflow, need to take attributes
begin
    push_trace('fat32.writeDirectoryGen.enter');
    writeDirectory(volume, directory, dirName, attributes, statusOut);
    push_trace('fat32.writeDirectoryGen.exit');
end;

{ Split a full path like 'SYSTEM/FILE.TXT' into parent dir ('SYSTEM') and name ('FILE.TXT').
  If no separator, parentOut is empty string and nameOut is the whole path.
  Caller must free parentOut and nameOut. }
procedure splitPathParts(fullPath : pchar; var parentOut : pchar; var nameOut : pchar);
var
    pathLen, lastSlash, i : uint32;
begin
    parentOut := nil;
    nameOut := nil;
    if fullPath = nil then begin
        parentOut := stringNew(0);
        nameOut := stringNew(0);
        exit;
    end;
    pathLen := stringSize(fullPath);
    if pathLen = 0 then begin
        parentOut := stringNew(0);
        nameOut := stringNew(0);
        exit;
    end;

    { Find last '/' separator }
    lastSlash := pathLen; { sentinel: no slash found }
    for i := 0 to pathLen - 1 do begin
        if fullPath[i] = '/' then
            lastSlash := i;
    end;

    if lastSlash < pathLen then begin
        parentOut := stringTrim(fullPath, lastSlash);
        nameOut := stringCopy(pchar(@fullPath[lastSlash + 1]));
    end else begin
        parentOut := stringNew(0);
        nameOut := stringCopy(fullPath);
    end;
end;

{ Free a FAT chain starting from the given cluster — marks all clusters as free (0). }
procedure freeFatChain(volume : PStorage_volume; startCluster : uint32; bootRecord : PBootRecord);
var
    currentCluster : uint32;
    nextCluster    : uint32;
begin
    push_trace('fat32.freeFatChain.enter');
    currentCluster := startCluster;
    while true do begin
        nextCluster := readFat(volume, currentCluster, bootRecord);
        writeFat(volume, currentCluster, 0, bootRecord);

        if (nextCluster and $0FFFFFFF) >= $0FFFFFF8 then break; { end of chain }
        if (nextCluster and $0FFFFFFF) = $0FFFFFF7 then break;  { bad cluster }
        if nextCluster = 0 then break;                          { already free }

        currentCluster := nextCluster;
    end;
    push_trace('fat32.freeFatChain.exit');
end;

{ Delete a file from the volume. filePath is relative to volume root, e.g. 'SYSTEM/FILE.TXT' or 'FILE.TXT' }
procedure deleteFile(volume : PStorage_Volume; filePath : pchar; statusOut : puint32);
var
    parentDir   : pchar;
    fileName    : pchar;
    namePart    : pchar;
    extPart     : pchar;
    bootRecord  : PBootRecord;
    directories : PLinkedListBase;
    dir         : PDirectory;
    parentCluster : uint32;
    parentEntry   : PDirectory;
    found       : boolean;
    foundIdx    : uint32;
    i           : uint32;
    cluster     : uint32;
    status      : puint32;
    dataStart   : uint32;
    sectorLocation : uint32;
    buffer      : puint32;
    EntriesPerSector : uint32;
begin
    push_trace('fat32.deleteFile.enter');
    status := puint32(kalloc(4));
    status^ := ord(eNone);

    { Split path into parent directory and filename }
    splitPathParts(filePath, parentDir, fileName);

    if (fileName = nil) or (stringSize(fileName) = 0) then begin
        if statusOut <> nil then statusOut^ := ord(eInvalidFileName);
        kfree(status);
        if parentDir <> nil then kfree(void(parentDir));
        if fileName <> nil then kfree(void(fileName));
        exit;
    end;

    bootRecord := readBootRecord(volume);
    directories := readDirectory(volume, parentDir, status);

    if status^ <> ord(eNone) then begin
        if statusOut <> nil then statusOut^ := status^;
        LL_Free(directories);
        kfree(status);
        kfree(puint32(bootRecord));
        kfree(void(parentDir));
        kfree(void(fileName));
        exit;
    end;

    { Get parent cluster from the '.' entry }
    if LL_size(directories) < 1 then begin
        if statusOut <> nil then statusOut^ := ord(eDirectoryDoesNotExist);
        LL_Free(directories);
        kfree(status);
        kfree(puint32(bootRecord));
        kfree(void(parentDir));
        kfree(void(fileName));
        exit;
    end;

    parentEntry := PDirectory(LL_Get(directories, 0));
    parentCluster := uint32(parentEntry^.clusterLow) or uint32(parentEntry^.clusterHigh shl 16);

    { Split filename for 8.3 matching }
    splitFileNameParts(fileName, namePart, extPart);

    { Find the entry in the directory }
    found := false;
    foundIdx := 0;
    for i := 0 to LL_size(directories) - 1 do begin
        dir := PDirectory(LL_Get(directories, i));
        if compareByteArray8(dir^.fileName, cleanString(namePart, status))
           and matchExtension(dir^.fileExtension, extPart) then begin
            { Don't allow deleting . or .. entries, or directories via deleteFile }
            if (dir^.attributes and $10) = $10 then begin
                if statusOut <> nil then statusOut^ := ord(eNotADirectory);
                LL_Free(directories);
                kfree(status);
                kfree(puint32(bootRecord));
                kfree(void(parentDir));
                kfree(void(fileName));
                kfree(void(namePart));
                kfree(void(extPart));
                exit;
            end;
            found := true;
            foundIdx := i;
            cluster := uint32(dir^.clusterLow) or uint32(dir^.clusterHigh shl 16);
            break;
        end;
    end;

    kfree(void(namePart));
    kfree(void(extPart));

    if not found then begin
        if statusOut <> nil then statusOut^ := ord(eFileDoesNotExist);
        LL_Free(directories);
        kfree(status);
        kfree(puint32(bootRecord));
        kfree(void(parentDir));
        kfree(void(fileName));
        exit;
    end;

    { Free the FAT chain for this file }
    if cluster >= 2 then
        freeFatChain(volume, cluster, bootRecord);

    { Mark the directory entry as deleted ($E5) on disk }
    dataStart := volume^.sectorStart + 1 + bootRecord^.rsvSectors + bootRecord^.FATSize;
    EntriesPerSector := uint32(bootRecord^.sectorSize) div uint32(sizeof(TDirectory));
    sectorLocation := (foundIdx div EntriesPerSector) + (parentCluster * bootRecord^.spc);

    buffer := puint32(kalloc(bootRecord^.sectorSize));
    storagemanager.storage_read(volume^.device, dataStart + sectorLocation, 1, buffer, nil, nil);

    PDirectory(buffer)[foundIdx mod EntriesPerSector].fileName[0] := char($E5);

    storagemanager.storage_write(volume^.device, dataStart + sectorLocation, 1, buffer, nil, nil);
    kfree(buffer);

    if statusOut <> nil then statusOut^ := ord(eNone);

    LL_Free(directories);
    kfree(status);
    kfree(puint32(bootRecord));
    kfree(void(parentDir));
    kfree(void(fileName));
    push_trace('fat32.deleteFile.exit');
end;

{ Delete a directory from the volume. path is relative to volume root. Directory must be empty. }
procedure deleteDir(volume : PStorage_Volume; path : pchar; statusOut : puint32);
var
    parentDir   : pchar;
    dirName     : pchar;
    namePart    : pchar;
    extPart     : pchar;
    bootRecord  : PBootRecord;
    directories : PLinkedListBase;
    childDirs   : PLinkedListBase;
    dir         : PDirectory;
    parentCluster : uint32;
    parentEntry   : PDirectory;
    found       : boolean;
    foundIdx    : uint32;
    i           : uint32;
    cluster     : uint32;
    status      : puint32;
    dataStart   : uint32;
    sectorLocation : uint32;
    buffer      : puint32;
    EntriesPerSector : uint32;
    childCount  : uint32;
begin
    push_trace('fat32.deleteDir.enter');
    status := puint32(kalloc(4));
    status^ := ord(eNone);

    { Split path into parent directory and target dir name }
    splitPathParts(path, parentDir, dirName);

    if (dirName = nil) or (stringSize(dirName) = 0) then begin
        if statusOut <> nil then statusOut^ := ord(eInvalidFileName);
        kfree(status);
        if parentDir <> nil then kfree(void(parentDir));
        if dirName <> nil then kfree(void(dirName));
        exit;
    end;

    bootRecord := readBootRecord(volume);
    directories := readDirectory(volume, parentDir, status);

    if status^ <> ord(eNone) then begin
        if statusOut <> nil then statusOut^ := status^;
        LL_Free(directories);
        kfree(status);
        kfree(puint32(bootRecord));
        kfree(void(parentDir));
        kfree(void(dirName));
        exit;
    end;

    if LL_size(directories) < 1 then begin
        if statusOut <> nil then statusOut^ := ord(eDirectoryDoesNotExist);
        LL_Free(directories);
        kfree(status);
        kfree(puint32(bootRecord));
        kfree(void(parentDir));
        kfree(void(dirName));
        exit;
    end;

    parentEntry := PDirectory(LL_Get(directories, 0));
    parentCluster := uint32(parentEntry^.clusterLow) or uint32(parentEntry^.clusterHigh shl 16);

    { Split dirName for 8.3 matching }
    splitFileNameParts(dirName, namePart, extPart);

    { Find the directory entry }
    found := false;
    foundIdx := 0;
    for i := 0 to LL_size(directories) - 1 do begin
        dir := PDirectory(LL_Get(directories, i));
        if compareByteArray8(dir^.fileName, cleanString(namePart, status))
           and matchExtension(dir^.fileExtension, extPart) then begin
            { Must be a directory }
            if (dir^.attributes and $10) <> $10 then begin
                if statusOut <> nil then statusOut^ := ord(eNotADirectory);
                LL_Free(directories);
                kfree(status);
                kfree(puint32(bootRecord));
                kfree(void(parentDir));
                kfree(void(dirName));
                kfree(void(namePart));
                kfree(void(extPart));
                exit;
            end;
            found := true;
            foundIdx := i;
            cluster := uint32(dir^.clusterLow) or uint32(dir^.clusterHigh shl 16);
            break;
        end;
    end;

    kfree(void(namePart));
    kfree(void(extPart));

    if not found then begin
        if statusOut <> nil then statusOut^ := ord(eDirectoryDoesNotExist);
        LL_Free(directories);
        kfree(status);
        kfree(puint32(bootRecord));
        kfree(void(parentDir));
        kfree(void(dirName));
        exit;
    end;

    { Check if directory is empty — should contain only '.' and '..' }
    childDirs := getDirEntries(volume, cluster, bootRecord);
    childCount := LL_size(childDirs);
    LL_Free(childDirs);

    if childCount > 2 then begin
        { Directory is not empty }
        if statusOut <> nil then statusOut^ := ord(eDirectoryNotEmpty);
        LL_Free(directories);
        kfree(status);
        kfree(puint32(bootRecord));
        kfree(void(parentDir));
        kfree(void(dirName));
        exit;
    end;

    { Free the FAT chain for this directory's data }
    if cluster >= 2 then
        freeFatChain(volume, cluster, bootRecord);

    { Mark the directory entry as deleted ($E5) on disk }
    dataStart := volume^.sectorStart + 1 + bootRecord^.rsvSectors + bootRecord^.FATSize;
    EntriesPerSector := uint32(bootRecord^.sectorSize) div uint32(sizeof(TDirectory));
    sectorLocation := (foundIdx div EntriesPerSector) + (parentCluster * bootRecord^.spc);

    buffer := puint32(kalloc(bootRecord^.sectorSize));
    storagemanager.storage_read(volume^.device, dataStart + sectorLocation, 1, buffer, nil, nil);

    PDirectory(buffer)[foundIdx mod EntriesPerSector].fileName[0] := char($E5);

    storagemanager.storage_write(volume^.device, dataStart + sectorLocation, 1, buffer, nil, nil);
    kfree(buffer);

    if statusOut <> nil then statusOut^ := ord(eNone);

    LL_Free(directories);
    kfree(status);
    kfree(puint32(bootRecord));
    kfree(void(parentDir));
    kfree(void(dirName));
    push_trace('fat32.deleteDir.exit');
end;

procedure writeFile(volume : PStorage_volume; directory : pchar; entry : PDirectory_Entry; byteCount : uint32; buffer : puint32; statusOut : puint32);
var
    bootRecord : PBootRecord;
    directories : PLinkedListBase;
    clusters : PLinkedListBase;
    startCluster: uint32;
    device : PStorage_Device;
    dir : PDirectory;
    exists : boolean = false;
    sectorCount : uint32;
    clusterCount : uint32;
    clusterDifference : uint32;
    dataStart : uint32;
    iterations : uint32;
    bufferPointer : puint32;
    dataPosition : uint32;

    i : uint32;
    status : puint32;
    namePart : pchar;
    extPart  : pchar;
begin
    push_trace('fat32.writeFile.enter');
    status:= kalloc(4);
    status^:= ord(eNone);

    { Validate the filename before doing any I/O }
    if not isValidFAT32Name(entry^.fileName) then begin
        if statusOut <> nil then statusOut^:= ord(eInvalidFileName);
        kfree(status);
        exit;
    end;

    bootRecord:= readBootRecord(volume);
    device:= volume^.device;
    push_trace('fat32.writeFile.readDir');
    directories:= readDirectory(volume, directory, status);

    { If the parent directory does not exist, bail out }
    if status^ <> ord(eNone) then begin
        if statusOut <> nil then statusOut^:= status^;
        LL_Free(directories);
        kfree(status);
        kfree(puint32(bootRecord));
        exit;
    end;

    sectorCount:= (byteCount div bootRecord^.sectorSize) + 1;
    datastart:= volume^.sectorStart + 1 + bootRecord^.FATSize + bootRecord^.rsvSectors;
    push_trace('fat32.writeFile.checkExists');

    { Split entry filename into name + extension for FAT32 8.3 matching }
    splitFileNameParts(entry^.fileName, namePart, extPart);

    for i:=0 to LL_size(directories) - 1 do begin
        dir:= PDirectory(LL_get(directories, i));
        if compareByteArray8(dir^.fileName, cleanString(namePart, status)) and matchExtension(dir^.fileExtension, extPart) then begin
            exists:= true; 
            break;
        end;
    end;

    kfree(void(namePart));
    kfree(void(extPart));


    if exists then begin //saving to existing file
        push_trace('fat32.writeFile.existingFile');
        startCluster:= uint32(dir^.clusterlow) or uint32(dir^.clusterhigh shl 16);
        clusters:= getFatChain(volume, startCluster, bootRecord); //check no clusters and check if needs to be more or less, add/remove clusters
        clusterCount := LL_size(clusters);
        push_trace('fat32.writeFile.gotFatChain');

        if (clusterCount * bootRecord^.spc) > sectorCount then begin //shrink
            clusterDifference:= clusterCount - (sectorCount div bootRecord^.spc);
            for i:= (clusterCount - clusterDifference) + 1 to clusterCount do begin //free unused clusters
                writeFat(volume, startCluster + i, 0, bootRecord);
            end;
            writeFat(volume, startCluster + (clusterCount - clusterDifference), $FFFFFFF8, bootRecord); // add new cluster terminator
            LL_Free(clusters);
        end else if (clusterCount * bootRecord^.spc) < sectorCount then begin //expand
            clusterDifference:= (sectorCount div bootRecord^.spc) - clusterCount;
            LL_Free(clusters);
            clusters:= findFreeClusters(volume, clusterDifference, bootRecord);
            if clusters = nil then begin
                { Disk full — cannot expand file }
                if statusOut <> nil then statusOut^:= ord(eDiskFull);
                LL_Free(directories);
                kfree(status);
                kfree(puint32(bootRecord));
                exit;
            end;
            for i:= clusterCount to clusterCount + clusterDifference - 1 do begin
                writeFat(volume, startCluster + i, startCluster + i + 1, bootRecord);
            end;
                writeFat(volume, startcluster + clusterCount + clusterDifference, $FFFFFFF8, bootRecord);
            LL_Free(clusters);
        end else begin //nothing
            clusterDifference:= 0;
            LL_Free(clusters);
        end;

    end else begin
        push_trace('fat32.writeFile.newFile');

        startCluster:= writeDirectory(volume, directory, entry^.fileName, 0, status);

        { If writeDirectory failed (disk full, dir full, invalid name, etc.), propagate error }
        if status^ <> ord(eNone) then begin
            if statusOut <> nil then statusOut^:= status^;
            LL_Free(directories);
            kfree(status);
            kfree(puint32(bootRecord));
            exit;
        end;

        clusterDifference:= (byteCount div bootRecord^.sectorsize) div 4;
            push_trace('fat32.writeFile.newFile.setupFat');

        for i:= startcluster to startCluster + clusterDifference - 1 do begin
            writeFat(volume, i, i + 1, bootRecord);
        end;
                push_trace('fat32.writeFile.newFile.writeFatEnd');

        writeFat(volume, startcluster + clusterDifference, $FFFFFFF8, bootRecord);
    end;

    push_trace('fat32.writeFile.writeSectors');

    iterations:= (bytecount div bootRecord^.sectorSize) div bootRecord^.spc; //no of clusters

    for i:=0 to iterations do begin
        dataPosition:= i * uint32(bootRecord^.sectorsize * 4); //needs to be bytes / 4
        bufferPointer:= @buffer[dataPosition div 4]; //todo change to puint8
        storagemanager.storage_write(volume^.device, dataStart + (startCluster * bootRecord^.spc) + (i * 4), 1, bufferPointer, nil, nil); //i * 4 needs to be changed, TODO fix fucking IDE driver, it suks
        storagemanager.storage_write(volume^.device, dataStart + (startCluster * bootRecord^.spc) + (i * 4) + 1, 1, @bufferPointer[512 div 4], nil, nil); 
        storagemanager.storage_write(volume^.device, dataStart + (startCluster * bootRecord^.spc) + (i * 4) + 2, 1, @bufferPointer[1024 div 4], nil, nil); 
        storagemanager.storage_write(volume^.device, dataStart + (startCluster * bootRecord^.spc) + (i * 4) + 3, 1, @bufferPointer[1536 div 4], nil, nil); 
    end;

    { Write succeeded }
    if statusOut <> nil then statusOut^:= ord(eNone);

    LL_Free(directories);
    kfree(status);
    kfree(puint32(bootRecord));
end;

function readFile(volume : PStorage_Volume; directory : pchar; fileName : pchar; buffer : puint32; bytecount : puint32) : uint32;
var
    bootRecord  : PBootRecord;
    dirs        : PLinkedListBase;
    dir         : PDirectory;
    readbuffer  : puint32;
    data        : puint32;
    statusOut   : puint32;
    i           : uint32;
    exists      : boolean = false;
    cluster     : uint32;
    clusters    : PLinkedListBase;
    noClusters  : uint32;
    dataStart   : uint32;
    cleanFileName : byteArray8;
    otherCleanFileName : byteArray8;
    tempdir : PDirectory;
    namePart : pchar;
    extPart  : pchar;
begin
    push_trace('fat32.readFile.enter');
    statusOut := puint32(kalloc(sizeof(uint32)));
    statusOut^ := 0;
    bootRecord := readBootRecord(volume);
    push_trace('fat32.readFile.readDir');
    dirs := readDirectory(volume, directory, statusOut);
    datastart:= volume^.sectorStart + 1 + bootRecord^.FATSize + bootRecord^.rsvSectors;
    push_trace('fat32.readFile.searchFile');

    { Split fileName into name + extension for FAT32 8.3 matching }
    splitFileNameParts(fileName, namePart, extPart);

    if LL_size(dirs) > 0 then begin
        cleanFileName := cleanString(namePart, statusOut);

        for i:=0 to LL_Size(dirs) -1 do begin
            tempdir := PDirectory(LL_get(dirs, i));
            otherCleanFileName := cleanString(tempdir^.filename, statusout);

            if compareByteArray8(cleanFileName, otherCleanFileName) and matchExtension(tempdir^.fileExtension, extPart) then begin
                dir:=tempdir;
                exists := true;
                statusOut^ := 0;
            end;
        end;
    end;

    kfree(void(namePart));
    kfree(void(extPart));


    if exists = false then begin
        push_trace('fat32.readFile.notFound');
        LL_Free(dirs);
        kfree(puint32(bootRecord));
        kfree(puint32(statusOut));
        exit(1);
    end else begin
        push_trace('fat32.readFile.found');
        cluster := uint32(dir^.clusterlow) or uint32(dir^.clusterhigh shl 16);
        clusters := getFatChain(volume, cluster, bootRecord);
        noClusters := LL_size(clusters);

        data := puint32(kalloc(noClusters * bootRecord^.spc * bootRecord^.sectorSize + bootRecord^.sectorSize));
        if data = puint32(0) then begin
            push_trace('UNABLE TO ALLOCATE MEMORY');
        end;
        memset(uint32(data), 0, noClusters * bootRecord^.spc * bootRecord^.sectorSize + bootRecord^.sectorSize);

        readbuffer := puint32(kalloc(bootRecord^.sectorSize * 2));
        if readbuffer = puint32(0) then begin
            push_trace('UNABLE TO ALLOCATE MEMORY');
        end;
        memset(uint32(readbuffer), 0, bootRecord^.sectorSize * 2);

        for i:=0 to noClusters * bootRecord^.spc do begin
            storagemanager.storage_read(volume^.device, dataStart + ((cluster * bootRecord^.spc)+ i), 1, readbuffer, nil, nil);
            memcpy(uint32(readbuffer), uint32(@data[i*bootRecord^.sectorSize div 4]), bootRecord^.sectorSize);
        end;

        kfree(readbuffer);
        buffer^ := uint32(data);
        bytecount^ := noClusters * bootRecord^.spc * bootRecord^.sectorSize + bootRecord^.sectorSize;//maybe need to spc
        readFile:= statusOut^;
        LL_Free(dirs);
        LL_Free(clusters);
        kfree(puint32(bootRecord));
        kfree(puint32(statusOut));
        push_trace('fat32.readFile.exit');
    end;

end;

// function checkExists(volume : PStorage_Volume; directory : pchar; fileName : pchar; fileExtension : pchar; entry : PDirectory_Entry) : uint32;
// var
//     bootRecord : PBootRecord;
//     directories : PLinkedListBase;
//     dir : PDirectory;
//     genDir : PDirectory_Entry;
//     data : puint32;
//     statusOut : puint32;
//     i : uint32;
//     exists : boolean = false;
// begin
//     bootRecord := readBootRecord(volume);
//     directories := readDirectory(volume, directory, statusOut);
//     datastart:= volume^.sectorStart + 1 + bootRecord^.FATSize + bootRecord^.rsvSectors;

//     for i:=0 to LL_Size(directories) -1 do begin
//         dir:= PDirectory(LL_Get(directories, i));
//         if (dir^.fileName = entry^.fileName) and (dir^.fileExtension = entry^.extension) then begin
//             exists:= true;
//             break;
//         end;
//     end;

//     PDirectory_Entry := PDirectory_Entry(kalloc(20));

//     PDirectory_Entry^.fileName := pchar(@dir^.fileName);
//     PDirectory_Entry^.extension := pchar(@dir^.fileExtension);

// end;

//TODO check directory commands for errors with a clean disk

procedure create_volume(volume : PStorage_Volume; sectors : uint32; start : uint32; config : puint32);
var
    buffer     : puint32;
    zeroBuffer : puint32;
    bootRecord : PBootRecord;
    dataStart  : uint32;
    fatStart   : uint32;
    FATSize    : uint32;
    batchSize  : uint32;
    batchPos   : uint32;

    asuroArray    : byteArray8 = ('A','S','U','R','O',' ','V','1');
    fatArray      : byteArray8 = ('F','A','T','3','2',' ',' ',' ');
    thisArray     : byteArray8 = ('.',' ',' ',' ',' ',' ',' ',' ');
    parentArray   : byteArray8 = ('.','.',' ',' ',' ',' ',' ',' ');

    asuroFileArray     : byteArray8 = ('A','S','U','R','O',' ',' ',' ');
    mountFileArray     : byteArray8 = ('M','O','U','N','T',' ',' ',' ');
    programFileArray   : byteArray8 = ('P','R','O','G','R','A','M','S');
    rootCluster   : uint32 = 2;

    sysArray : byteArray8 = ('S','Y','S','T','E','M',' ',' ');
    progArray : byteArray8 = ('P','R','O','G','R','A','M','S');
    userArray : byteArray8 = ('U','S','E','R',' ',' ',' ',' ');

    status : puint32;
    disk : PStorage_device;
    spc : uint32;

begin
    push_trace('fat32.create_volume()');

    disk := volume^.device;

    { Default sectors-per-cluster to 1 if config is nil }
    if config <> nil then
        spc := config^
    else
        spc := 1;
    if spc = 0 then spc := 1;

    //fat32 structure
    (* BootRecord            *)
    (* reserved sectors      *)
    (* File Allocation Table *)
    (* Data Area             *)

    buffer:= puint32(kalloc(disk^.sectorSize+512));
    memset(uint32(buffer), 0, disk^.sectorSize);

    bootRecord:= PBootRecord(buffer);

    FATSize:= ((sectors div spc) * 4) div disk^.sectorsize;

    bootRecord^.jmp2boot        := $0; //TODO impliment boot jump
    bootRecord^.OEMName         := asuroArray;
    bootRecord^.sectorSize      := disk^.sectorsize;
    bootRecord^.spc             := 1;
    bootRecord^.rsvSectors      := 32; //32 is standard
    bootRecord^.numFats         := 1;
    bootRecord^.mediaDescp      := $F8;
    bootRecord^.hiddenSectors   := start;
    bootRecord^.manySectors     := sectors;
    bootRecord^.FATSize         := FATSize;
    bootRecord^.rootCluster     := rootCluster;
    bootRecord^.FSInfoCluster   := 0;
    bootRecord^.driveNumber     := $80;
    bootRecord^.volumeID        := 62; //+ puint32(@rtc.getDateTime())^;
    bootRecord^.bsignature      := $29;
    bootRecord^.identString     := fatArray;


    { Write the boot sector signature marker at bytes 508-511 }
    puint32(buffer)[127] := $55AA;

    storagemanager.storage_write(disk, start + 1, 1, puint32(buffer), nil, nil);

    fatStart:= start + 1 + bootRecord^.rsvSectors;
    dataStart:= fatStart + bootRecord^.FATSize;

    { Batch zero the FAT: write 128 sectors at a time instead of 1 }
    if FATSize > 128 then
        batchSize := 128
    else
        batchSize := FATSize;
    zeroBuffer:= puint32(kalloc( disk^.sectorSize * batchSize ));
    memset(uint32(zeroBuffer), 0, disk^.sectorSize * batchSize);

    batchPos := 0;
    while batchPos < FATSize do begin
        if (FATSize - batchPos) >= batchSize then
            storagemanager.storage_write(disk, fatStart + batchPos, batchSize, zeroBuffer)
        else
            storagemanager.storage_write(disk, fatStart + batchPos, FATSize - batchPos, zeroBuffer, nil, nil);
        batchPos += batchSize;
    end;

    kfree(buffer);
    kfree(zeroBuffer);

    buffer:= puint32(kalloc(disk^.sectorSize));
    memset(uint32(buffer), 0, disk^.sectorSize);

    puint32(buffer)[0]:= $0FFFFFF8; //media type marker (reserved entry 0)
    puint32(buffer)[1]:= $0FFFFFFF; //clean/dirty marker (reserved entry 1)
    puint32(buffer)[2]:= $0FFFFFF8; //root cluster end-of-chain (entry 2)

    storagemanager.storage_write(disk, fatStart, 1, buffer, nil, nil);

    kfree(buffer);

    buffer:= puint32(kalloc(disk^.sectorsize));
    memset(uint32(buffer), 0, disk^.sectorsize);

    PDirectory(buffer)[0].fileName   := thisArray;
    PDirectory(buffer)[0].attributes := $08;
    PDirectory(buffer)[0].clusterLow := rootCluster;

    PDirectory(buffer)[1].fileName   := parentArray;
    PDirectory(buffer)[1].attributes := $10;
    PDirectory(buffer)[1].clusterLow := rootCluster;
    
    storagemanager.storage_write(disk, dataStart + (spc * rootCluster), 1, buffer, nil, nil);

    memset(uint32(buffer), 0, disk^.sectorsize);

    status := puint32(kalloc(sizeof(uint32)));
    writeDirectory(volume, '', 'SYSTEM', $10, status);
    kfree(status);

    kfree(buffer);



end;

{ Count free clusters by scanning the FAT sector by sector.
  Returns the number of free clusters (FAT entries == 0). }
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
    if (bootRecord^.sectorsize = 0) or (bootRecord^.FATSize = 0) then exit;

    fatStart := volume^.sectorStart + 1 + bootRecord^.rsvSectors;
    maxCluster := (bootRecord^.FATSize * bootRecord^.sectorsize) div 4;
    entriesPerSect := bootRecord^.sectorsize div 4;
    fatSectors := bootRecord^.FATSize;

    fatBuffer := puint32(kalloc(bootRecord^.sectorsize));
    freeCount := 0;

    for sectorIdx := 0 to fatSectors - 1 do begin
        if sectorIdx * entriesPerSect >= maxCluster then break;
        storagemanager.storage_read(volume^.device, fatStart + sectorIdx, 1, fatBuffer, nil, nil);
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

function identify_volume(volume : PStorage_Volume) : boolean;
var
    buffer     : puint32;
    bootRecord : PBootRecord;
begin
    push_trace('fat32.identify_volume');
    identify_volume := false;
    if volume^.device = nil then exit;
    if (volume^.device^.readCallback = nil) and (volume^.device^.readCallbackAsync = nil) then exit;

    buffer := puint32(kalloc(512));
    memset(uint32(buffer), 0, 512);

    storagemanager.storage_read(volume^.device, volume^.sectorStart + 1, 1, buffer, nil, nil);
    bootRecord := PBootRecord(buffer);

    if (bootRecord^.bsignature = $29) then begin
        identify_volume := true;
        volume^.freeSectors := countFreeFATClusters(volume, bootRecord) * bootRecord^.spc;
    end;

    kfree(buffer);
end;

procedure detect_volumes(disk : PStorage_Device);
var
    buffer : puint32;
    i : uint8;
    volume : PStorage_volume;
begin
    push_trace('fat32.detectVolumes()');

    buffer := puint32(kalloc(512));
    memset(uint32(buffer), 0, 512);

    { Read from sector 2 to check for FAT32 boot record }
    if (disk^.readCallback = nil) and (disk^.readCallbackAsync = nil) then begin
        syslog.writestringln('FAT32: detect_volumes: device has no read callback.');
        kfree(buffer);
        exit;
    end;

    storagemanager.storage_read(disk, 2, 1, buffer, nil, nil);

    if (puint32(buffer)[127] = $55AA) and (PBootRecord(buffer)^.bsignature = $29) then begin
        syslog.writestringln('FAT32: volume found!');
        volume := PStorage_volume(kalloc(sizeof(TStorage_Volume)));
        memset(uint32(volume), 0, sizeof(TStorage_Volume));
        volume^.device       := disk;
        volume^.sectorStart  := 1;
        volume^.sectorSize   := PBootRecord(buffer)^.sectorSize;
        volume^.sectorCount  := disk^.maxSectorCount;
        volume^.filesystem   := @filesystem;
        volume^.freeSectors  := countFreeFATClusters(volume, PBootRecord(buffer)) * PBootRecord(buffer)^.spc;
        volume^.isBootDrive  := false;

        volumemanager.register_volume(disk, volume);
    end;

    kfree(buffer);
end;

{ Read byteCount bytes from a file beginning at byte offset 'offset'.
  Returns the number of bytes actually read (may be less than byteCount if EOF reached).

  NOTE: This implementation reads sectors sequentially from the first cluster of the
  file, consistent with the existing readFile behaviour.  It does NOT follow the FAT
  chain between clusters \u2014 it assumes contiguous allocation.  This is acceptable for
  the initial streaming implementation.  A future improvement should cache the last
  visited (offset, cluster) pair in the open-file entry to make sequential chunked
  reads O(1) per call instead of O(n) in the FAT chain length. }
function readFileAtOffset(volume : PStorage_Volume; directory : pchar; fileName : pchar; offset : uint32; buffer : puint32; byteCount : uint32) : uint32;
var
    bootRecord      : PBootRecord;
    dirs            : PLinkedListBase;
    dir             : PDirectory;
    statusOut       : puint32;
    i               : uint32;
    exists          : boolean;
    cluster         : uint32;
    clusters        : PLinkedListBase;
    noClusters      : uint32;
    dataStart       : uint32;
    cleanFileName   : byteArray8;
    otherCFN        : byteArray8;
    tempdir         : PDirectory;
    namePart        : pchar;
    extPart         : pchar;
    readbuffer      : puint32;
    totalSectors    : uint32;
    startSector     : uint32;
    inSectorOffset  : uint32;
    destPos         : uint32;
    sectorIdx       : uint32;
    baseLBA         : uint32;
    bytesToCopy     : uint32;
    remaining       : uint32;
begin
    push_trace('fat32.readFileAtOffset.enter');
    readFileAtOffset := 0;
    exists := false;

    statusOut := puint32(kalloc(sizeof(uint32)));
    statusOut^ := 0;
    bootRecord := readBootRecord(volume);
    dirs := readDirectory(volume, directory, statusOut);
    dataStart := volume^.sectorStart + 1 + bootRecord^.FATSize + bootRecord^.rsvSectors;

    splitFileNameParts(fileName, namePart, extPart);

    if LL_size(dirs) > 0 then begin
        cleanFileName := cleanString(namePart, statusOut);
        for i := 0 to LL_Size(dirs) - 1 do begin
            tempdir := PDirectory(LL_get(dirs, i));
            otherCFN := cleanString(tempdir^.filename, statusOut);
            if compareByteArray8(cleanFileName, otherCFN) and matchExtension(tempdir^.fileExtension, extPart) then begin
                dir := tempdir;
                exists := true;
                statusOut^ := 0;
            end;
        end;
    end;

    kfree(void(namePart));
    kfree(void(extPart));

    if not exists then begin
        LL_Free(dirs);
        kfree(puint32(bootRecord));
        kfree(puint32(statusOut));
        push_trace('fat32.readFileAtOffset.notFound');
        exit;
    end;

    cluster    := uint32(dir^.clusterlow) or uint32(dir^.clusterhigh shl 16);
    clusters   := getFatChain(volume, cluster, bootRecord);
    noClusters := LL_size(clusters);

    { Total sectors spanned by this file (matches readFile formula) }
    totalSectors := noClusters * bootRecord^.spc + 1;

    { Sector within the file that contains the first byte of 'offset' }
    startSector    := offset div bootRecord^.sectorSize;
    inSectorOffset := offset mod bootRecord^.sectorSize;

    if startSector >= totalSectors then begin
        LL_Free(dirs);
        LL_Free(clusters);
        kfree(puint32(bootRecord));
        kfree(puint32(statusOut));
        exit;
    end;

    baseLBA    := dataStart + (cluster * bootRecord^.spc);
    readbuffer := puint32(kalloc(bootRecord^.sectorSize));
    destPos    := 0;
    remaining  := byteCount;
    sectorIdx  := 0;

    while (sectorIdx < totalSectors - startSector) and (remaining > 0) do begin
        storagemanager.storage_read(volume^.device, baseLBA + startSector + sectorIdx, 1, readbuffer, nil, nil);

        if sectorIdx = 0 then begin
            { First sector: skip inSectorOffset bytes at the start }
            bytesToCopy := bootRecord^.sectorSize - inSectorOffset;
            if bytesToCopy > remaining then bytesToCopy := remaining;
            util.memcpy(uint32(readbuffer) + inSectorOffset, uint32(buffer) + destPos, bytesToCopy);
        end else begin
            bytesToCopy := bootRecord^.sectorSize;
            if bytesToCopy > remaining then bytesToCopy := remaining;
            util.memcpy(uint32(readbuffer), uint32(buffer) + destPos, bytesToCopy);
        end;

        destPos   := destPos + bytesToCopy;
        remaining := remaining - bytesToCopy;
        sectorIdx := sectorIdx + 1;
    end;

    kfree(readbuffer);
    LL_Free(dirs);
    LL_Free(clusters);
    kfree(puint32(bootRecord));
    kfree(puint32(statusOut));
    readFileAtOffset := destPos;
    push_trace('fat32.readFileAtOffset.exit');
end;

procedure init();
begin
    push_trace('fat32.init()');
    filesystem.sName:= 'FAT32'; 
    filesystem.system_id:= $01; 
    filesystem.readDirCallback:= @readDirectoryGen;
    filesystem.createDirCallback:= @writeDirectoryGen;
    filesystem.createcallback:= @create_volume;
    filesystem.detectcallback:= @detect_volumes;
    filesystem.writecallback:= @writeFile;
    filesystem.readcallback := @readFile;
    filesystem.readOffsetCallback := @readFileAtOffset;
    filesystem.identifyCallback := @identify_volume;
    filesystem.deleteFileCallback := @deleteFile;
    filesystem.deleteDirCallback := @deleteDir;

    filesystemmanager.register_filesystem(@filesystem);
end;

end.