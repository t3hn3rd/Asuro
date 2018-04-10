{ ************************************************
  * Asuro
  * Unit: Drivers/storage/fat32
  * Description: fat32 file system driver
  * 
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }

unit fat32;

interface

uses
    console, storagemanagement;

type 

    TBootRecord = bitpacked record 
        jmp2boot        : ubit24;
        OEMName         : uint64;
        sectorSize      : uint16;
        spc             : uint8;
        rsvSectors      : uint16;
        numFats         : uint8;
        numDirEnt       : uint16;
        numSecotrs      : uint16;
        mediaDescp      : uint8;
        sectorsPerFat   : uint16;
        sectorsPerTrack : uint16;
        heads           : uint16;
        hiddenSecotrs   : uint32;
        manySectors     : uint32;
    end;
    
    TExtendedBootRecord = bitpacked record
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
        signature     : uint8 = $28;
        volumeID      : uint32;
        volumeLabel   : array[0..10] of uint8;
        identString   : pchar = 'FAT32 ';
    end;

    TDirectory = bitpacked record
        fileName      : uint64;
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

procedure init;
procedure create_volume(disk : PStorage_Device; sectors : uint32; start : uint32);
function detect_volumes(disk : PStorage_Device) : APStorage_volume;

implementation

function load(ptr : void) : boolean;
begin
    console.outputln('DUMMY DRIVER', 'LOADED.')
end;

procedure init;
var
    filesystem : TFilesystem;
begin
    filesystem.sName:= 'FAT32'; 
    filesystem.writecallback:= write;
    filesystem.readcallback:= read;
    filesystem.createcallback:= create_volume;
    filesystem.detectcallback:= detect_volumes; 
    storagemanagement.register_filesystem(filesystem);
end;

procedure read(volume : PStorage_volume; directory : pchar; byteCount : uint32; buffer : puint32);
begin

end;

procedure write(volume : PStorage_volume; directory : pchar; byteCount : uint32; buffer : puint32);
begin

end;

procedure create_volume(disk : PStorage_Device; sectors : uint32; start : uint32);
begin

end;

function detect_volumes(disk : PStorage_Device) : APStorage_volume;
begin
    
end;

end.