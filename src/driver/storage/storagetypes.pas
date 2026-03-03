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
	Driver->Storage->Include->storagetypes - Structs & Data Shared Across Storage Drivers.
	
	@author(Aaron Hance <ah@aaronhance.me>)
}
unit storagetypes;

interface

uses
    lists;

type

    { Controller types }
    TControllerType = (
        ControllerATA, 
        ControllerATAPI,
        ControllerUSB,
        ControllerAHCI,
        ControllerAHCI_ATAPI,
        ControllerNVMe,
        ControllerNET, 
        ControllerRAM,
        ControllerSCSI
        );

    { Filesystem type identifiers }
    TFileSystemType = (
        FileSystemFAT32,
        FileSystemExFAT,
        FileSystemEXT,
        FileSystemEXT2,
        FileSystemCDFS,
        FileSystemOther
        );

    { Directory entry types }
    TDirectory_Entry_Type = (directoryEntry, fileEntry, mountEntry);

    { Storage error codes — shared between VFS and filesystem drivers }
    TError          = (eNone, eUnknown, eFileInUse, eWriteOnly, eReadOnly, eFileDoesNotExist, 
                       eDirectoryDoesNotExist, eDirectoryAlreadyExists, eNotADirectory, 
                       eDiskFull, eFilenameTooLong, eDirectoryFull, eInvalidPath, ePermissionDenied,
                       eInvalidFileName, eInvalidFileExtension, eTooManyOpenFiles, eDirectoryNotEmpty);
    PError          = ^TError;

    { Forward declarations }
    PStorage_device  = ^TStorage_Device;
    PStorage_Volume  = ^TStorage_Volume;
    PFilesystem      = ^TFilesystem;
    PDirectory_Entry = ^TDirectory_Entry;
    PDrive_Error     = ^TDrive_Error;

    { Block I/O callback for raw device access }
    PPHIOHook  = procedure(drive : PStorage_device; addr : uint32; sectors : uint32; buffer : puint32);
    PPHIOHook_ = procedure;

    { Completion callback fired from IRQ context after async block I/O.
      Must be short — set a flag or post to a queue.
      Never call kalloc/kfree/VFS from within this callback. }
    TStorageCompletion = procedure(success : boolean; userdata : puint32);

    { Async block I/O callback — issues the command and returns immediately;
      calls completion from IRQ context when done. }
    PPHIOHookAsync = procedure(drive : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32; completion : TStorageCompletion; userdata : puint32);

    { Poll callback — called by sync bridge after each hlt wake-up to process
      completions when the hardware interrupt isn't delivered through the PIC. }
    PPPollHook = procedure;

    { Filesystem callback types }
    PPWriteHook     = procedure(volume : PStorage_volume; directory : pchar; entry : PDirectory_Entry; byteCount : uint32; buffer : puint32; statusOut : puint32);
    PPReadHook      = function(volume : PStorage_Volume; directory : pchar; fileName : pchar; buffer : puint32; bytecount : puint32) : uint32;
    PPCreateHook    = procedure(volume : PStorage_volume; start : uint32; size : uint32; config : puint32);
    PPDetectHook    = procedure(disk : PStorage_Device);
    PPCreateDirHook  = procedure(volume : PStorage_volume; directory : pchar; dirname : pchar; attributes : uint32; status : puint32);
    PPReadDirHook    = function(volume : PStorage_volume; directory : pchar; status : puint32) : PLinkedListBase;
    PPDeleteFileHook = procedure(volume : PStorage_Volume; filePath : pchar; status : puint32);
    PPDeleteDirHook  = procedure(volume : PStorage_Volume; path : pchar; status : puint32);
    PPIdentifyHook   = function(volume : PStorage_Volume) : boolean;
    { Offset-based read: reads byteCount bytes starting at byte offset into the file.
      Returns the number of bytes actually read.
      Filesystems that do not implement this leave the field nil and VFS falls back
      to the load-all readCallback behaviour. }
    PPReadOffsetHook = function(volume : PStorage_Volume; directory : pchar; fileName : pchar; offset : uint32; buffer : puint32; byteCount : uint32) : uint32;

    byteArray8  = array[0..7] of char;
    PByteArray8 = ^byteArray8;

    { Generic storage device }
    TStorage_Device = record
        id               : uint8;
        controller       : TControllerType;
        controllerId0    : uint32;
        writable         : boolean;
        volumes          : PDList;
        writeCallback    : PPHIOHook;
        readCallback     : PPHIOHook;
        { Async block I/O callbacks — nil if the driver does not support async }
        readCallbackAsync  : PPHIOHookAsync;
        writeCallbackAsync : PPHIOHookAsync;
        { Poll callback — processes pending completions inline when the
          hardware interrupt is not delivered. Called from storage_read/write
          sync bridge after each hlt wake-up.  nil if not needed. }
        pollCallback       : PPPollHook;
        maxSectorCount   : uint32;
        sectorSize       : uint32; //in bytes
        start            : uint32; //start of device in sectors
    end;

    { Filesystem driver descriptor }
    TFilesystem = record
        sName              : pchar;
        system_id          : uint8;
        writeCallback      : PPWriteHook;
        readCallback       : PPReadHook;
        createCallback     : PPCreateHook;
        detectCallback     : PPDetectHook;
        createDirCallback  : PPCreateDirHook;
        readDirCallback    : PPReadDirHook;
        deleteFileCallback : PPDeleteFileHook;
        deleteDirCallback  : PPDeleteDirHook;
        identifyCallback   : PPIdentifyHook;
        { Offset-based read for streaming mode — nil if not implemented }
        readOffsetCallback : PPReadOffsetHook;
    end;

    { Generic storage volume }
    TStorage_Volume = record
        id           : uint32;
        device       : PStorage_device;
        sectorStart  : uint32;
        sectorSize   : uint32;
        sectorCount  : uint32;
        freeSectors  : uint32;
        filesystem   : PFilesystem;
        isBootDrive  : boolean;
    end;

    { Generic directory entry }
    TDirectory_Entry = record
        fileName  : pchar;
        entryType : TDirectory_Entry_Type;
    end;

    TDrive_Error = record 
        code : uint16;
        description : pchar;
        recoverable : boolean;
    end;


implementation


end.
