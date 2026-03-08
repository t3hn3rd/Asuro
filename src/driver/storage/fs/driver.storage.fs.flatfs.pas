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
    Driver->Storage->driver.storage.fs.flatfs super simple flat filesystem

    @author(Aaron Hance ah@aaronhance.me)
}

unit driver.storage.fs.flatfs;

interface

uses
    driver.storage.fs.mgr,
    core.ds.lists,
    memory.heap,
    io.stdio,
    driver.storage.mgr,
    driver.storage.types,
    core.strings,
    io.syslog,
    debug.tracer,
    core.util, arch.x86.util,
    driver.storage.vol.mgr;

type

    TDisk_Info = bitpacked record
        jmp2boot: ubit24;
        OEMName: array[0..7] of char;
        version: uint16;
        sectorCount : uint16;
        fileCount : uint16;
        signature : uint32;
    end;
    PDisk_Info = ^TDisk_Info;

    TFile_Entry = bitpacked record
        attribues : uint8; // 0x00 = does not exsist, 0x01 = file, 0x02 = hidden, 0x04 = system/read only, 0x10 = directory, 0x20 = archive
        name: array[0..53] of char; //max file name length is 54
        rsv : uint8;
        size: uint32;
        start : uint32;
    end;
    PFile_Entry = ^TFile_Entry;

var
    filesystem : TFilesystem;


procedure init;
procedure create_volume(volume : PStorage_Volume; sectors : uint32; start : uint32; config : puint32);
procedure detect_volumes(disk : PStorage_Device);
function read_directory(volume : PStorage_Volume; directory : pchar; status : PuInt32) : PLinkedListBase;
procedure write_directory(volume : PStorage_Volume; directory : pchar; status : PuInt32);
procedure write_file(volume : PStorage_Volume; fileName : pchar; data : PuInt32; size : uint32; status : PuInt32);
procedure read_file(volume : PStorage_Volume; fileName : pchar; data : PuInt32; status : PuInt32);

implementation

procedure create_volume(volume : PStorage_Volume; sectors : uint32; start : uint32; config : puint32);
var
    info : PDisk_Info;
    entryTable : PFile_Entry;
    i : uint32;

    directories : PLinkedListBase;
    status : PuInt32;

    data : pchar;

const
    asuroArray : array[0..7] of char = 'ASURO';
    systemArray : array[0..6] of char = '/system';
    programsArray : array[0..8] of char = '/programs';
    userArray : array[0..4] of char = '/user';

    testArray : array[0..23] of char = 'ASURO TEST DATA ARRAY';
begin

    info := PDisk_Info(Kalloc(512));
    memset(uint32(info), 0, 512);

    info^.jmp2boot := $0;
    info^.OEMName := asuroArray;
    info^.version := 1;
    info^.sectorCount := sectors;
    info^.fileCount := 1000;
    info^.signature := $0B00B1E5;

    if config^ <> 0 then begin
        info^.fileCount := config^;
    end;

    driver.storage.mgr.storage_write(volume^.device, start, 1, PuInt32(info));// what happens if buffer is smaller than 512?
    
    // create file table
    entryTable := PFile_Entry(Kalloc(126 * 512));
    memset(uint32(entryTable), 0, 126 * 512);

    //create system folders
    entryTable[0].attribues := $10;
    memcpy(uint32(@systemArray), uint32(@entryTable[0].name), 7);
    entryTable[0].size := 0;
    entryTable[0].start := 0;

    entryTable[1].attribues := $10;
    memcpy(uint32(@programsArray), uint32(@entryTable[1].name), 9);
    entryTable[1].size := 0;
    entryTable[1].start := 0;

    entryTable[2].attribues := $10;
    memcpy(uint32(@userArray), uint32(@entryTable[2].name), 5);
    entryTable[2].size := 0;
    entryTable[2].start := 0;

    //write file table
    driver.storage.mgr.storage_write(volume^.device, start + 1, ((sizeof(TFile_Entry) * info^.fileCount) div 512), puint32(entryTable));
    //volume^.device^.writeCallback(volume^.device, start + 1, 1, puint32(entryTable));

    //temp read
    status := PuInt32(Kalloc(sizeof(uint32)));
    // directories := read_directory(volume, '/', status);

    data := stringNew(1024);
    memset(uint32(data), 0, 513);
    memcpy(uint32(@testArray), uint32(data), 23);
    
    write_directory(volume, '/logs', status);
    write_directory(volume, '/logs/test', status);
    write_file(volume, '/logs/log.txt', PuInt32(data), 1, status);
    write_file(volume, '/logs/log2.txt', PuInt32(data), 1, status);
    write_file(volume, '/logs/log3.txt', PuInt32(data), 1, status);
    read_directory(volume, '/logs', status);

    kfree(puint32(data));

    read_file(volume, '/logs/log.txt', PuInt32(data), status);
