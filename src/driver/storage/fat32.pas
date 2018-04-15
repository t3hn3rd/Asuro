{ ************************************************
  * Asuro
  * Unit: Drivers/storage/fat32
  * Description: fat32 file system driver
  * 
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }

unit FAT32;

interface

uses
    console,
    storagemanagement,
    util,
    lmemorymanager,
    strings,
    lists,
    tracer;

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

    TDirectory = bitpacked record
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

implementation

function load(ptr : void) : boolean;
begin
    console.outputln('DUMMY DRIVER', 'LOADED.')
end;

function readBootRecord(volume : PStorage_volume) : TBootRecord; // need write functions for boot record!
var
    buffer : puint32;
begin
    buffer:= puint32(kalloc(512));
    volume^.device^.readcallback(volume^.device, volume^.sectorStart + 1, 1, buffer);
    readBootRecord:= PBootRecord(buffer)^;
    kfree(buffer);
end;

function readFat(volume : PStorage_volume; cluster : uint32): uint32;
var
    buffer      : puint32;
    bootRecord  : TBootRecord;
    fatSize     : uint32;
begin
    bootRecord := readBootRecord(volume);
    fatSize:= bootrecord.fatSize;
    buffer:= puint32(kalloc(fatSize));
    volume^.device^.readcallback(volume^.device, volume^.sectorStart + 2 + (cluster * 32 div volume^.sectorSize), 1, buffer);
    readFat:= buffer[cluster];
    kfree(buffer);
end;

procedure writeFat(volume : PStorage_volume; cluster : uint32; value : uint32); // untested, but should work
var
    buffer      : puint32;
    bootRecord  : TBootRecord;
    fatSize     : uint32;
begin
    bootRecord := readBootRecord(volume);
    fatSize:= bootrecord.fatSize;
    buffer:= puint32(kalloc(fatSize));
    volume^.device^.readcallback(volume^.device, volume^.sectorStart + 2 + (cluster * 32 div volume^.sectorSize), 1, buffer);
    buffer[cluster]:= value;
    volume^.device^.writeCallback(volume^.device, volume^.sectorStart + 2 + (cluster * 32 div volume^.sectorSize), 1, buffer);
    kfree(buffer);
end;


function readDirectory(volume : PStorage_volume; directory : pchar; listPtr : PLinkedListBase) : uint8; //returns: 0 = success, 1 = dir not exsist, 2 = not directory, 3 = error
var
    directories     : PLinkedListBase;
    rootTable       : PLinkedListBase;
    clusters        : PLinkedListBase;
    dirElm          : void;
    buffer          : puint32;
    bufferI         : puint32;
    bootRecord      : TBootRecord;
    clusterInfo     : uint32;
    cc              : uint32;
    clusterByteSize : uint32;
    fatSectorSize   : uint32;
    device          : PStorage_Device;
    i               : uint32;
    dirI            : uint32 = 0;
    str             : pchar;
    targetStr       : pchar;
    dir             : PDirectory;
