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
        hpc              : uint16;
        spt              : uint16;
    end;
    APStorage_Device = array[0..255] of PStorage_device;

    TDirectory_Entry = record //TODO implement dtae.time stuff
        fileName  : pchar;
        extension : pchar;
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
function writeNewFile(fileName : pchar; extension : pchar; buffer : puint32; size : uint32) : uint32;
function readFile(fileName : pchar; extension : pchar; buffer : puint32; byteCount : puint32) : puint32;

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

function padWithSpaces(str : pchar; length : uint16) : pchar;
var
    i : uint32;
    ii : uint32;
begin
    for i:=0 to length do begin
        if str[i] = ' ' then begin
            for ii:=i to length do begin
                padWithSpaces[i]:= ' ';
            end;
        end else begin
            if str[i] = char(0) then exit;
            padWithSpaces[i]:= str[i];
        end;
    end;
end;

function allButLast(str : pchar; delim : char) : pchar;
var
    strings : PLinkedListBase;
    i       : uint32;
begin
    strings:= STRLL_FromString(str, delim);

    if STRLL_Size(strings) > 2 then begin
        for i:=0 to STRLL_Size(strings) - 2 do begin
            stringConcat(allButLast, STRLL_Get(strings, i));
        end;
    end else begin
        if STRLL_Size(strings) = 2 then begin
            allButLast:= STRLL_Get(strings, 0);
        end else begin
            allButLast:= str;
        end;
    end;

    console.writestringlnWND(allButLast, getTerminalHWND());

    STRLL_Clear(strings);
    STRLL_Free(strings);
end;

procedure list_command(params : PParamList);
var
    dirEntries : PLinkedListBase;
    i : uint32;
    ii : uint32;
    error : puint32;
    nli : uint32 = 0;
begin
    error := puint32(kalloc(4));

    if paramCount(params) > 1 then begin
        console.writestringlnWND('', getTerminalHWND());
        console.writestringlnWND('Lists the files and directories in working directory, or optionaly, the specified directory.', getTerminalHWND());
        console.writestringlnWND('', getTerminalHWND());
        console.writestringlnWND('Usage:', getTerminalHWND());
        console.writestringlnWND('ls <directory>', getTerminalHWND());
    end else begin

        if paramCount(params) = 1 then begin
            dirEntries:= rootVolume^.filesystem^.readDirCallback(rootVolume, pchar(getParam(0, params)), error);
        end else begin
            dirEntries:= rootVolume^.filesystem^.readDirCallback(rootVolume, getWorkingDirectory(), error);
        end;

        //loop and print dirs
        for i:=2 to LL_Size(dirEntries) - 1 do begin
            console.writestringWND('    /', getTerminalHWND);
            console.writestringWND( PDirectory_Entry(LL_Get(dirEntries, i ))^.fileName , getTerminalHWND());
            if nli > 3 then begin 
                console.writestringlnWND('',getTerminalHWND());
                nli:= 0;
            end else begin
                nli+=1;
            end;
        end;

        console.writestringlnWND('',getTerminalHWND());


    end;
    kfree(error);
end;

procedure change_dir_command(params : PParamList);
var
    targetDirectory : pchar;
    dirEntries      : PLinkedListBase;
    lastString      : pchar;
    entry           : PDirectory_Entry;
    error           : puint32;
begin
    error := puint32(kalloc(4));
    if paramCount(params) = 1 then begin

        if (pchar(getParam(0, params))[0] = '/') then begin //search from root
            targetDirectory:= pchar(getParam(0,params));
            dirEntries:= rootVolume^.filesystem^.readDirCallback(rootVolume, pchar( getParam(0, params)), error);
            console.writestringlnWND('from root', getTerminalHWND());
        end else begin //search from working directory
            //concat current dir and param
            targetDirectory:= stringConcat(getWorkingDirectory, '/');
            targetDirectory:= stringConcat(targetDirectory, pchar(getParam(0,params)) ); //do i need pad with space?
            dirEntries:= rootVolume^.filesystem^.readDirCallback(rootVolume, targetDirectory, error); // need to be able to supply attributes for list conversion method
        end;

        if error^ = 0 then begin
            setworkingdirectory(targetDirectory); // need to clean ..
        end;
        
        kfree(puint32(dirEntries));
    end else begin
        console.writestringlnWND('', getTerminalHWND());
        console.writestringlnWND('Changes the current working directory, this is the context wich other commands rely on.', getTerminalHWND());
        console.writestringlnWND('', getTerminalHWND());
        console.writestringlnWND('Usage:', getTerminalHWND());
        console.writestringlnWND('cd <directory>', getTerminalHWND());
    end;
    kfree(error);
end;

procedure mkdir_command(params : PParamList);
var
    directories : PLinkedListBase;
    targetDirectory : pchar;
    temp : pchar;
    target : pchar;
    device : PStorage_Device;
    volume : PStorage_Volume;
    status : uint32;
    error : puint32;
    i : uint32;
    isRoot : boolean = false;