end;

procedure write_directory(volume : PStorage_Volume; directory : pchar; status : PuInt32);
var
    directories : PLinkedListBase;
    i : uint32;

    fileEntries : PFile_Entry;

    fileEntry : PFile_Entry;
    buffer : PuInt32;

    position : uint32;
    offset : uint32;

const
    fileCount : uint32 = 1000;
begin
    status^ := 0;

    //directories := read_directory(volume, directory, status);

    fileEntries := PFile_Entry(Kalloc(sizeof(TFile_Entry) * fileCount + 512));
    memset(uint32(fileEntries), 0, sizeof(TFile_Entry) * fileCount + 512);

    driver.storage.mgr.storage_read(volume^.device, volume^.sectorStart + 1, (sizeof(TFile_Entry) * fileCount) div 512, PuInt32(fileEntries));

    if status^ = 0 then begin
        for i := 0 to fileCount - 1 do begin

            push_trace('write_directory_2');

            //fileEntry := PFile_Entry(STRLL_Get(directories, i));
            fileEntry := @fileEntries[i];

            if fileEntry^.attribues = 0 then begin
                fileEntry^.attribues := $10;
                fileEntry^.size := 0;
                fileEntry^.start := 0;
                memcpy(uint32(directory), uint32(@fileEntry^.name), stringSize(directory));

                push_trace('write_directory_3');

                //write file table
                buffer := PuInt32(Kalloc(513));
                memset(uint32(buffer), 0, 512);

                push_trace('write_directory.b4_read');

                //read file table cointaining entry of interest
                position := (i * sizeof(TFile_Entry)) div 512;
                driver.storage.mgr.storage_read(volume^.device, volume^.sectorStart + 1 + position, 1, buffer);

                push_trace('write_directory.after_read');

                //calculate entry offset into sector
                offset := (i * sizeof(TFile_Entry)) mod 512;
                offset := offset div sizeof(TFile_Entry);

                //set entry in buffer
                PFile_Entry(buffer)[offset] := fileEntry^;

                //write updated file table sector
                driver.storage.mgr.storage_write(volume^.device, volume^.sectorStart + 1 + position, 1, buffer);

                Kfree(buffer);

                push_trace('write_directory.after_write');

                break;

            end;
        end;
    end;

    if fileEntry^.attribues = 0 then begin
        status^ := 1;
    end;

end;

function read_directory(volume : PStorage_Volume; directory : pchar; status : PuInt32) : PLinkedListBase;
var
    directories : PLinkedListBase;
    fileEntrys : PFile_Entry;
    i : uint32;

    compString : PChar;
    afterString : PChar;
    slash : PChar;
    compStringLength : uint32;

    fileCount : uint32 = 1000;

    slashArray : array[0..1] of char = '/';

