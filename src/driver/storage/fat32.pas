{ ************************************************
  * Asuro
  * Unit: Drivers/storage/fat32
  * Description: fat32 file system driver
  * 
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }

  {
      Todo in the future, optimise by prvoiding batch read/write commands

  }

unit FAT32;

interface

uses
    console,
    storagemanagement,
    util, terminal,
    lmemorymanager,
    strings,
    lists,
    tracer,
    serial,
    rtc;

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

    TDirectory = packed record
        fileName      : array[0..7] of char;
        fileExtension : array[0..2] of char;
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
procedure create_volume(disk : PStorage_Device; sectors : uint32; start : uint32; config : puint32);
procedure detect_volumes(disk : PStorage_Device);
//function writeDirectory(volume : PStorage_volume; directory : pchar; attributes : uint32) : uint8; // need to handle parent table cluster overflow, need to take attributes
//function readDirectory(volume : PStorage_volume; directory : pchar; listPtr : PLinkedListBase) : uint8; //returns: 0 = success, 1 = dir not exsist, 2 = not directory, 3 = error


implementation

procedure STOS(str : PChar);
var
    i : uint32;

begin
    for i:=0 to StringSize(str)-1 do begin
        serial.send(COM1, uint8(str[i]), 100);
    end;
    serial.send(COM1, 13, 100);
end;

function load(ptr : void) : boolean;
begin
    console.outputln('DUMMY DRIVER', 'LOADED.')
end;

function cleanString(str : pchar; status : puint32) : byteArray8;
var
    i : uint32;
    ii: uint32;
begin
    //cleanString:= pchar(kalloc(sizeof(10)));
    for i:=0 to 7 do begin
        if str[i] = char(0) then begin
            for ii:=i to 7 do begin
                cleanString[ii]:= ' ';
            end;
            break;
        end else begin
            // if (str[i] = '/') or (str[i] = ',') then begin
            //     status:= 3;
            // end;
            cleanString[i]:= str[i];
        end;
    end;

end;    

function readBootRecord(volume : PStorage_volume) : PBootRecord; // need write functions for boot record!
var
    buffer : puint32;
begin
    buffer:= puint32(kalloc(512));
    memset(uint32(buffer), 0, 512);
    volume^.device^.readcallback(volume^.device, volume^.sectorStart + 1, 1, buffer);
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
    push_trace('fat32.readFat');
    buffer:= puint32(kalloc(bootRecord^.sectorsize));
    memset(uint32(buffer), 0, bootRecord^.sectorsize);
    fatEntriesPerSector:= bootRecord^.sectorsize div 4;
    sectorLocation:= cluster div fatEntriesPerSector;
    dataStart:= (volume^.sectorStart + 1 + bootRecord^.rsvSectors);

    volume^.device^.readcallback(volume^.device, datastart + sectorLocation, 1, buffer); 
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
    push_trace('fat32.WriteFat');
    buffer:= puint32(kalloc(bootRecord^.sectorsize));
    memset(uint32(buffer), 0, bootRecord^.sectorsize);
    fatEntriesPerSector:= bootRecord^.sectorsize div 4;
    sectorLocation:= cluster div fatEntriesPerSector;
    dataStart:= (volume^.sectorStart + 1 + bootRecord^.rsvSectors);

    volume^.device^.readcallback(volume^.device, dataStart + sectorLocation, 1, buffer);
    buffer[cluster - (sectorLocation * fatEntriesPerSector)]:= value;
    volume^.device^.writecallback(volume^.device, dataStart + sectorLocation, 1, buffer);

    kfree(buffer);
end;

function getFatChain(volume : PStorage_volume; cluster : uint32; bootRecord : PBootRecord) : PLinkedListBase;
var
    currentCluster      : uint32;
    currentClusterValue : uint32;
    clusters            : PLinkedListBase;
    dirElm              : puint32;
