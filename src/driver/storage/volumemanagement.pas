{ ************************************************
  * Asuro
  * Unit: Drivers/storage/storagemanagement
  * Description: manages logical volumes on disks
  * 
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }
unit volumemanagement;

interface

uses
    util,
    drivertypes,
    console,
    terminal,
    drivermanagement,
    storagemanagement,
    vmemorymanager,
    lmemorymanager;

type

    TStorage_Volume = record 
        device : TStorage_Device;
        sectorStart : uint32;
        sectorSize  : uint32;
        filesystem  : uint32; 
    end;

var

implementation 