begin
    compString := pchar(kalloc(60));
    memset(uint32(compString), 0, 60);

    afterString := pchar(kalloc(60));
    memset(uint32(afterString), 0, 60);

    slash := stringNew(2);
    memcpy(uint32(@slashArray), uint32(slash), 1);

    directories := STRLL_New();

    fileEntrys := PFile_Entry(Kalloc(sizeof(TFile_Entry) * fileCount + 512));
    driver.storage.mgr.storage_read(volume^.device, volume^.sectorStart + 1, sizeof(TFile_Entry) * fileCount div 512, puint32(fileEntrys));

    for i := 0 to fileCount - 1 do begin

            if uint32(fileEntrys[i].name[0]) = 0 then begin
                break;
            end;

            

            compString := stringSub(fileEntrys[i].name, 0, stringSize(directory));
            afterString := stringSub(fileEntrys[i].name, stringSize(directory), stringSize(fileEntrys[i].name)-1);


            push_trace('read_directory_2');

            if stringEquals(compString, directory) and 
                (not stringContains(afterString, slash)) then begin

                STRLL_Add(directories, afterString);
            end;
    end;

    push_trace('read_directory_3');

    Kfree(puint32(fileEntrys));

    read_directory := directories;
end;

procedure quicksort_start(list : PFile_Entry; begining : uint32; stop : uint32);
var
    pivot : uint32;
    i : uint32;
    j : uint32;
    temp : PLinkedListBase;

    tempFileEntry : PFile_Entry;
begin

    tempFileEntry := PFile_Entry(Kalloc(sizeof(TFile_Entry)));
    memset(uint32(tempFileEntry), 0, sizeof(TFile_Entry));

    i:=begining;
    j:=stop;

    pivot := list[(begining + stop) div 2].start;

    while i <= j do begin
        while list[i].start < pivot do begin
            i := i + 1;
        end;

        while list[j].start > pivot do begin
            j := j - 1;
        end;

        if i <= j then begin
            tempFileEntry^ := list[i];
            list[i] := list[j];
            list[j] := tempFileEntry^;

            i := i + 1;
            j := j - 1;
        end;
    end;

    if begining < j then begin
        quicksort_start(list, begining, j);
    end;

    if i < stop then begin
        quicksort_start(list, i, stop);
    end;

    Kfree(puint32(tempFileEntry));

end;

function find_free_space(volume : PStorage_Volume; size : uint32; status : PuInt32) : uint32;
var
    fileEntrys : PFile_Entry;
    confirmedFileEntrys : PFile_Entry;
    confirmedFileEntrysCount : uint32 = 0;
    fileEntry : PFile_Entry;
    i : uint32;
    fileCount : uint32 = 1000;

    baseAddress : uint32;
begin
    fileEntrys := PFile_Entry(Kalloc(sizeof(TFile_Entry) * fileCount + 512));
    confirmedFileEntrys := PFile_Entry(Kalloc(sizeof(TFile_Entry) * fileCount + 512));
    memset(uint32(fileEntrys), 0, sizeof(TFile_Entry) * fileCount + 512);
    memset(uint32(confirmedFileEntrys), 0, sizeof(TFile_Entry) * fileCount + 512);

    driver.storage.mgr.storage_read(volume^.device, volume^.sectorStart + 1, sizeof(TFile_Entry) * fileCount div 512, puint32(fileEntrys));

    baseAddress := volume^.sectorStart + 2 + ( (fileCount * sizeof(TFile_Entry)) div 512);

    for i := 0 to fileCount - 1 do begin
        if fileEntrys[i].attribues <> 0 then begin
            confirmedFileEntrys[confirmedFileEntrysCount] := fileEntrys[i];
            confirmedFileEntrysCount := confirmedFileEntrysCount + 1;
        end;
    end;

    //sort file table by start address using quicksort
    quicksort_start(confirmedFileEntrys, 0, confirmedFileEntrysCount - 1);

    //find free space big enough to fit size //TODO: make this work
    for i := 0 to confirmedFileEntrysCount - 1 do begin

        if confirmedFileEntrys[i+1].attribues = 0 then begin

            if confirmedFileEntrys[i].size = 0 then begin
                find_free_space := baseAddress;
                break;
            end else begin
                find_free_space := confirmedFileEntrys[i].start + confirmedFileEntrys[i].size;
                break;
            end;

            break;
        end;

        if confirmedFileEntrys[i].size <> 0 then begin
            if confirmedFileEntrys[i+1].start - (confirmedFileEntrys[i].start + confirmedFileEntrys[i].size) > size+1 then begin
                find_free_space := confirmedFileEntrys[i].start + confirmedFileEntrys[i].size;
                status^ := 0;
                break;
            end;
        end;
    end;

    Kfree(puint32(fileEntrys));
    Kfree(puint32(confirmedFileEntrys));