begin
    push_trace('fat32.readDirectory');

    rootTable       := LL_New(sizeof(TDirectory));
    clusters        := LL_New(sizeof(uint32));
    directories     := stringToLL(directory, '/');
    bootRecord      := readBootRecord(volume);
    device          := volume^.device;
    clusterByteSize := bootrecord.spc * bootrecord.sectorSize;
    fatSectorSize   := bootrecord.fatSize;

    readDirectory:= 0;
    // if readFat(volume, bootrecord.rootCluster) = $FFFFFFF8 then begin
    //     buffer:= puint32(kalloc((bootrecord.spc * 512) + 1));
    //     volume^.device^.readcallback(volume^.device, volume^.sectorStart + 1 + (bootrecord.fatSize div 512) + (bootRecord.spc * bootRecord.rootCluster), bootrecord.spc, buffer);
    // end else if readFat(volume, bootrecord.rootCluster) <> $FFFFFFF7 then begin
    //     //need to read multiple clusters to get full directory table
    // end;


    cc:= bootrecord.rootCluster;

    while true do begin

        targetStr:= pchar(LL_Get(directories, dirI));

        //build list of clusters for current directory table
        while true do begin 
            console.writestring('cluster: ');
            console.writeintln(cc);
            clusterInfo:= readFat(volume, cc);
            console.writestring('info: ');
            console.writehexln(clusterInfo);
            if clusterInfo = $FFFFFFF7 then begin
                readDirectory:= 3; //ERROR
                break;
            end else if clusterInfo = $FFFFFFF8 then begin
                //last dir table cluster
                dirElm:= LL_Add(clusters);
                uint32(dirElm^):= cc;
                break;
            end else if clusterInfo = 0 then begin
                break;
            end else begin
                //dir is longer than one cluster
                dirElm:= LL_Add(clusters);
                uint32(dirElm^):= cc;
                cc:= clusterInfo;
            end;
        end;

        //load clusters into buffer
        buffer:= puint32(kalloc( (clusterByteSize * (LL_size(clusters) - 1)) + 1));
        bufferI := buffer;
        for i:= 0 to LL_size(clusters) - 1 do begin
            cc:= uint32(LL_Get(clusters, i)^);
            device^.readcallback(device, volume^.sectorStart + 1 + fatSectorSize + (bootRecord.spc * cc), bootrecord.spc, puint32(buffer + (i * clusterByteSize)) );
        end;

        if dirI = LL_size(directories) - 1 then break;

        //get elements in the directory table
        while true do begin
            dir:= PDirectory(bufferI);
            if dir^.fileName[0] = char(0) then break; //need to check if I have found the right directoy and set cc if not last
            if (dir^.attributes and $10) = $10 then begin // is a directory;
                str:= dir^.fileName;
                str[9]:= char(0);
                if stringEquals(str, targetStr) then begin //need to get current folder searching for
                    cc:= dir^.clusterLow;
                    cc:= cc or (dir^.clusterHigh shl 16);
                end;
            end;
            
            dirElm:= LL_Add(rootTable);
            PDirectory(dirElm)^:= PDirectory(bufferI)^;
            bufferI:= puint32(bufferI + 8);
        end;

        //set CC
        dirI += 1;
    end;

    while true do begin
        dir:= PDirectory(bufferI);
        if dir^.fileName[0] = char(0) then break; //need to check if I have found the right directoy and set cc if not last
        dirElm:= LL_Add(rootTable);
        PDirectory(dirElm)^:= PDirectory(bufferI)^;
        bufferI:= puint32(bufferI + 8);
    end;

    kfree(buffer);
    listPtr := rootTable;

    // while true do begin // I need to be inside another loop
    //     if PDirectory(buffer)^.fileName[0] = char(0) then break;
    //     dirElm:= LL_Add(rootTable);
    //     PDirectory(dirElm)^:= PDirectory(buffer)^;

    //     console.writestring('FileName: ');
    //     console.writechar(PDirectory(buffer)^.fileName[0]);
    //     //console.writecharln(PDirectory(buffer)^.fileName[1]);
    //     buffer:= puint32(buffer + 8);
    // end;

    pop_trace();
end;

function writeDirectory(volume : PStorage_volume; directory : pchar) : uint8;
var
    dirList      : PLinkedListBase;
    str          : pchar;
    str2         : pchar;
    i            : uint32 = 0;
    ii           : uint32;
    buffer       : puint32;
    foundCluster : boolean = false;
    emptyCluster : uint32;
    targetDirectory : TDirectory;
