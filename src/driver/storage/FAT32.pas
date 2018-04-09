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
end;

procedure read(volume : PStorage_volume; directory : pchar; byteCount : uint32; buffer : puint32);
begin
end;

procedure write(volume : PStorage_volume; directory : pchar; byteCount : uint32; buffer : puint32);
begin
end;

end.