end;

procedure write_file(volume : PStorage_Volume; fileName : pchar; data : PuInt32; size : uint32; status : PuInt32);
var
    directories : PLinkedListBase;
    i : uint32;
    p : uint32;

    fileEntries : PFile_Entry;
    fileEntry : PFile_Entry;
    buffer : PuInt32;

    position : uint32;
    offset : uint32;

    fileCount : uint32 = 1000;

    exsists : boolean;

    elm : puint32;
begin
    push_trace('driver.storage.fs.flatfs.write_file');

    //load file table
    fileEntries := PFile_Entry(Kalloc(sizeof(TFile_Entry) * fileCount + 512));
    memset(uint32(fileEntries), 0, sizeof(TFile_Entry) * fileCount);

    driver.storage.mgr.storage_read(volume^.device, volume^.sectorStart + 1, sizeof(TFile_Entry) * fileCount div 512, puint32(fileEntries));

    //check if file exists else find free entry
    for i := 0 to fileCount - 1 do begin

        if stringEquals(fileEntries[i].name, fileName) then begin
            exsists := true;
            p:= i;
            break;
        end;

        if fileEntries[i].attribues = 0 then begin
            exsists := false;
            p:= i;
            break;
        end;
    end;

    //if entry is directory then exit
    if fileEntries[p].attribues and $10 = $10 then begin
        status^ := 1;
        exit;
    end;

    // //read file table cointaining entry of interest
    position := (p * sizeof(TFile_Entry)) div 512;

    //if file exists update entry else create new entry
    if exsists then begin
         //check if size is greater than current size
        if size > fileEntries[p].size then begin
            //find free space
            fileEntries[p].start := find_free_space(volume, size, status);
            fileEntries[p].size := size;
        end else begin
            //update size
            fileEntries[p].size := size;
        end;

    end else begin
        //find free space
        fileEntries[p].start := find_free_space(volume, size, status);
        fileEntries[p].size := size;
        fileEntries[p].attribues := $01;

        //add file name
        memcpy(uint32(fileName), uint32(@fileEntries[p].name), 14);

    end;

    //write file table
    driver.storage.mgr.storage_write(volume^.device, volume^.sectorStart + 1 , 1, puint32(@fileEntries[position]));

    //write file
    driver.storage.mgr.storage_write(volume^.device, fileEntries[p].start, size, data);
   
    //free buffer
    Kfree(puint32(fileEntries));
end;

procedure read_file(volume : PStorage_Volume; fileName : pchar; data : PuInt32; status : PuInt32);
var
    directories : PLinkedListBase;
    i : uint32;
    p : uint32;

    fileEntries : PFile_Entry;
    fileEntry : PFile_Entry;

    fileCount : uint32 = 1000;
    exsists : boolean = false;

    size : uint32;