begin
    push_trace('fat32.getFatChain');
    clusters:= LL_New(sizeof(uint32));
    currentCluster:= cluster;
    currentClusterValue:= cluster;

    while true do begin
        currentClusterValue:= readFat(volume, currentClusterValue, bootRecord);

        if currentClusterValue = $FFFFFFF7 then begin
            break;
        end else if currentClusterValue = $FFFFFFF8 then begin
            dirElm:= LL_add(clusters);
            dirElm^:= currentCluster;
            break;
        end else if currentClusterValue = 0 then begin
            break;
        end else begin
            dirElm:= LL_add(clusters);
            dirElm^:= currentCluster;
        end;

        currentCluster+=1;
    end;

    getFatChain:= clusters;
end;

//TODO improve with FSINFO
function findFreeClusters(volume : PStorage_volume; amount : uint32; bootRecord : PBootRecord) : PLinkedListBase;
var
    i                   : uint32 = 2;
    currentClusterValue : uint32;
    currentAmount       : uint32 = 0;
    clusters            : PLinkedListBase;
    dirElm              : puint32;
begin
    push_trace('fat32.findFreeClusters');
    clusters := LL_New(8);

    while true do begin

        if currentAmount = amount then break;

        currentClusterValue:= readFat(volume, i, bootRecord);

        if currentClusterValue = 0 then begin
            dirElm:= LL_add(clusters);
            dirElm^:= i;
            currentAmount+=1;
        end;

        i+=1;
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
    datastart : uint32;
    sectorLocation : uint32;
    dirElm : puint32;
begin
    push_trace('fat32.getDirEntries');
    directories:= LL_New(sizeof(TDirectory));

    clusters:= PLinkedListBase(getFatChain(volume, cluster, bootRecord));
    buffer:= puint32(kalloc( (bootRecord^.sectorSize * bootRecord^.spc) * LL_size(clusters) ));
    memset(uint32(buffer), 0, (bootRecord^.sectorSize * bootRecord^.spc) * LL_size(clusters) );

    dataStart:= volume^.sectorStart + 1 + bootRecord^.rsvSectors + bootRecord^.FATSize;

    for i:=0 to LL_size(clusters) - 1 do begin
        sectorLocation:= bootRecord^.spc * (i + cluster);
        bufferI:= @buffer[i * (bootRecord^.spc * bootRecord^.sectorSize)];
        volume^.device^.readcallback(volume^.device, datastart + sectorLocation, bootRecord^.spc, bufferI); //datastart + spc(i + cluster)
    end;

    i:=0;
    while true do begin
        if PDirectory(buffer)[i].fileName[0] = char(0) then break;

        dirElm:= LL_Add(directories);
        PDirectory(dirElm)^:= PDirectory(buffer)[i];
        i+=1;
    end;

    getDirEntries:= directories; //get last .
    LL_Free(clusters);
    kfree(buffer);
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
    i     : uint32;
    entry : PDirectory_Entry;
    dir   : PDirectory;
    dirElm: puint32;
begin
    push_trace('fat32.fat2GenericEntries');
    puint32(entry) := kalloc(sizeof(TDirectory_Entry));
    fat2GenericEntries:= LL_New(sizeof(TDirectory_Entry));

    if LL_size(list) > 0 then begin //TODO

        for i:= 0 to LL_Size(list) - 1 do begin
            dir := PDirectory(LL_get(list, i));
            entry^.fileName:= pchar(dir^.fileName);
            entry^.extension:= pchar(dir^.fileExtension);

            if dir^.attributes = $10 then begin
                entry^.entryType:= TDirectory_Entry_Type.directoryEntry;
            end else begin //TODO add mount type
                entry^.entryType:= TDirectory_Entry_Type.fileEntry;
            end;

            //add to list
            dirElm:= LL_add(fat2GenericEntries);
            PDirectory_Entry(dirElm)^:= entry^;
        end;
    end;

    kfree(puint32(list));
    kfree(puint32(entry));
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
    push_trace('fat32.readDirectory');
    status^:= 0;
    bootRecord:= readBootRecord(volume);
    directoryStrings:= LL_fromString(directory, '/');
    directories:= getDirEntries(volume, bootRecord^.rootCluster, bootRecord);

    if LL_size(directoryStrings) > 0 then begin
        for i:=0 to (LL_Size(directoryStrings) ) do begin /// maybe -1 will work
            ii:=0;

            while true do begin
                if ii > LL_Size(directories) - 1 then begin
                    status^:= 1;
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

    statusOut^:= status^;
    LL_Free(directoryStrings);
    kfree(puint32(bootRecord));
