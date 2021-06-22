//  Copyright 2021 Aaron Hance
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

{
    Driver->Storage->StorageManagment Storage Managment System

    @author(Aaron Hance ah@aaronhance.me)
}
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
    tracer,
    rtc;

type 

    TControllerType = (ControllerIDE, ControllerUSB, ControllerAHCI, ControllerNET, ControllerRAM, rsvctr1, rsvctr2, rsvctr3);
    TDirectory_Entry_Type = (directoryEntry, fileEntry, mountEntry);
    PStorage_volume = ^TStorage_Volume;
    PStorage_device = ^TStorage_Device;
    APStorage_Volume = array[0..10] of PStorage_volume;
    byteArray8 = array[0..7] of char;
    PByteArray8 = ^byteArray8;
    PDirectory_Entry = ^TDirectory_Entry;

    PPWriteHook = procedure(volume : PStorage_volume; directory : pchar; entry : PDirectory_Entry; byteCount : uint32; buffer : puint32; statusOut : puint32);
    PPReadHook = function(volume : PStorage_Volume; directory : pchar; fileName : pchar; fileExtension : pchar; buffer : puint32; bytecount : puint32) : uint32;
    PPHIOHook = procedure(volume : PStorage_device; addr : uint32; sectors : uint32; buffer : puint32);
    PPCreateHook = procedure(disk : PStorage_Device; sectors : uint32; start : uint32; config : puint32);
    PPDetectHook = procedure(disk : PStorage_Device);
    PPCreateDirHook = procedure(volume : PStorage_volume; directory : pchar; dirname : pchar; attributes : uint32; status : puint32);
    PPReadDirHook = function(volume : PStorage_volume; directory : pchar; status : puint32) : PLinkedListBase; //returns: 0 = success, 1 = dir not exsist, 2 = not directory, 3 = error //returns: 0 = success, 1 = dir not exsist, 2 = not directory, 3 = error

    PPHIOHook_ = procedure;

    TFilesystem = record
        sName : pchar;
        writeCallback     : PPWriteHook;
        readCallback      : PPReadHook;
        createCallback    : PPCreateHook;
        detectCallback    : PPDetectHook;
        createDirCallback : PPCreateDirHook;
        readDirCallback   : PPReadDirHook;
    end;
    PFileSystem = ^TFilesystem;

    TStorage_Volume = record
        device          : PStorage_device;
        sectorStart     : uint32;
        sectorSize      : uint32;
        freeSectors     : uint32;
        filesystem      : PFilesystem; 
        { True if this drive contains the loaded OS }
        isBootDrive     : boolean;
    end;

    { Generic storage device }
    TStorage_Device = record
        idx              : uint8;
        controller       : TControllerType;
        controllerId0    : uint32;
        maxSectorCount   : uint32;
        sectorSize       : uint32;
        writable         : boolean;
        volumes          : PLinkedListBase;
        writeCallback    : PPHIOHook;
        readCallback     : PPHIOHook;
        hpc              : uint16;
        spt              : uint16;
    end;
    APStorage_Device = array[0..255] of PStorage_device;

    { Generic directory entry }
    TDirectory_Entry = record
        { Contains filename and optionally file extension, seperated by the last period.}
        fileName  : pchar; 
        entryType : TDirectory_Entry_Type;
        creationT : TDateTime;
        modifiedT : TDateTime;
    end;

var 
    storageDevices : PLinkedListBase; //index in this array is global drive id
    fileSystems : PLinkedListBase;
    rootVolume : PStorage_Volume = PStorage_Volume(0);

procedure init();

procedure register_device(device : PStorage_Device);
function get_device_list() : PLinkedListBase;

procedure register_filesystem(filesystem : PFilesystem);

procedure register_volume(device : PStorage_Device; volume : PStorage_Volume);
//function writeNewFile(fileName : pchar; extension : pchar; buffer : puint32; size : uint32) : uint32;
//function readFile(fileName : pchar; extension : pchar; buffer : puint32; byteCount : puint32) : puint32;

//TODO write partition table

implementation 

function controller_type_2_string(controllerType : TControllerType) : pchar; 
begin
    case controllerType of
        ControllerIDE : controller_type_2_string:= 'IDE';
        ControllerUSB :  controller_type_2_string:= 'USB';
        ControllerAHCI : controller_type_2_string:= 'ACHI (SATA)';
        ControllerNET : controller_type_2_string:= 'Net';
    end;
end;

{ Disk subcommand for listing drives }
procedure ls_command(params : PParamList);
var 
    i : uint16;