begin
  
    //load file table
    fileEntries := PFile_Entry(Kalloc(sizeof(TFile_Entry) * fileCount + 512));
    memset(uint32(fileEntries), 0, sizeof(TFile_Entry) * fileCount);

    driver.storage.mgr.storage_read(volume^.device, volume^.sectorStart + 1, sizeof(TFile_Entry) * fileCount div 512, puint32(fileEntries));

    //check if file exists else exit
    for i := 0 to fileCount - 1 do begin

        if stringEquals(fileEntries[i].name, fileName) then begin
            exsists := true;
            p:= i;
            break;
        end;

    end;

    //if entry is directory then exit
    if fileEntries[p].attribues and $10 = $10 then begin
        status^ := 1;
        exit;
    end;

    //if entry is not found exit
    if fileEntries[i].attribues = 0 then begin
        exsists := false;
        p:= i;
        exit;
    end;

    //file size rounded up to nearest 512
    size := (fileEntries[p].size + 511) and -512;

    //read file
    data := Kalloc(size);
    driver.storage.mgr.storage_read(volume^.device, fileEntries[p].start, size, data);

    //free buffer
    Kfree(puint32(fileEntries));

    status^ := 0;
end;

{ Count free sectors on a FlatFS volume by scanning file entries. }
function countFreeFlatFSSectors(volume : PStorage_Volume) : uint32;
var
    buffer       : puint32;
    diskInfo     : PDisk_Info;
    sectorCount  : uint32;
    fileCount    : uint32;
    tableSectors : uint32;
    fileEntries  : PFile_Entry;
    usedSectors  : uint32;
    overhead     : uint32;
    i            : uint32;
begin
    countFreeFlatFSSectors := 0;

    buffer := puint32(kalloc(512));
    memset(uint32(buffer), 0, 512);
    driver.storage.mgr.storage_read(volume^.device, volume^.sectorStart, 1, buffer);

    diskInfo := PDisk_Info(buffer);
    sectorCount := diskInfo^.sectorCount;
    fileCount := diskInfo^.fileCount;
    kfree(buffer);

    if sectorCount = 0 then exit;

    tableSectors := (fileCount * sizeof(TFile_Entry)) div 512;
    overhead := 2 + tableSectors; { header + boundary + file table }

    usedSectors := 0;
    if fileCount > 0 then begin
        fileEntries := PFile_Entry(kalloc(sizeof(TFile_Entry) * fileCount + 512));
        memset(uint32(fileEntries), 0, sizeof(TFile_Entry) * fileCount);
        driver.storage.mgr.storage_read(volume^.device, volume^.sectorStart + 1,
            tableSectors, puint32(fileEntries));

        for i := 0 to fileCount - 1 do begin
            if fileEntries[i].attribues <> 0 then
                usedSectors := usedSectors + fileEntries[i].size;
        end;

        kfree(puint32(fileEntries));
    end;

    if sectorCount > (overhead + usedSectors) then
        countFreeFlatFSSectors := sectorCount - overhead - usedSectors
    else
        countFreeFlatFSSectors := 0;
end;

procedure detect_volumes(disk : PStorage_Device);
var
    buffer : puint32;
    bufSize : uint32;
    volume : PStorage_volume;
begin
    push_trace('driver.storage.fs.flatfs.detectVolumes()');

    bufSize := disk^.sectorSize;
    if bufSize < 512 then bufSize := 512;
    buffer := puint32(kalloc(bufSize));
    memset(uint32(buffer), 0, bufSize);

    if disk^.dispatchRead = nil then begin
        io.syslog.writestringln('FlatFS: detect_volumes: device has no read dispatch.');
        kfree(buffer);
        exit;
    end;

    driver.storage.mgr.storage_read(disk, 2, 1, buffer);

    if (PDisk_Info(buffer)^.signature = $0B00B1E5) then begin
        io.syslog.writestringln('FlatFS: volume found!');
        volume := PStorage_volume(kalloc(sizeof(TStorage_Volume)));
        memset(uint32(volume), 0, sizeof(TStorage_Volume));
        volume^.device       := disk;
        volume^.sectorStart  := 2;
        volume^.sectorSize   := 512;
        volume^.sectorCount  := PDisk_Info(buffer)^.sectorCount;
        volume^.filesystem   := @filesystem;
        volume^.freeSectors  := countFreeFlatFSSectors(volume);
        volume^.isBootDrive  := false;

        driver.storage.vol.mgr.register_volume(disk, volume);
    end;

    kfree(buffer);