end;

function readDirectoryGen(volume : PStorage_volume; directory : pchar; status : puint32) : PLinkedListBase; //returns: 0 = success, 1 = dir not exsist, 2 = not directory, 3 = invalid name, 4= already exists
begin
    readDirectoryGen:= fat2GenericEntries(readDirectory(volume, directory, status));
end;

//need to allow for setting file extension
function writeDirectory(volume : PStorage_volume; directory : pchar; dirName : pchar; attributes : uint32; statusOut : puint32; fileExtension : pchar) : uint32; // need to handle parent table cluster overflow, need to take attributes
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
begin
    push_trace('fat32.writeDirectory');
    status:= puint32(kalloc(sizeof(uint32)));
    status^:= 0;

    directories:= readDirectory(volume, directory, status); 

    if(LL_size(directories) > 1) then begin
        for i:=0 to LL_Size(directories) - 1 do begin
            if compareByteArray8( pchar(PDirectory(LL_get(directories, i))^.fileName), cleanString( dirName , status)) then begin
                status^:= 4;
            end;
        end;
    end;

    bootRecord:= readBootRecord(volume);
    datastart:= volume^.sectorStart + 1 + bootRecord^.FATSize + bootRecord^.rsvSectors;

    if status^ = 0 then begin

        parentDirectory:= PDirectory(LL_Get(directories, 0));
        parentCluster:= uint32(parentDirectory^.clusterlow) or uint32(parentDirectory^.clusterhigh shl 16);
        //TODO check if this cluster is full, if so allocate new cluster

        clusters:= findFreeClusters(volume, 1, bootRecord); 
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
            volume^.device^.writecallback(volume^.device, dataStart + (cluster * bootRecord^.spc), 1, buffer);

            //write fat
            writeFat(volume, cluster, $FFFFFFF8, bootRecord);
        end;
        memset(uint32(buffer), 0, bootRecord^.sectorSize);
        //calculate write cluster using directories and parentCluster
        sectorLocation:= LL_size(directories) * sizeof(TDirectory) div bootRecord^.sectorSize;
        sectorLocation:= sectorLocation + (parentCluster * bootRecord^.spc);

        //dataOffset:= datastart + ( (LL_size(directories) * sizeof(PDirectory)) - (sizeUsed * bootRecord^.sectorSize));
        volume^.device^.readcallback(volume^.device, dataStart + sectorLocation, 1, buffer);

        //construct my dir entry
        bufferPointer:= @PDirectory(buffer)[LL_size(directories)];
        bufferPointer^.fileName:= cleanString(dirName, status);
        bufferPointer^.attributes:= attributes;
        //if attributes = 0 then bufferPointer^.fileExtension:= fileExtension;
        bufferPointer^.clusterLow:= cluster;
        bufferPointer^.clusterHigh:= uint16((cluster shr 16) and $0000FFFF);

        writeDirectory:= cluster;

        //write to disk
        volume^.device^.writecallback(volume^.device, dataStart + sectorLocation, 1, buffer);
        kfree(buffer);
    end;

    statusOut^:= status^;
    kfree(puint32(bootRecord));
    //LL_Free(directories); // page fault on free, possible memory leak now?
    push_trace('writedirectory.end');

end;

procedure writeDirectoryGen(volume : PStorage_volume; directory : pchar; dirName : pchar; attributes : uint32; statusOut : puint32); // need to handle parent table cluster overflow, need to take attributes
begin
    writeDirectory(volume, directory, dirName, attributes, statusOut, '');
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

    i : uint32;
    status : puint32;
