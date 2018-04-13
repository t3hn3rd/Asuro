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
    console, storagemanagement, util, lmemorymanager, strings;

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
        fileExtension : ubit24;
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
        FATBaseAddress : uint32;
        RootDirectory  : uint32;
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

procedure readDirectory(volume : PStorage_volume; directory : pchar; buffer : puint32);
begin
    //get location of first directory entre
    
    //check if it takes up more than one cluster
    //read all entries
end;

procedure writeDirectory(volume : PStorage_volume; directory : pchar; buffer : puint32);
begin

end;

procedure readFile(volume : PStorage_volume; directory : pchar; byteCount : uint32; buffer : puint32);
begin

end;

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
    bootrecord.spc:= PFatVolumeInfo(config)^.sectorsPerCluster;
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
    BootRecord.FATSize:= ((sectors DIV 4) * 16 DIV disk^.sectorSize);
    BootRecord.flags:= 0; //1 shl 7 for mirroring
    BootRecord.FATVersion:= 0;
    BootRecord.rootCluster:= 2; // can be changed if needed.
    BootRecord.FSInfoCluster:=1; //TODO need FSINFO
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

    dataStart:= (sectors DIV bootrecord.spc) + 2;

    //TODO FSINFO struct

    //write fat
    buffer := puint32(kalloc((sectors DIV bootrecord.spc) * 4));
    memset(uint32(buffer), 0, sectors DIV bootrecord.spc);
    puint32(buffer + 1)^:= $FFF8; //root directory table cluster, currently root is only 1 cluster long
    disk^.writeCallback(disk, start + 2, sectors DIV bootrecord.spc, buffer); 
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

    disk^.writeCallback(disk, dataStart + (bootRecord.spc), 1, buffer);

end;

procedure detect_volumes(disk : PStorage_Device);
var
    buffer : puint32;
    i : uint8;
    volume : PStorage_volume;
begin
    volume:= PStorage_volume(kalloc(sizeof(TStorage_Volume)));
    //check first address for MBR
    //if found then add volume and use info to see if there is another volume
    buffer := puint32(kalloc(512));
    memset(uint32(buffer), 0, 512);
    disk^.readcallback(disk, 2, 1, buffer);

    if (puint32(buffer + (127))^ = $55AA) and (PBootRecord(buffer)^.bsignature = $29) then begin
        console.writestringln('FAT32: volume found!');
        volume^.sectorStart:= 1;
        volume^.sectorSize:= PBootRecord(buffer)^.sectorSize;
        volume^.freeSectors:= 1000000; //TODO implement get free sectors need FSINFO implemented first
        volume^.filesystem := @filesystem;
        storagemanagement.register_volume(disk, volume);
    end;
end;

end.