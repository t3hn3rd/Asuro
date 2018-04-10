{ ************************************************
  * Asuro
  * Unit: Drivers/storage/storagemanagement
  * Description: interface for storage drivers
  * 
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }
unit storagemanagement;

interface

uses
    util,
    drivertypes,
    console,
    terminal,
    drivermanagement,
    strings;

type 

    TControllerType = (ControllerIDE, ControllerUSB, ControllerAHCI, ControllerNET);
    PStorage_volume = ^TStorage_Volume;
    PStorage_device = ^TStorage_Device;
    PPIOHook = procedure(volume : PStorage_volume; directory : pchar; byteCount : uint32; buffer : puint32);
    PPCreateHook = procedure(disk : PStorage_Device; sectors : uint32; start : uint32);
    PPDetectHook = procedure(disk : PStorage_Device);

    TFilesystem = record
        sName : pchar;
        writeCallback  : PPIOHook;
        readCallback   : PPIOHook;
        createCallback : uint32;
        detectCallback : uint32;
    end;

    TStorage_Volume = record
        idx         : uint8; 
        sectorStart : uint32;
        sectorSize  : uint32;
        filesystem  : TFilesystem; 
    end;
    APStorage_Volume = array[0..10] of PStorage_volume;

    TStorage_Device = record
        idx              : uint8;
        controller       : TControllerType;
        controllerId0    : uint32;
        maxSectorCount   : uint32;
        sectorSize       : uint32;
        writable         : boolean;
        volumes          : array[0..255] of TStorage_Volume
    end;
    APStorage_Device = array[0..255] of PStorage_device;


var 
    storageDevices : array[0..25] of TStorage_Device; //index in this array is global drive id
    fileSystems : array[0..31] of TFilesystem;

procedure init();

procedure register_device(device : TStorage_Device);
function get_all_devices() : APStorage_Device;

procedure register_filesystem(filesystem : TFilesystem);

//procedure register_volume(volume : TStorage_Volume);

implementation 

procedure disk_command(params : PParamList);
var
    i : uint8;
begin

    if stringEquals(getParam(0, params), 'ls') then begin
        for i:=0 to 255 do begin
            if storageDevices[i].maxSectorCount = 0 then break;
            console.writeint(i);
            console.writestring(') Device_Type: ');
            case storageDevices[i].controller of
                ControllerIDE  : console.writestring('IDE, ');
                ControllerUSB  : console.writestring('USB, ');
                ControllerAHCI : console.writestring('AHCI, ');
                ControllerNET  : console.writestring('NET, ');
            end;
            console.writestring('Capacity: ');
            console.writeint(((storageDevices[i].maxSectorCount * storageDevices[i].sectorSize) DIV 1000) DIV 1000);
            console.writestringln('MB');
        end;
    end;
end;

procedure init();
begin
    terminal.registerCommand('DISK', @disk_command, 'List physical storage devices');
end;

procedure register_device(device : TStorage_Device);
var 
    i : uint8;
begin
    for i:=0 to 255 do begin 
        if storageDevices[i].maxSectorCount = 0 then begin
            storageDevices[i]:= device;
            storageDevices[i].idx:= i;
            //for all filesystems look for volumes
            break;
        end;
    end;
end;

function get_all_devices() : APStorage_Device;
var
    devices : APStorage_Device;
    i : uint8;
begin
    for i:= 0 to 255 do begin
        if storageDevices[i].maxSectorCount <> 0 then begin
            devices[i]:= @storageDevices[i];
        end;
    end;
    get_all_devices:= devices;
end;

procedure register_filesystem(filesystem : TFilesystem);
var
    i : uint8;
begin
    for i:= 0 to 31 do begin
        if fileSystems[i].sName = nil then begin
            fileSystems[i]:= filesystem;
            break;
        end;
    end; 
end;

end.