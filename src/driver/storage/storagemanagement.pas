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
    IDE,
    drivermanagement,
    vmemorymanager,
    lmemorymanager;

type 

    TControllerType = (ControllerIDE, ControllerUSB, ControllerAHCI, ControllerNET);

    PStorage_device = ^TStorage_Device;
    APStorage_Device = array[0..256] of PStorage_device;
    TStorage_Device = record
        controller       : TControllerType;
        controllerId0    : uint32;
        maxSectorCount   : uint32;
        usedSectorCount  : uint32;
    end;

const
    

var 
    storageDevices : array[0..255] of TStorage_Device;

procedure init();
procedure register_device(device : TStorage_Device);
function get_all_devices() : APStorage_Device;
function read(device : uint16; address : uint32; byteCount : uint32) : PuInt32;
procedure write(device : uint16; address : uint32; byteCount : uint32; data : PuInt32);

implementation 

procedure list_drives_command(params : PParamList);
var
    i : uint8;
begin
    for i:=0 to 255 do begin
        if storageDevices[i].controller = nil then break;
        console.writeint(i);
        console.writestring(') Device_Type: ');
        case storageDevices[i].controller of
            ControllerIDE:console.writestring('IDE ');
            ControllerUSB:console.writestring('USB ');
            ControllerAHCI:console.writestring('AHCI ');
            ControllerNET:console.writestring('NET ');
        end;
        console.writestring('Capacity: ');
        console.writeint(((sectors * 512) / 1000) / 1000);
        console.writestringln('MB');
    end;
end;

procedure init();
begin
    terminal.registerCommand('disks', @list_drives_command, 'List storage devices');
end;
end.