begin
    error:= @status;
    error^ := 0;
    
    if paramCount(params) = 1 then begin
        directories:= STRLL_FromString(getParam(0, params), '/');

        if LL_Size(directories) > 1 then begin
                temp := allbutlast(getParam(0, params), '/');
        end else begin
            temp:= '/';
        end;

        target:= STRLL_Get(directories, LL_Size(directories)-1);

        if (getParam(0, params)[0] = '/') then begin //search from root
            targetDirectory:= temp;
        end else begin //search from working directory
            targetDirectory:= stringConcat(getWorkingDirectory, '/');
            targetDirectory:= stringConcat(targetDirectory, temp ); //do i need pad with space?
        end;


        console.writestringlnWND(targetDirectory, getTerminalHWND());
        console.writestringlnWND(target, getTerminalHWND());

        device:= PStorage_Device(LL_Get(storageDevices, 0));
        volume:= PStorage_Volume(LL_Get(device^.volumes, 0));

        volume^.filesystem^.createDirCallback(volume, targetDirectory, target, $10, error);
        if error^ <> 0 then console.writestringlnWND('ERROR', getTerminalHWND());
    end; // else print out help
end;

procedure txt_command(params : PParamList);
var
    buffer : puint32;
    entry : TDirectory_Entry;
    error : puint32;
    i     : uint32 = 1;
    fatArray      : byteArray8 = ('F','A','T','3','2',' ',' ',' ');
begin
    push_trace('txt_command');
    error:= puint32(kalloc(512));
    buffer:= puint32(kalloc(2048));
    memset(uint32(buffer), 0, 2048);

    entry.fileName:= getParam(0, params);
    entry.extension:= 'txt';
    entry.entryType:= TDirectory_Entry_Type.fileEntry;

    PByteArray8(buffer)^ := fatArray;


    push_trace('txt_cmd_');
    rootVolume^.filesystem^.writeCallback(rootVolume, '.', @entry, stringSize(pchar(buffer)), buffer, error); //need to change the function pointer to match and impiment it in the filesystem init.
end;

procedure init();
begin
    push_trace('storagemanagement.init');
    setworkingdirectory('.');
    storageDevices:= ll_New(sizeof(TStorage_Device));
    fileSystems:= ll_New(sizeof(TFilesystem));
    terminal.registerCommand('DISK', @disk_command, 'Disk utility');
    terminal.registerCommand('VOLUME', @volume_command, 'Volume utility');
    terminal.registerCommandEx('mkdir', @mkdir_command, 'Make Directory', true);
    terminal.registerCommandEx('ls', @list_command, 'List contents of directory', true);
    terminal.registerCommandEx('cd', @change_dir_command, 'Change the working directory', true);
    terminal.registerCommandEx('txt', @txt_command, 'testing file write', false);
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

    if rootVolume = PStorage_Volume(0) then rootVolume:= volume;
end;

function writeNewFile(fileName : pchar; extension : pchar; buffer : puint32; size : uint32) : uint32;
var
    entry : TDirectory_Entry;
    error : puint32;
begin
    push_trace('storagemanagment.writenewfile');
    error:= puint32(kalloc(512));

    entry.fileName:= fileName;
    entry.extension:= extension;
    entry.entryType:= TDirectory_Entry_Type.fileEntry;

    rootVolume^.filesystem^.writeCallback(rootVolume, getWorkingDirectory(), @entry, size, buffer, error);
    writeNewFile:= error^; //memory leak
end;

function cleanString(str : pchar) : pchar;
var
    i : uint32;
    ii: uint32;
begin
    cleanString:= pchar(kalloc(10));
    memset(uint32(cleanstring), 0, 10);
    for i:=0 to 7 do begin
        if str[i] = char(0) then begin
            for ii:=i to 7 do begin
                cleanString[ii]:= ' ';
            end;
            break;
        end else begin
            cleanString[i]:= str[i];
        end;
    end;
end;

function readFile(fileName : pchar; extension : pchar; buffer : puint32; byteCount : puint32) : puint32;
var
    error : puint32;
    dirs : PLinkedListBase;
    exists : boolean = false;
    i : uint32;
    cleanFileName : pchar;
    otherCleanFileName : pchar;
begin
    push_trace('storagemanagement.readfile');
    //bytecount := puint32(kalloc(4));
    //memset(uint32(bytecount), 0, 4);
    error := puint32(kalloc(4));
    readfile:= error;

    // cleanFileName := cleanString(filename);

    // dirs := rootVolume^.filesystem^.readdirCallback(rootVolume, getWorkingDirectory(), error);
    
    // for i:=0 to LL_Size(dirs) -1 do begin
    //     otherCleanFileName := cleanString(PDirectory_Entry(LL_get(dirs, i))^.filename); //TODO clean extension
    //             writestringlnWND(otherCleanFileName, getTerminalHWND());
    //             writestringlnWND(cleanFileName, getTerminalHWND());

    //     if stringEquals(cleanFileName, otherCleanFileName) then begin
    //             writestringlnWND('match found!', getTerminalHWND());

    //         exists := true;
    //         error^ := 0;
    //     end;

    //     kfree(puint32(otherCleanFileName));
    // end;

    // kfree(puint32(cleanFileName));



    error^ := rootVolume^.filesystem^.readCallback(rootVolume, getWorkingDirectory(), fileName, extension, buffer, bytecount);


end;
end.