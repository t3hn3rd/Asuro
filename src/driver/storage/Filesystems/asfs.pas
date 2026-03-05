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
	Drivers->Storage->ASFS - Asuro Filesystem Driver.
	
	@author(Aaron Hance <ah@aaronhance.me>)
}
unit asfs;

interface

uses
    syslog,
    lists,
    lmemorymanager,
    rtc,
    serial,
    storagemanagement,
    storagemanager,
    strings,
    stdio,
    tracer,
    util;

type

    TFilesystemRecord = bitpacked record 
        magicNumber : uint32;
        sectorSize : uint16;
        sectorsPerTable : uint8;
        totalSectors : uint32;
        volumeLabel : array[0..15] of uint8;
        endOfData : uint32;
    end;
    PFilesystemRecord = ^TFilesystemRecord;

    //File or folder entry for file table
    TFileEntry = bitpacked record 
        filename : array[0..15] of uint8;
        lastWriteDate : array[0..3] of uint8; // year (2000 + x), month, day, hour
        lastReadDate : array[0..3] of uint8;
        attributes : uint8; // 0 null entry, 1 file, 2 folder, 3 this folder, 4 parent folder, 5 table continuation, 6 volume root
        extension : array[0..6] of uint8;
        location : uint32; // location on disk
        numSectors : uint32; // size in sectors
    end;
    PFileEntry = ^TFileEntry;

var 
    filesystem : TFilesystemRecord;
    //nullsectors : array[0..1024] of TFileEntry; //cache some null entry pointers for effeciency sake

procedure init;
procedure create_volume(disk : PStorage_Device; sectors : uint32; start : uint32; config : puint32);
procedure detect_volumes(disk : PStorage_Device);

implementation

procedure init() begin
    push_trace('asfs.init()');
    filesystem.sName:= 'asfs'; 
    //filesystem.readDirCallback:= @readDirectoryGen;
    //filesystem.createDirCallback:= @writeDirectoryGen;
    filesystem.createcallback:= @create_volume;
    filesystem.detectcallback:= @detect_volumes;
    //filesystem.writecallback:= @writeFile;

    storagemanagement.register_filesystem(@filesystem);
end;

procedure create_volume(disk : PStorage_Device; sectors : uint32; start : uint32; config : puint32) 
var
    filesystemRecord : PFilesystemRecord;
    fileEntry : PFileEntry;
    buffer : puint32;

    thisArray     : byteArray8 = ('.',' ',' ',' ',' ',' ',' ',' ');
    parentArray   : byteArray8 = ('.','.',' ',' ',' ',' ',' ',' ');
begin

    buffer := puint32(kalloc(disk^.sectorSize))
    memset(uint32(buffer), 0, disk^.sectorSize);
    PFilesystemRecord := PFilesystemRecord(buffer);

    filesystemRecord^.magicNumber     := $A2F2;
    filesystemRecord^.sectorSize      := disk^.sectorsize;
    filesystemRecord^.sectorsPerTable := 8;
    filesystemRecord^.totalSectors    := sectors;
    filesystemRecord^.endOfData       := filesystemRecord.sectorsPerTable; 
    //filesystemRecord.volumeLabel     := config^

    storagemanager.storage_write(disk, start, 1, buffer);
    memset(uint32(buffer), 0, disk^.sectorSize);

    fileEntry            := PFileEntry(buffer)[0];
    fileEntry^.filename   := thisArray;
    fileEntry^.attributes := 6;
    fileEntry^.location   := 1;

    fileEntry            := PFileEntry(buffer)[1];
    fileEntry^.filename   := parentArray;
    fileEntry^.attributes := 0;
    fileEntry^.location   := 1;

    storagemanager.storage_write(disk, start + 1, 1, buffer);


end;


procedure detect_volumes(disk : PStorage_Device) begin
end;