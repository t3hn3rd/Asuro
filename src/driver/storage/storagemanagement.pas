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

procedure register_device(device : TStorage_Device);
function get_all_devices() : APStorage_Device;
function read(device : uint16; address : uint32; byteCount : uint32) : PuInt32;
procedure write(device : uint16; address : uint32; byteCount : uint32; data : PuInt32);

implementation 
end.