begin
    push_trace('fat32.writefile');
    status:= kalloc(4);
    bootRecord:= readBootRecord(volume);
    device:= volume^.device;
    directories:= readDirectory(volume, directory, statusOut);
    sectorCount:= (byteCount div bootRecord^.sectorSize) + 1;
    datastart:= volume^.sectorStart + 1 + bootRecord^.FATSize + bootRecord^.rsvSectors;


    for i:=0 to LL_size(directories) - 1 do begin
        dir:= PDirectory(LL_get(directories, i));
        if (dir^.fileName = entry^.fileName) and (dir^.fileExtension = entry^.extension) then begin
            exists:= true;
            break;
        end;
    end;

    push_trace('writefile.1');

    if exists then begin
        startCluster:= uint32(dir^.clusterlow) or uint32(dir^.clusterhigh shl 16);
        clusters:= getFatChain(volume, startCluster, bootRecord); //check no clusters and check if needs to be more or less, add/remove clusters
        clusterCount := LL_size(clusters);

        if (clusterCount * bootRecord^.spc) > sectorCount then begin //shrink
            clusterDifference:= clusterCount - (sectorCount div bootRecord^.spc);
            for i:= (clusterCount - clusterDifference) + 1 to clusterCount do begin //free unused clusters
                writeFat(volume, startCluster + i, 0, bootRecord);
            end;
            writeFat(volume, startCluster + (clusterCount - clusterDifference), $FFFFFFF8, bootRecord); // add new cluster terminator
            //change last entry to terminator.
        end else if (clusterCount * bootRecord^.spc) < sectorCount then begin //expand
            clusterDifference:= (sectorCount div bootRecord^.spc) - clusterCount;
            LL_Free(clusters);
            clusters:= findFreeClusters(volume, clusterDifference, bootRecord);
            for i:= clusterCount to clusterCount + clusterDifference - 1 do begin
                writeFat(volume, startCluster + i, startCluster + i + 1, bootRecord);
            end;
                writeFat(volume, startcluster + clusterCount + clusterDifference, $FFFFFFF8, bootRecord);
        end else begin //nothing
            clusterDifference:= 0;
        end;

    end else begin
        push_trace('writefile.1.2.1');

        startCluster:= writeDirectory(volume, directory, entry^.fileName, 0, status, entry^.extension);
        clusterDifference:= (byteCount div bootRecord^.sectorsize) - 1;
            push_trace('writefile.1.2.2');

        for i:= startcluster to startCluster + clusterDifference - 1 do begin
            writeFat(volume, i, i + 1, bootRecord);
        end;
                push_trace('writefile.1.2.3');

        writeFat(volume, startcluster + clusterDifference, $FFFFFFF8, bootRecord);
        //setup fat chain 
    end;

    push_trace('writefile.2');

    iterations:= (bytecount div bootRecord^.sectorSize) div 4;

    for i:=0 to byteCount div bootRecord^.sectorSize do begin
        bufferPointer:= @buffer[i * uint32(bootRecord^.sectorsize * 4)];
        volume^.device^.writecallback(volume^.device, dataStart + startCluster, 4, bufferPointer);
    end;

    kfree(puint32(bootRecord));
end;

procedure create_volume(disk : PStorage_Device; sectors : uint32; start : uint32; config : puint32);
var
    buffer     : puint32;
    zeroBuffer : puint32;
    bootRecord : PBootRecord;
    dataStart  : uint32;
    fatStart   : uint32;
    FATSize    : uint32;
    i          : uint32 = 0;

    asuroArray    : byteArray8 = ('A','S','U','R','O',' ','V','1');
    fatArray      : byteArray8 = ('F','A','T','3','2',' ',' ',' ');
    thisArray     : byteArray8 = ('.',' ',' ',' ',' ',' ',' ',' ');
    parentArray   : byteArray8 = ('.','.',' ',' ',' ',' ',' ',' ');

    asuroFileArray     : byteArray8 = ('A','S','U','R','O',' ',' ',' ');
    mountFileArray     : byteArray8 = ('M','O','U','N','T',' ',' ',' ');
    programFileArray   : byteArray8 = ('P','R','O','G','R','A','M','S');
    rootCluster   : uint32 = 1;