end;

procedure delete_file(volume : PStorage_Volume; fileName : pchar; status : PuInt32);
var
    directories : PLinkedListBase;
    i : uint32;
    p : uint32;

    fileEntries : PFile_Entry;
    fileEntry : PFile_Entry;
    zeroBuffer : PuInt32;

    position : uint32;
    offset : uint32;

    fileCount : uint32 = 1000;

    exsists : boolean;
begin
  
    //load file table
    fileEntries := PFile_Entry(Kalloc(sizeof(TFile_Entry) * fileCount + 512));
    memset(uint32(fileEntries), 0, sizeof(TFile_Entry) * fileCount);

    driver.storage.mgr.storage_read(volume^.device, volume^.sectorStart + 1, sizeof(TFile_Entry) * fileCount div 512, puint32(fileEntries));

    //check if file exists else exit
    for i := 0 to fileCount - 1 do begin

        if stringEquals(fileEntries[i].name, fileName) then begin
            exsists := true;
            p:= i;
            break;
        end;

    end;

    //set position of entry
    position := (p * sizeof(TFile_Entry)) div 512;

    //if entry is directory then exit
    if fileEntries[p].attribues and $10 = $10 then begin
        status^ := 1;
        exit;
    end;

    //if entry is not found exit
    if fileEntries[i].attribues = 0 then begin
        exsists := false;
        p:= i;
        exit;
    end;

    //zero out file
    zeroBuffer := Kalloc(fileEntries[p].size);
    memset(uint32(zeroBuffer), 0, fileEntries[p].size);

    //write file
    driver.storage.mgr.storage_write(volume^.device, fileEntries[p].start, fileEntries[p].size, zeroBuffer);

    //free buffer
    Kfree(puint32(zeroBuffer));

    //zero out file table
    memset(uint32(@fileEntries[p]), 0, sizeof(TFile_Entry));
    
    //write file table
    driver.storage.mgr.storage_write(volume^.device, volume^.sectorStart + 1 , 1, puint32(@fileEntries[position]));

    //free buffer
    Kfree(puint32(fileEntries));

    status^ := 0;
    
end;

procedure delete_directory(volume : PStorage_Volume; directoryName : pchar; status : PuInt32);
var
    directories : PLinkedListBase;
    i : uint32;
    p : uint32;

    fileEntries : PFile_Entry;
    fileEntry : PFile_Entry;
    zeroBuffer : PuInt32;

    position : uint32;
    offset : uint32;

    fileCount : uint32 = 1000;

    exsists : boolean;
begin

    //load file table
    fileEntries := PFile_Entry(Kalloc(sizeof(TFile_Entry) * fileCount + 512));
    memset(uint32(fileEntries), 0, sizeof(TFile_Entry) * fileCount);

    driver.storage.mgr.storage_read(volume^.device, volume^.sectorStart + 1, sizeof(TFile_Entry) * fileCount div 512, puint32(fileEntries));

    //check if file exists else exit

    for i := 0 to fileCount - 1 do begin

        if stringEquals(fileEntries[i].name, directoryName) then begin
            exsists := true;
            p:= i;
            break;
        end;

    end;

    //if entry is not directory then exit
    if fileEntries[i].attribues and $10 <> $10 then begin
        status^ := 1;
        exit;
    end;

    //calculate position of directory in file table
    position := (p * sizeof(TFile_Entry)) div 512;

    //zero file table
    memset(uint32(@fileEntries[p]), 0, sizeof(TFile_Entry));

    //write file table
    driver.storage.mgr.storage_write(volume^.device, volume^.sectorStart + 1 , 1, puint32(@fileEntries[position]));

    //free buffer
    Kfree(puint32(fileEntries));

    status^ := 0;