begin
    dirList:= stringToLL(directory, '/');
    buffer:= puint32(kalloc(sizeof(volume^.sectorSize)));
    
    //find un allocated cluster
    while not foundCluster do begin
        volume^.device^.readcallback(volume^.device, volume^.sectorStart + 2 + (i * 32 div volume^.sectorSize), 1, buffer);
        for ii:=0 to 15 do begin
            if puint32(buffer + ii)^ = 0 then begin //found unallocated cluster
                emptyCluster:= (i * 16) + ii;
                foundCluster:= true;
            end;
        end;
        i+= 1;
    end;
    kfree(buffer);

    //write fat
    writeFat(volume, emptyCluster, $FFFFFFF8);

    //find directory table
    for i:=0 to LL_size(dirList) - 2 do begin
        str2:= pchar( puint32(LL_Get(dirList, i))^ );
        str:= stringConcat(str, str2);    
    end;

    writeDirectory:= readDirectory(volume, str, dirList);
    targetDirectory:= PDirectory(LL_Get(dirList, 0))^;

    //insert table entree
    //write new directory table at emptyCluster
end;

procedure readFile(volume : PStorage_volume; directory : pchar; byteCount : uint32; buffer : puint32);
begin

end;
//need to be able to increase no of clusted used by a directory
procedure writeFile(volume : PStorage_volume; directory : pchar; byteCount : uint32; buffer : puint32);
begin

end;

procedure init;
begin
    filesystem.sName:= 'FAT32'; 
    filesystem.writecallback:= @writeFile;
    filesystem.readcallback:= @readFile;
    filesystem.createcallback:= @create_volume;
    filesystem.detectcallback:= @detect_volumes; 
    storagemanagement.register_filesystem(@filesystem);
end;

procedure create_volume(disk : PStorage_Device; sectors : uint32; start : uint32; config : puint32);
var
    i : uint8;
    bootRecord : TBootRecord;
    buffer : puint32;
    asuroArray : byteArray8 = ('A','S','U','R','O',' ','V','1');
    fatArray : byteArray8 = ('F','A','T','3','2',' ',' ',' ');
    tmpArray : byteArray8;

    fatStart : uint32;
    dataStart: uint32;
    