begin
    push_trace('fat32.create_volume()');

    // zeroBuffer:= puint32(kalloc( disk^.sectorSize * 4 ));
    // memset(uint32(zeroBuffer), 0, disk^.sectorSize * 4);

    // while true do begin
    //     if i > sectors then break;
    //     disk^.writecallback(disk, 1 + i, 1, zeroBuffer);
    //     i+=1;
    // end;
    // kfree(zeroBuffer);

    //fat32 structure
    (* BootRecord            *)
    (* reserved sectors      *)
    (* File Allocation Table *)
    (* Data Area             *)
    
    buffer:= puint32(kalloc(sizeof(TBootRecord)));
    memset(uint32(buffer), 0, sizeof(TBootRecord));
    bootRecord:= PBootRecord(buffer);

    FATSize:= ((sectors div config^) * 4) div disk^.sectorsize;

    bootRecord^.jmp2boot        := $0; //TODO impliment boot jump
    bootRecord^.OEMName         := asuroArray;
    bootRecord^.sectorSize      := disk^.sectorsize;
    bootRecord^.spc             := config^;
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

    puint32(buffer)[127]:= $55AA;

    disk^.writecallback(disk, start + 1, 1, buffer);

    fatStart:= start + 1 + bootRecord^.rsvSectors;
    dataStart:= fatStart + bootRecord^.FATSize;

    zeroBuffer:= puint32(kalloc( disk^.sectorSize * 4 ));
    memset(uint32(zeroBuffer), 0, disk^.sectorSize * 4);

    while true do begin
        if i > FATSize DIV 4 then break;
        disk^.writecallback(disk, fatStart + i, 4, zeroBuffer);
        i+=4;
    end;

    kfree(buffer);
    kfree(zeroBuffer);

    buffer:= puint32(kalloc(disk^.sectorSize));
    memset(uint32(buffer), 0, disk^.sectorSize);

    puint32(buffer)[0]:= $FFFFFFF8; //fsinfo
    puint32(buffer)[1]:= $FFFFFFF8; //root cluster

    disk^.writecallback(disk, fatStart, 1, buffer);

    kfree(buffer);

    buffer:= puint32(kalloc(disk^.sectorsize));
    memset(uint32(buffer), 0, disk^.sectorsize);

    PDirectory(buffer)[0].fileName   := thisArray;
    PDirectory(buffer)[0].attributes := $08;
    PDirectory(buffer)[0].clusterLow := 1;

    PDirectory(buffer)[1].fileName   := parentArray;
    PDirectory(buffer)[1].attributes := $10;
    PDirectory(buffer)[1].clusterLow := 1;
    
    disk^.writecallback(disk, dataStart + (config^ * rootCluster), 1, buffer);

    kfree(buffer);

end;

procedure detect_volumes(disk : PStorage_Device);
var
    buffer : puint32;
    i : uint8;
    volume : PStorage_volume;

    dir : PDirectory;
    dirs : PLinkedListBase;
begin
    push_trace('fat32.detectVolumes()');
    console.writeintln(2);
    redrawWindows();

    volume:= PStorage_volume(kalloc(sizeof(TStorage_Volume)));
    //check first address for MBR
    //if found then add volume and use info to see if there is another volume
    buffer := puint32(kalloc(512));
    memset(uint32(buffer), 0, 512);
    disk^.readcallback(disk, 2, 1, buffer);

        console.writeintln(3);
    redrawWindows();

    if (puint32(buffer)[127] = $55AA) and (PBootRecord(buffer)^.bsignature = $29) then begin //TODO partition table
        console.writestringln('FAT32: volume found!');
        volume^.device:= disk;
        volume^.sectorStart:= 1;
        volume^.sectorSize:= PBootRecord(buffer)^.sectorSize;
        volume^.freeSectors:= 1000000; //TODO implement get free sectors need FSINFO implemented first
        volume^.filesystem := @filesystem;
        storagemanagement.register_volume(disk, volume);
    end;

    kfree(buffer);
end;

procedure init();
begin
    push_trace('fat32.init()');
    filesystem.sName:= 'FAT32'; 
    filesystem.readDirCallback:= @readDirectoryGen;
    filesystem.createDirCallback:= @writeDirectoryGen;
    filesystem.createcallback:= @create_volume;
    filesystem.detectcallback:= @detect_volumes;
    filesystem.writecallback:= @writeFile;

    storagemanagement.register_filesystem(@filesystem);
end;

end.