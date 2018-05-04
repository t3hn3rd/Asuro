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

    byteArray8 = array[0..7] of char;

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
begin
    buffer:= puint32(kalloc(bootRecord^.sectorsize));
    memset(uint32(buffer), 0, bootRecord^.sectorsize);
    fatEntriesPerSector:= bootRecord^.sectorsize div 4;
    sectorLocation:= cluster div fatEntriesPerSector + (volume^.sectorStart + 1 + bootRecord^.rsvSectors);

    volume^.device^.readcallback(volume^.device, sectorLocation, 1, buffer);
            //console.writehexln(uint32(buffer[1]));

            //console.writeint(cluster);
            //console.writestring(' - (');
            //console.writeint(sectorLocation);
            //console.writestring(' * ');
            //console.writeint(fatEntriesPerSector);
            //console.writestringln(') ');
        console.redrawWindows();
    readFat:= buffer[cluster - ((cluster - 1) * fatEntriesPerSector)];

    kfree(buffer);
end;

procedure writeFat(volume : PStorage_volume; cluster : uint32; value : uint32; bootRecord : PBootRecord);
var
    buffer              : puint32;
    fatEntriesPerSector : uint32;
    sectorLocation      : uint32;
begin
    buffer:= puint32(kalloc(bootRecord^.sectorsize));
    memset(uint32(buffer), 0, bootRecord^.sectorsize);
    fatEntriesPerSector:= bootRecord^.sectorsize div 4;
    sectorLocation:= cluster div fatEntriesPerSector + (volume^.sectorStart + 1 + bootRecord^.rsvSectors);

    volume^.device^.readcallback(volume^.device, sectorLocation, 1, buffer);
    buffer[cluster - (sectorLocation * fatEntriesPerSector)]:= value;
    volume^.device^.writecallback(volume^.device, sectorLocation, 1, buffer);

    kfree(buffer);
end;

function getFatChain(volume : PStorage_volume; cluster : uint32; bootRecord : PBootRecord) : PLinkedListBase;
var
    currentCluster      : uint32;
    currentClusterValue : uint32;
    clusters            : PLinkedListBase;
    dirElm              : puint32;
begin
    clusters:= LL_New(sizeof(uint32));
    currentCluster:= cluster;
    currentClusterValue:= cluster;

    while true do begin
        currentClusterValue:= readFat(volume, currentClusterValue, bootRecord);
        //while true do begin end;

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

        console.redrawWindows();
    end;

    redrawWindows();
    console.writestringln('------------------');
    console.writehexln(uint32(clusters));
    console.writeintln(LL_size(clusters));
    getFatChain:= clusters;
    exit;
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
    clusters := LL_New(sizeof(uint32));

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
    directories:= LL_New(sizeof(TDirectory));

    clusters:= PLinkedListBase(getFatChain(volume, cluster, bootRecord));

        console.writehexln(uint32(clusters));
        console.writehexln(uint32(LL_Get(clusters, 0)^));
        console.redrawWindows();

        //while true do begin end;

    buffer:= puint32(kalloc( (bootRecord^.sectorSize * bootRecord^.spc) * LL_size(clusters) ));
    memset(uint32(buffer), 0, (bootRecord^.sectorSize * bootRecord^.spc) * LL_size(clusters) );

    dataStart:= volume^.sectorStart + 1 + bootRecord^.rsvSectors + bootRecord^.FATSize;

    for i:=0 to LL_size(clusters) - 1 do begin
        console.writestringln('LOOP');
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

    getDirEntries:= directories;
    LL_Free(clusters);
    kfree(buffer);
end;

//need to find out why having multiple dir stings isn't working, maybe the ls command?
function readDirectory(volume : PStorage_volume; directory : pchar; status : puint32) : PLinkedListBase; //returns: 0 = success, 1 = dir not exsist, 2 = not directory, 3 = error
var
    bootRecord       : PBootRecord;
    directoryStrings : PLinkedListBase;
    directories      : PLinkedListBase;
    cluster          : uint32;
    i                : uint32;
    ii               : uint32 = 0;
    dirEntry         : PDirectory;
begin
    bootRecord:= readBootRecord(volume);
    directoryStrings:= stringToLL(directory, '/');

    directories:= getDirEntries(volume, bootRecord^.rootCluster, bootRecord);


    if LL_size(directoryStrings) > 0 then begin

            console.writeintln(123123);
            redrawWindows();

        for i:=0 to LL_Size(directoryStrings) - 1 do begin
            ii:=0;
            while true do begin
                if ii > LL_Size(directories) - 1 then break;
                dirEntry:= PDirectory(LL_Get(directories, ii));

                if stringEquals( @dirEntry^.fileName, pchar(LL_Get(directoryStrings, i)) ) then begin
                    cluster:= dirEntry^.clusterLow;
                    cluster:= cluster and (dirEntry^.clusterHigh shl 16);
                    break;
                end;
                ii+=1;
            end;

            if i = LL_Size(directoryStrings) - 1 then break;
            
            LL_Free(directories);
            directories:= getDirEntries(volume, cluster, bootRecord);
        end;
    end else begin
            console.writeintln(LL_Size(directories)); //nneds to be fixed currently only 1
            redrawWindows();

        while true do begin
            if ii > LL_Size(directories) - 1 then break;
            dirEntry:= PDirectory(LL_Get(directories, ii));
            ii+=1;
        end;
    end;

    readDirectory:= directories;

    LL_Free(directoryStrings);
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
    rootCluster   : uint32 = 1;
begin
    push_trace('fat32.create_volume()');
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
    bootRecord^.rsvSectors      := 32; //TODO sanity check
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
        if i > FATSize - 4 then break;
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

    //Temp for testing other functions
    PDirectory(buffer)[2].fileName   := fatArray; 
    PDirectory(buffer)[2].attributes := $10;
    PDirectory(buffer)[2].clusterLow := 1;
    //

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
        redrawWindows();
    //sleep(1);

    volume:= PStorage_volume(kalloc(sizeof(TStorage_Volume)));
    //check first address for MBR
    //if found then add volume and use info to see if there is another volume
    buffer := puint32(kalloc(512));
    memset(uint32(buffer), 0, 512);
    disk^.readcallback(disk, 2, 1, buffer);

    if (puint32(buffer)[127] = $55AA) and (PBootRecord(buffer)^.bsignature = $29) then begin
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
    filesystem.readDirCallback:= @readDirectory;
    filesystem.createcallback:= @create_volume;
    filesystem.detectcallback:= @detect_volumes;
    storagemanagement.register_filesystem(@filesystem);
end;

end.