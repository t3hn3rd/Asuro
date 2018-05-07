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
    TDirectory_Entry_Type = (Directory, Data, Executable, Mounted);
    PStorage_volume = ^TStorage_Volume;
    PStorage_device = ^TStorage_Device;
    APStorage_Volume = array[0..10] of PStorage_volume;
    byteArray8 = array[0..7] of char;
    PByteArray8 = ^byteArray8;

    PPIOHook = procedure(volume : PStorage_volume; directory : pchar; byteCount : uint32; buffer : puint32);
    PPHIOHook = procedure(volume : PStorage_device; addr : uint32; sectors : uint32; buffer : puint32);
    PPCreateHook = procedure(disk : PStorage_Device; sectors : uint32; start : uint32; config : puint32);
    PPDetectHook = procedure(disk : PStorage_Device);
    PPCreateDirHook = procedure(volume : PStorage_volume; directory : pchar; dirname : pchar; attributes : uint32; status : puint32);
    PPReadDirHook = function(volume : PStorage_volume; directory : pchar; status : puint32) : PLinkedListBase; //returns: 0 = success, 1 = dir not exsist, 2 = not directory, 3 = error //returns: 0 = success, 1 = dir not exsist, 2 = not directory, 3 = error

    PPHIOHook_ = procedure;

    TFilesystem = record
        sName : pchar;
        writeCallback     : PPIOHook;
        readCallback      : PPIOHook;
        createCallback    : PPCreateHook;
        detectCallback    : PPDetectHook;
        createDirCallback : PPCreateDirHook;
        readDirCallback   : PPReadDirHook;
    end;
    PFileSystem = ^TFilesystem;

    TStorage_Volume = record
        device            : PStorage_device;
        sectorStart     : uint32;
        sectorSize      : uint32;
        freeSectors     : uint32;
        filesystem      : PFilesystem; 
        //filesystemInfo  : Puint32; // type dependant on filesystem. can be null if not creating volume now
        //directory       : PLinkedListBase; // type dependant on filesytem?
    end;

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
    end;
    APStorage_Device = array[0..255] of PStorage_device;

    TDirectory_Entry = record //TODO implement dtae.time stuff
        fileName  : pchar;
        extension : pchar;
        volume    : PStorage_Volume;
        entryType : TDirectory_Entry_Type;
    end;


var 
    storageDevices : PLinkedListBase; //index in this array is global drive id
    fileSystems : PLinkedListBase;

procedure init();

procedure register_device(device : PStorage_Device);
function get_device_list() : PLinkedListBase;

procedure register_filesystem(filesystem : PFilesystem);

procedure register_volume(device : PStorage_Device; volume : PStorage_Volume);

//TODO write partition table

implementation 

procedure test_command(params : PParamList);
var
    i : uint32;
    elm : puint32;
    str : pchar;
    list : PLinkedListBase;
begin
    str := getParam(0, params);

    list := LL_fromString(str, '/');

    for i:=0 to LL_Size(list) - 1 do begin
        elm:= puint32(LL_Get(list, i));
        str := pchar(elm^);
        console.writestringln(str);
    end;
end;

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
                PFilesystem(LL_Get(filesystems, 0))^.createCallback((PStorage_Device(LL_Get(storageDevices, drive))), 10000, 1, spc); //todo check fs
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

procedure mkdir_command(params : PParamList);
var
    dir : pchar;
    temp : pchar;
    dirName : pbyteArray8;
    device : PStorage_Device;
    volume : PStorage_Volume;
    error : uint32;
    i : uint32;
begin
    push_trace('mkdir');
    if paramCount(params) > 0 then begin
        dir := getParam(0, params);
        temp:= getParam(1, params);

        //for i:=0 to 7 do begin
        //    dirname[i]:= pbyteArray8(temp)[i];
        //end;

        //console.writestringlnWND(pchar(dirname), getTerminalHWND());

        device:= PStorage_Device(LL_Get(storageDevices, 0));
        volume:= PStorage_Volume(LL_Get(device^.volumes, 0));

        volume^.filesystem^.createDirCallback(volume, dir, temp, $10, @error);
        //if error <> 1 then console.writestringln('ERROR');
    end;
end;

procedure ls_command(params : PParamList);
type
    TDirectory = bitpacked record
        fileName      : array[0..7] of char;
        fileExtension : array[0..2] of char;
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
    PDirectory = ^TDirectory;
var
    dirs : PLinkedListBase;
    dir : pchar;
    dirp : PDirectory;
    device : PStorage_Device;
    volume : PStorage_Volume;
    error : puint32;
    i : uint32;
begin
    push_trace('ls');
    
    error:= puint32(kalloc(4));

    if paramCount(params) > 0 then begin
        dir := getParam(0, params);

        device:= PStorage_Device(LL_Get(storageDevices, 0));
        volume:= PStorage_Volume(LL_Get(device^.volumes, 0));
        dirs:= volume^.filesystem^.readDirCallback(volume, dir, error);

        //if error <> 1 then console.writestringln('ERROR');
        for i:=2 to LL_Size(dirs) - 1 do begin
            console.writestringWND('    /', getTerminalHWND);
            dirp:= PDirectory(LL_Get(dirs, i));
            console.writestringlnWND(pchar(dirp^.fileName), getTerminalHWND);
        end;
        pop_trace();
    end else begin
        console.writestringlnWND('Specifiy a folder', getTerminalHWND);
    end;
end;


procedure volume_command(params : PParamList);
var
    i : uint32;
    ii : uint16;
    device : PStorage_device;
    volume : PStorage_volume;
begin
    if stringEquals(getParam(0, params), 'ls') and (LL_Size(storageDevices) > 0) then begin
        for i:=0 to LL_Size(storageDevices) - 1 do begin
            device := PStorage_device(LL_Get(storageDevices, i));

            if LL_Size(device^.volumes) > 0 then begin
                for ii:= 0 to LL_Size(device^.volumes) - 1 do begin
                    volume:= PStorage_volume(LL_Get(device^.volumes, ii));
                    console.writeint(i);
                    console.writestring(') Filesystem: ');
                    console.writestring(volume^.filesystem^.sName);
                    console.writestring(' Free Space: ');
                    console.writeintln(volume^.freeSectors * volume^.sectorSize DIV 1024 DIV 1024);
                end;
            end;

        end;
    end;
end;


procedure init();
begin
    push_trace('storagemanagement.init');
    storageDevices:= ll_New(sizeof(TStorage_Device));
    fileSystems:= ll_New(sizeof(TFilesystem));
    terminal.registerCommand('DISK', @disk_command, 'Disk utility');
    terminal.registerCommand('VOLUME', @volume_command, 'Volume utility');
    terminal.registerCommandEx('mkdir', @mkdir_command, 'Volume utility', true);
    terminal.registerCommandEx('ls', @ls_command, 'Volume utility', true);
    pop_trace();
end;

procedure register_device(device : PStorage_device);
var 
    i   : uint8;
    elm : void;
begin
    push_trace('storagemanagement.register_device()');
    elm:= LL_Add(storageDevices);
    PStorage_device(elm)^ := device^;

    PStorage_Device(LL_Get(storageDevices, LL_Size(storageDevices) - 1))^.volumes := LL_New(sizeof(TStorage_Volume));
    //check for volumes
    for i:=0 to ll_size(filesystems) - 1 do begin
        PFileSystem(LL_Get(filesystems, i))^.detectCallback(PStorage_Device(LL_Get(storageDevices, LL_Size(storageDevices) - 1)));
    end;
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
end;

end.