begin
    buffer:= puint32(kalloc(512));

    bootrecord.jmp2boot:= $00; // TODO what ahppens here???
    bootRecord.OEMName:= asuroArray;
    bootrecord.sectorsize:= disk^.sectorSize;
    bootrecord.spc:= config^;
    console.writeintln(uint32(config^));
    bootrecord.rsvSectors:= 32; //Is this acceptable?
    bootrecord.numFats:= 1;
    bootrecord.numDirEnt:= 0;
    bootRecord.numSectors:= 0;
    bootrecord.mediaDescp:= $F8;
    bootrecord.sectorsPerFat:= 0;
    bootRecord.sectorsPerTrack:= 0;
    bootRecord.heads:= 0;
    bootRecord.hiddenSectors:= start;
    bootRecord.manySectors:= sectors;

    //BootRecord.FATSize:= ((sectors DIV PFatVolumeInfo(config)^.sectorsPerCluster) * 16 DIV disk^.sectorSize);
    //BootRecord.FATSize:= ((sectors DIV 4) * 2 DIV disk^.sectorSize);
    BootRecord.FATSize:= ((sectors DIV bootrecord.spc) * 4) DIV 512;
    //sectors div spc, *
    BootRecord.flags:= 0; //1 shl 7 for mirroring
    BootRecord.FATVersion:= 0;
    BootRecord.rootCluster:= start + 2; // can be changed if needed.
    BootRecord.FSInfoCluster:= start + 1 + bootrecord.fatSize; //TODO need FSINFO
    BootRecord.driveNumber:= $80;
    //BootRecord.reserved0:=0;
    //BootRecord.reserved1:=0;
    BootRecord.volumeID := 53424; //need random number generator
    //BootRecord.volumeLabel[0] := 0; //needs to be set later !!!
    BootRecord.bsignature:= $29;
    BootRecord.identString:= fatArray;

    buffer:= @bootrecord;
    puint32(buffer + (127))^:= $55AA; //end marker

    disk^.writeCallback(disk, start + 1, 1, buffer);

    dataStart:= (bootrecord.fatSize) + 1 + start;

    //TODO FSINFO struct

    //write fat
    buffer := puint32(kalloc((sectors DIV bootrecord.spc) * 4));
    memset(uint32(buffer), 0, (sectors DIV bootrecord.spc) * 4);
    puint32(buffer + bootRecord.rootCluster - 1)^:= $FFFFFFF7; //make space for fsinfo, by setting this field to bad.
    puint32(buffer + bootRecord.rootCluster)^:= $FFFFFFF8; //root directory table cluster, currently root is only 1 cluster long
    disk^.writeCallback(disk, start + 2, (sectors DIV bootrecord.spc) * 4, buffer); 
    //disk^.writeCallback(disk, start + 2 + (sectors Div bootrecord.sectorsPerCluster DIV 512), sectors DIV bootrecord.sectorsPerCluster, buffer);
    kfree(buffer);

    //setup root directory
    buffer:= puint32(kalloc(512));
    memset(uint32(buffer), 0, 512);

    tmpArray[0]:= '.';
    tmpArray[1]:= ' ';
    tmpArray[2]:= ' ';
    tmpArray[3]:= ' ';
    tmpArray[4]:= ' ';
    tmpArray[5]:= ' ';
    tmpArray[6]:= ' ';
    tmpArray[7]:= ' ';

    PDirectory(buffer)^.fileName:= tmpArray;
    PDirectory(buffer)^.attributes:= $10; // is directory
    PDirectory(buffer)^.clusterLow:= 2; //my cluster location

    tmpArray[1]:= '.';
    PDirectory(buffer + (sizeof(TDirectory) DIV 4 ) )^.fileName:= tmpArray;
    PDirectory(buffer + (sizeof(TDirectory) DIV 4) )^.attributes:= $08; // volume id
    PDirectory(buffer + (sizeof(TDirectory) DIV 4) )^.clusterLow:= 2; //my cluster location

    tmpArray[0]:= 'M';
    tmpArray[1]:= 'U';
    tmpArray[2]:= 'S';
    tmpArray[3]:= 'I';
    tmpArray[4]:= 'C';
    PDirectory(buffer + (sizeof(TDirectory) * 2 DIV 4 ) )^.fileName:= tmpArray;
    PDirectory(buffer + (sizeof(TDirectory) * 2 DIV 4) )^.attributes:= $10; // volume id
    PDirectory(buffer + (sizeof(TDirectory) * 2 DIV 4) )^.clusterLow:= 2; //my cluster location

    disk^.writeCallback(disk, dataStart + (bootRecord.spc * bootrecord.rootCluster), 1, buffer);

end;

procedure detect_volumes(disk : PStorage_Device);
var
    buffer : puint32;
    i : uint8;
    volume : PStorage_volume;
begin
    push_trace('detect volume');
    volume:= PStorage_volume(kalloc(sizeof(TStorage_Volume)));
    //check first address for MBR
    //if found then add volume and use info to see if there is another volume
    buffer := puint32(kalloc(512));
    memset(uint32(buffer), 0, 512);
    disk^.readcallback(disk, 2, 1, buffer);

    if (puint32(buffer + (127))^ = $55AA) and (PBootRecord(buffer)^.bsignature = $29) then begin
        console.writestringln('FAT32: volume found!');
        volume^.device:= disk;
        volume^.sectorStart:= 1;
        volume^.sectorSize:= PBootRecord(buffer)^.sectorSize;
        volume^.freeSectors:= 1000000; //TODO implement get free sectors need FSINFO implemented first
        volume^.filesystem := @filesystem;
        storagemanagement.register_volume(disk, volume);
    end;

    readDirectory(volume, 'hello/word', nil);
    pop_trace();
end;

end.