begin
    push_trace('storagemanagment.ls_command');
    //if no storage device print none found
    if LL_Size(storageDevices) < 1 then begin
        console.writestringlnWnd('No storage devices found.', getTerminalHWND());
        exit;
    end;

    //print number of storage devices
    console.writeintwnd(LL_Size(storageDevices), getTerminalHWND());
    console.writestringlnWnd(' devices found', getTerminalHWND());

    for i:=0 to LL_Size(storageDevices)-1 do begin

        //print device id and type
        console.writeintwnd(i, getTerminalHWND());
        console.writestringwnd(' - Device type: ', getTerminalHWND());
        console.writestringwnd(controller_type_2_string(PStorage_Device(LL_Get(storageDevices, i))^.controller), getTerminalHWND());
        console.writestringwnd(', ', getTerminalHWND());

        //print device capcity
        console.writestringwnd(' Capacity: ', getTerminalHWND());
        console.writeintwnd((( PStorage_Device(LL_Get(storageDevices, i))^.maxSectorCount * PStorage_Device(LL_Get(storageDevices, i))^.sectorSize) DIV 1024) DIV 1024, getTerminalHWND());
        console.writestringlnWnd('MB', getTerminalHWND());
    end;

end;

{ Disk subcommand for formatting drives }
procedure format_command(params : PParamList);
var
    driveIndex : uint16;
    drive : PStorage_Device;

    filesystemString : pchar;
    filesystem : PFileSystem;
    spc : puint32;
begin

    spc:= puint32(kalloc(4));
    spc^:= 4;

    driveIndex:= stringToInt( getParam(1, params) );
    drive:= PStorage_Device(LL_Get(storageDevices, driveIndex));

    //todo change b4 adding in aniother filesytem
    PFilesystem(LL_Get(filesystems, 0))^.createCallback(drive, drive^.maxSectorCount-1, 1, spc); 

    writestringWnd('Drive ', getTerminalHWND);
    writeintWnd(driveIndex, getTerminalHWND);
    writestringlnWnd(' formatted.', getTerminalHWND);
    
end;


{ Command for managing and getting information from disks. }
procedure disk_command(params : PParamList);
var
    i : uint16;
    drive : uint16;
    subcmd : pchar;
begin
    push_trace('StorageManagment.disk_command');

    //check if params wehre supplied
    if paramCount(params) = 0 then begin
        writestringlnWnd('Incorrect number of params.', getTerminalHWND);
        exit;
    end;
    
    subcmd:= getParam(0, params);

    //ls for listing storage devices
    if stringEquals(subcmd, 'ls') then begin
        ls_command(params);
        exit;
    end;

    //format command for clearing a disk and make a new volume
    if stringEquals(subcmd, 'format') then begin
        format_command(params);
    end;

    //lsfs command for listing filesystems
    if stringEquals(subcmd, 'lsfs') then begin
    end;

    pop_trace();
end;

{ Initialise the storage manager }
procedure init();
begin
    push_trace('StorageManagment.init');
    
    setworkingdirectory('.');
    storageDevices:= ll_new(sizeof(TStorage_Device));
    fileSystems:= ll_New(sizeof(TFilesystem));
    terminal.registerCommand('DISK', @disk_command, 'Disk utility');

    pop_trace();
end; 

{ Register a new drive with the storage manager }
procedure register_device(device : PStorage_device);
var 
    i   : uint8;
    elm : void;
begin
    push_trace('StorageManagment.register_device');

    //add the drive to the list of storage devices.
    elm:= LL_Add(storageDevices);
    PStorage_device(elm)^ := device^;

    //create empty volume list for drive
    PStorage_Device(LL_Get(storageDevices, LL_Size(storageDevices) - 1))^.volumes := LL_New(sizeof(TStorage_Volume));
    
    //check for volumes
    for i:=0 to ll_size(filesystems) - 1 do begin
        PFileSystem(LL_Get(filesystems, i))^.detectCallback(PStorage_Device(LL_Get(storageDevices, LL_Size(storageDevices) - 1)));
    end;

    pop_trace();
end;

function get_device_list() : PLinkedListBase;
begin
    get_device_list:= storageDevices;
end;

procedure register_filesystem(filesystem : PFilesystem);
var
    elm : void;    
begin
    elm:= LL_Add(fileSystems);
    PFileSystem(elm)^ := filesystem^;
end;

procedure register_volume(device : PStorage_Device; volume : PStorage_Volume);
var
    elm : void;
begin
    push_trace('storagemanagement.register_volume');
    elm := LL_Add(device^.volumes);
    PStorage_volume(elm)^:= volume^;

    if rootVolume = PStorage_Volume(0) then rootVolume:= volume;
end;

end.