end;

function identify_volume(volume : PStorage_Volume) : boolean;
var
    buffer  : puint32;
    bufSize : uint32;
begin
    push_trace('driver.storage.fs.flatfs.identify_volume');
    identify_volume := false;
    if volume^.device^.dispatchRead = nil then exit;

    bufSize := volume^.device^.sectorSize;
    if bufSize < 512 then bufSize := 512;
    buffer := puint32(kalloc(bufSize));
    memset(uint32(buffer), 0, bufSize);

    driver.storage.mgr.storage_read(volume^.device, volume^.sectorStart, 1, buffer);

    if (PDisk_Info(buffer)^.signature = $0B00B1E5) then begin
        identify_volume := true;
        volume^.freeSectors := countFreeFlatFSSectors(volume);
    end;

    kfree(buffer);
end;

function readDirectoryEntries(volume : PStorage_Volume; directory : pchar; status : PuInt32) : PLinkedListBase;
var
    entries     : PLinkedListBase;
    fileEntrys  : PFile_Entry;
    i           : uint32;
    compString  : PChar;
    afterString : PChar;
    slash       : PChar;
    fileCount   : uint32;
    dirEntry    : PDirectory_Entry;
    elm         : void;
    slashArray  : array[0..1] of char;
begin
    push_trace('driver.storage.fs.flatfs.readDirectoryEntries');
    fileCount := 1000;
    slashArray[0] := '/';
    slashArray[1] := char(0);

    entries := LL_New(sizeof(TDirectory_Entry));

    fileEntrys := PFile_Entry(Kalloc(sizeof(TFile_Entry) * fileCount + 512));
    driver.storage.mgr.storage_read(volume^.device, volume^.sectorStart + 1,
        sizeof(TFile_Entry) * fileCount div 512, puint32(fileEntrys));

    slash := stringNew(2);
    memcpy(uint32(@slashArray), uint32(slash), 1);

    for i := 0 to fileCount - 1 do begin
        if uint32(fileEntrys[i].name[0]) = 0 then break;

        compString := stringSub(fileEntrys[i].name, 0, stringSize(directory));
        afterString := stringSub(fileEntrys[i].name, stringSize(directory),
            stringSize(fileEntrys[i].name) - 1);

        if stringEquals(compString, directory) and
           (not stringContains(afterString, slash)) then begin
            elm := LL_Add(entries);
            dirEntry := PDirectory_Entry(elm);
            dirEntry^.fileName := stringCopy(afterString);
            if fileEntrys[i].attribues and $10 = $10 then
                dirEntry^.entryType := TDirectory_Entry_Type.directoryEntry
            else
                dirEntry^.entryType := TDirectory_Entry_Type.fileEntry;
            dirEntry^.fileSize     := fileEntrys[i].size;
            dirEntry^.modifiedDate := 0;
            dirEntry^.modifiedTime := 0;
            dirEntry^.attributes   := fileEntrys[i].attribues;
        end;

        kfree(void(compString));
        kfree(void(afterString));
    end;

    Kfree(puint32(fileEntrys));
    kfree(void(slash));
    readDirectoryEntries := entries;
end;

procedure init();
begin
    push_trace('driver.storage.fs.flatfs.init()');
    filesystem.sName:= 'driver.storage.fs.flatfs'; 
    filesystem.system_id:= $02; 
    filesystem.readDirCallback:= @readDirectoryEntries;
    // filesystem.createDirCallback:= @writeDirectoryGen;
    filesystem.createcallback:= @create_volume;
    filesystem.detectcallback:= @detect_volumes;
    filesystem.identifyCallback:= @identify_volume;
    // filesystem.writecallback:= @writeFile;
    // filesystem.readcallback := @readFile;

    driver.storage.fs.mgr.register_filesystem(@filesystem);
end;

    
end.
