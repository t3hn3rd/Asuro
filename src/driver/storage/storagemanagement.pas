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
    lmemorymanager,
    strings,
    lists,
    tracer;

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
    PFileSystem = ^TFilesystem;

    TStorage_Volume = record
        sectorStart     : uint32;
        sectorSize      : uint32;
        freeSectors     : uint32;
        filesystem      : PFilesystem; 
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
    fileSystems : PLinkedListBase;

procedure init();

procedure register_device(device : PStorage_Device);
function get_device_list() : PLinkedListBase;

procedure register_filesystem(filesystem : PFilesystem);

//procedure register_volume(volume : TStorage_Volume);

//TODO write partition table

implementation 

procedure disk_command(params : PParamList);
var
    i : uint8;
    spc : puint32;
    drive : uint32;
begin
    push_trace('storagemanagement.diskcommand');
    spc:= puint32(kalloc(4));
    spc^:= 4;

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
    end else if stringEquals(getParam(0, params), 'format') then begin //disk format 0 fat32
        //check param count!
        drive :=  stringToInt(getParam(1, params));
        console.writeintln(drive); // works
        if stringEquals(getParam(2, params), 'fat32') then begin
                PFilesystem(LL_Get(filesystems, 0))^.createCallback((PStorage_Device(LL_Get(storageDevices, drive))), 100000, 1, @spc); //todo check fs
                console.writestring('Drive ');
                //console.writeint(drive); // page faults
                console.writestringln(' formatted.');
        end;

    end else if stringEquals(getParam(0, params), 'lsfs') then begin
        for i:=0 to LL_Size(filesystems)-1 do begin
            //print file systems
            console.writestringln(PFilesystem(LL_Get(filesystems, i))^.sName);
        end;
    end;
    pop_trace;
end;

procedure init();
begin
    push_trace('storagemanagement.init');
    storageDevices:= ll_New(sizeof(TStorage_Device));
    fileSystems:= ll_New(sizeof(TFilesystem));
    terminal.registerCommand('DISK', @disk_command, 'List physical storage devices');
    pop_trace();
end;

procedure register_device(device : PStorage_device);
var 
    i   : uint8;
    elm : void;
begin
    elm:= LL_Add(storageDevices);
    PStorage_device(elm)^ := device^;

    //check for volumes
end;

function get_device_list() : PLinkedListBase;
begin
    get_device_list:= storageDevices;
end;

procedure register_filesystem(filesystem : PFilesystem);
var
    i : uint8;
    elm : void;    
begin
    elm:= LL_Add(fileSystems);
    PFileSystem(elm)^ := filesystem^;
end;

end.