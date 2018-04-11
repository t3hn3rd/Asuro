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
    strings,
    lists;

type 

    TControllerType = (ControllerIDE, ControllerUSB, ControllerAHCI, ControllerNET);
    PStorage_volume = ^TStorage_Volume;
    PStorage_device = ^TStorage_Device;
    APStorage_Volume = array[0..10] of PStorage_volume;

    PPIOHook = procedure(volume : PStorage_volume; directory : pchar; byteCount : uint32; buffer : puint32);
    PPHIOHook = procedure(volume : PStorage_device; addr : uint32; sectors : uint32; buffer : puint32);
    PPCreateHook = procedure(disk : PStorage_Device; sectors : uint32; start : uint32; config : puint32);
    PPDetectHook = procedure(disk : PStorage_Device; volumes : Puint32);

    PPHIOHook_ = procedure;

    TFilesystem = record
        sName : pchar;
        writeCallback  : PPIOHook;
        readCallback   : PPIOHook;
        createCallback : PPCreateHook;
        detectCallback : PPDetectHook;
    end;

    TStorage_Volume = record
        sectorStart     : uint32;
        sectorSize      : uint32;
        freeSectors     : uint32;
        filesystem      : TFilesystem; 
        filesystemInfo  : Puint32; // type dependant on filesystem. can be null if not creating volume now
        directory       : PLinkedListBase; // type dependant on filesytem?
    end;

    TStorage_Device = record
        idx              : uint8;
        controller       : TControllerType;
        controllerId0    : uint32;
        maxSectorCount   : uint32;
        sectorSize       : uint32;
        writable         : boolean;
        volumes          : array[0..7] of TStorage_Volume;
        writeCallback    : PPHIOHook;
        readCallback     : PPHIOHook;
    end;
    APStorage_Device = array[0..255] of PStorage_device;


var 
    storageDevices : PLinkedListBase; //index in this array is global drive id
    fileSystems : array[0..7] of TFilesystem;

procedure init();

procedure register_device(device : PStorage_Device);
function get_device_list() : PLinkedListBase;

procedure register_filesystem(filesystem : TFilesystem);

//procedure register_volume(volume : TStorage_Volume);

//TODO write partition table

implementation 

procedure disk_command(params : PParamList);
var
    i : uint8;
begin


    if stringEquals(getParam(0, params), 'ls') and (LL_Size(storageDevices) > 0) then begin
        for i:=0 to LL_Size(storageDevices) - 1 do begin
          //  if PStorage_Device(LL_Get(storageDevices, i))^.maxSectorCount = 0 then break;
            console.writeint(i);
            console.writestring(') Device_Type: ');
            case PStorage_Device(LL_Get(storageDevices, i))^.controller of
                ControllerIDE  : console.writestring('IDE, ');
                ControllerUSB  : console.writestring('USB, ');
                ControllerAHCI : console.writestring('AHCI, ');
                ControllerNET  : console.writestring('NET, ');
            end;
            console.writestring('Capacity: ');
            console.writeint((( PStorage_Device(LL_Get(storageDevices, i))^.maxSectorCount * PStorage_Device(LL_Get(storageDevices, i))^.sectorSize) DIV 1024) DIV 1024);
            console.writestringln('MB');
        end;
    end;
end;

procedure init();
begin
    storageDevices:= ll_New(sizeof(TStorage_Device));
    terminal.registerCommand('DISK', @disk_command, 'List physical storage devices');
end;

procedure register_device(device : PStorage_device);
var 
    i   : uint8;
    elm : void;
    dev : PStorage_device;
begin
    elm:= LL_Add(storageDevices);
    PStorage_device(elm)^ := device^;

    //check for volumes
end;

function get_device_list() : PLinkedListBase;
begin
    get_device_list:= storageDevices;
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