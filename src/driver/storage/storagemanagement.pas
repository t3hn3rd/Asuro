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
    vmemorymanager,
    lmemorymanager,
    strings;

type 

    TControllerType = (ControllerIDE, ControllerUSB, ControllerAHCI, ControllerNET);
    PStorage_volume = ^TStorage_Volume;
    PPIOHook = procedure(volume : PStorage_volume; directory : pchar; byteCount : uint32; buffer : puint32);

    TFilesystem = record
        sName : pchar;
        writeCallback : PPIOHook;
        readCallback  : PPIOHook;
    end;

    TStorage_Volume = record
        idx         : uint8; 
        sectorStart : uint32;
        sectorSize  : uint32;
        filesystem  : TFilesystem; 
    end;
    APStorage_Volume = array[0..255] of PStorage_volume;

    TStorage_Device = record
        idx              : uint8;
        controller       : TControllerType;
        controllerId0    : uint32;
        maxSectorCount   : uint32;
        sectorSize       : uint32;
        writable         : boolean;
        volumes          : array[0..255] of TStorage_Volume
    end;
    PStorage_device = ^TStorage_Device;
    APStorage_Device = array[0..255] of PStorage_device;


var 
    storageDevices : array[0..255] of TStorage_Device; //index in this array is global drive id
    fileSystems : array[0..31] of TFilesystem;

//TODO need callback things for when new devices are connected
procedure init();

procedure register_device(device : TStorage_Device);
function get_all_devices() : APStorage_Device;

//procedure register_filesystem(filesystem : TFilesystem);

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

end.