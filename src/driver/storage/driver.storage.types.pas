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
	Driver->Storage->Include->driver.storage.types - Structs & Data Shared Across Storage Drivers.
	
	@author(Aaron Hance <ah@aaronhance.me>)
}
unit driver.storage.types;

interface

uses
    core.ds.types,
    core.ds.lists;

type

    { Controller core.types }
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

    { Directory entry core.types }
    TDirectory_Entry_Type = (directoryEntry, fileEntry, mountEntry);

    { Storage error codes — shared across I/O layer, drivers, FS, and VFS }
    TError = (
        { Success }
        eNone,

        { Generic }
        eUnknown,                 { catch-all — replace with specific code wherever possible }
        eNotSupported,            { operation not supported (e.g., write on RO FS, seek on non-stream) }
        eOutOfMemory,             { kalloc/heap allocation failed }
        eInvalidArgument,         { nil pointer, zero-length, or otherwise invalid parameter }

        { File errors }
        eFileInUse,               { file is open by another process (relevant for delete/unmount) }
        eFileDoesNotExist,        { path resolves but file not found }
        eInvalidFileName,         { illegal characters or format in filename }
        eInvalidFileExtension,    { reserved — FS rejects extension }
        eFilenameTooLong,         { exceeds FS name length limit }

        { Directory errors }
        eDirectoryDoesNotExist,   { directory component of path not found }
        eDirectoryAlreadyExists,  { CreateDirectory target already exists }
        eDirectoryNotEmpty,       { RemoveDirectory on non-empty dir }
        eDirectoryFull,           { FS directory entry table full }
        eNotADirectory,           { path component is a file, not a dir }

        { Access / mode errors }
        eWriteOnly,               { attempted read on write-only handle }
        eReadOnly,                { attempted write on read-only handle or read-only FS }
        ePermissionDenied,        { generic access denied }

        { Path errors }
        eInvalidPath,             { malformed path string }

        { VFS / FD errors }
        eTooManyOpenFiles,        { per-process FD table full }
        eInvalidHandle,           { TFileHandle does not refer to an open FD }

        eFileNotLoaded,           { ReadFile on a pre-load handle whose data is not yet loaded }
        eAlreadyExists,           { generic: target name already exists (symlink, file, etc.) }

        { Disk / capacity errors }
        eDiskFull,                { FS reports no free clusters/blocks }

        { I/O layer errors }
        eIOError,                 { generic I/O failure (DMA error, bad status) }
        eIOTimeout,               { driver timed out waiting for hardware }
        eIOCancelled,             { request cancelled (task killed or device removed) }
        eDeviceNotReady,          { device exists but not ready (spin-up, reset) }
        eDeviceRemoved,           { device hot-unplugged (driver.bus.usb disconnect) }
        eDeviceNotFound,          { submit_io with nil or unregistered device }
        eQueueFull,               { per-device CFIFO cannot accept more requests }
        eNoFreeSlot,              { driver has no free command slot — transient, retry }

        { Filesystem integrity errors }
        eCorruptFilesystem,       { bad cluster chain, invalid FAT entry, broken metadata }
        eBadSector,               { sector-level CRC/ECC failure }

        { Mount / volume errors }
        eAlreadyMounted,          { mount point already has a volume attached }
        eNotMounted,              { unmount target is not a mount point }
        eUnsupportedFilesystem,   { no FS driver could identify the volume }
        eInvalidPartitionTable,   { GPT/mbr signature or CRC validation failed }
        eVolumeNotFound           { volume ID/path does not match any known volume }
    );
    PError = ^TError;

    { Forward declarations }
    PStorage_device  = ^TStorage_Device;
    PStorage_Volume  = ^TStorage_Volume;
    PFilesystem      = ^TFilesystem;
    PDirectory_Entry = ^TDirectory_Entry;
    PDrive_Error     = ^TDrive_Error;
    PIORequest       = ^TIORequest;

    { === Driver dispatch type (Phase 2+) === }

    { Unified driver dispatch — driver receives PIORequest, fires complete_io on finish }
    TDriverDispatch = procedure(device : PStorage_Device; request : PIORequest);

    { === I/O callback type === }

    { Completion callback used across storage/VFS async APIs.
      error = eNone on success; specific code on failure.
      userdata is the opaque pointer passed by the submitter.
      Context is API-specific: some callers complete from ISR context, others
      from task/worker context, and some may invoke the callback immediately. }
    TIOCallback = procedure(error : TError; userdata : pointer);

    { Filesystem callback core.types }
    PPCreateHook    = procedure(volume : PStorage_volume; start : uint32; size : uint32; config : puint32);
    PPCreateAsyncHook = procedure(volume : PStorage_volume; start : uint32; size : uint32; config : puint32; callback : TIOCallback; callbackData : pointer);
    PPDetectHook    = procedure(disk : PStorage_Device);
    PPCreateDirHook  = procedure(volume : PStorage_volume; directory : pchar; dirname : pchar; attributes : uint32; status : puint32);
    PPReadDirHook    = function(volume : PStorage_volume; directory : pchar; status : puint32) : PLinkedListBase;
    PPDeleteFileHook = procedure(volume : PStorage_Volume; filePath : pchar; status : puint32);
    PPDeleteDirHook  = procedure(volume : PStorage_Volume; path : pchar; status : puint32);
    PPIdentifyHook   = function(volume : PStorage_Volume) : boolean;
    PPRenameFileHook = procedure(volume : PStorage_Volume; filePath : pchar; newName : pchar; status : puint32);
    { Offset-based read: reads byteCount bytes starting at byte offset into the file.
      Returns the number of bytes actually read.  ctx is the opaque per-file
      context returned by openFileCallback (nil when called without a handle). }
    PPReadOffsetHook = function(volume : PStorage_Volume; directory : pchar; fileName : pchar; offset : uint32; buffer : puint32; byteCount : uint32; ctx : pointer) : uint32;
    { Offset-based write: writes byteCount bytes starting at byte offset into the file.
      Returns the number of bytes actually written.
      Filesystems that do not implement this leave the field nil; VFS returns 0
      for stream-mode writes on volume FDs. }
    PPWriteOffsetHook = function(volume : PStorage_Volume; directory : pchar; fileName : pchar; offset : uint32; buffer : puint32; byteCount : uint32; ctx : pointer) : uint32;
    { Async offset-based read/write hooks. Implementations must return immediately
      and fire callback when the transfer completes. BytesRead/BytesWritten may be
      nil; if provided, implementations store the actual completed byte count. }
    PPReadOffsetAsyncHook = procedure(volume : PStorage_Volume; directory : pchar; fileName : pchar; offset : uint32; buffer : puint32; byteCount : uint32; ctx : pointer; bytesRead : puint32; callback : TIOCallback; callbackData : pointer);
    PPWriteOffsetAsyncHook = procedure(volume : PStorage_Volume; directory : pchar; fileName : pchar; offset : uint32; buffer : puint32; byteCount : uint32; ctx : pointer; bytesWritten : puint32; callback : TIOCallback; callbackData : pointer);
    { File size query: returns the size in bytes of the named file.
      Returns 0 if the file does not exist or has zero length. }
    PPFileSizeHook = function(volume : PStorage_Volume; directory : pchar; fileName : pchar) : uint32;
    { Per-file open hook: called by VFS on OpenFile to create FS-level cached
      metadata.  Returns an opaque pointer stored in the FD and passed as ctx
      to read/write hooks.  Also returns the current file size through the
      var parameter.  Returning nil is legal (disables per-call fast-path). }
    PPOpenFileHook = function(volume : PStorage_Volume; directory : pchar; fileName : pchar; var fileSize : uint32) : pointer;
    { Per-file close hook: frees the context allocated by openFileCallback. }
    PPCloseFileHook = procedure(ctx : pointer);

    { === Async filesystem hook core.types ===
      Each mirrors the corresponding sync hook but receives a TIOCallback + callbackData.
      The implementation must return immediately; the callback is fired when the
      operation completes from worker-process context (IF=1, safe to block). }
    PPLinkedListBase      = ^PLinkedListBase;   { needed for PPReadDirAsyncHook parameter }
    PPCreateDirAsyncHook  = procedure(volume : PStorage_Volume; directory : pchar; dirname : pchar; attributes : uint32; status : puint32; callback : TIOCallback; callbackData : pointer);
    PPReadDirAsyncHook    = procedure(volume : PStorage_Volume; directory : pchar; resultList : PPLinkedListBase; status : puint32; callback : TIOCallback; callbackData : pointer);

    { === I/O Request core.types === }

    TIORequestType  = (ioRead, ioWrite);
    TIORequestState = (iosPending, iosDispatched, iosComplete, iosCancelled, iosError);

    { Core I/O request — one per disk operation in flight }
    TIORequest = record
        RequestType  : TIORequestType;
        State        : TIORequestState;
        Device       : PStorage_Device;
        LBA          : uint32;
        SectorCount  : uint32;
        Buffer       : pointer;
        ByteCount    : uint32;          { actual bytes transferred (filled by driver) }
        Error        : TError;          { eNone on success; specific code on failure }
        Caller       : pointer;         { PProcessContext — owning process for sleep/wake (blocking path) }
        UserData     : pointer;         { points back to caller's stack-local request (blocking path) }
        Callback     : TIOCallback;     { async completion callback (nil for blocking path) }
        CallbackData : pointer;         { opaque data passed to Callback }
    end;

    byteArray8  = array[0..7] of char;
    PByteArray8 = ^byteArray8;

    { Generic storage device }
    TStorage_Device = record
        id               : uint8;
        controller       : TControllerType;
        controllerId0    : uint32;
        writable         : boolean;
        removed          : boolean;       { true if device was hot-unplugged }
        volumes          : PDList;

        { === New dispatch interface (Phase 2+) === }
        dispatchRead     : TDriverDispatch;   { nil if driver not yet migrated }
        dispatchWrite    : TDriverDispatch;   { nil if driver not yet migrated }
        requestQueue     : PCFIFOQueue;       { per-device I/O request CFIFO }
        activeCount      : uint32;            { number of commands currently dispatched to HW }
        maxActive        : uint32;            { max concurrent commands (NCQ depth) }

        maxSectorCount   : uint32;
        sectorSize       : uint32; //in bytes
        start            : uint32; //start of device in sectors
        cachedMBR        : pointer;           { cached mbr data, nil if not yet read }
        isBootDevice     : boolean;           { true if this is the device GRUB booted from }
    end;

    { Filesystem driver descriptor }
    TFilesystem = record
        sName              : pchar;
        system_id          : uint8;
        createCallback     : PPCreateHook;
        detectCallback     : PPDetectHook;
        createDirCallback  : PPCreateDirHook;
        readDirCallback    : PPReadDirHook;
        deleteFileCallback : PPDeleteFileHook;
        deleteDirCallback  : PPDeleteDirHook;
        identifyCallback   : PPIdentifyHook;
        { Offset-based read for streaming mode — nil if not implemented }
        readOffsetCallback : PPReadOffsetHook;
        { Offset-based write for streaming mode — nil if not implemented }
        writeOffsetCallback : PPWriteOffsetHook;
        { Async offset-based read/write for streaming mode — nil if not implemented }
        readOffsetAsyncCallback : PPReadOffsetAsyncHook;
        writeOffsetAsyncCallback : PPWriteOffsetAsyncHook;
        { File size query — returns size in bytes without loading the file }
        fileSizeCallback : PPFileSizeHook;
        { Async format — nil if FS only supports synchronous create }
        createAsyncCallback : PPCreateAsyncHook;
        createDirAsyncCallback  : PPCreateDirAsyncHook;
        readDirAsyncCallback    : PPReadDirAsyncHook;
        renameFileCallback      : PPRenameFileHook;
        { Per-file open/close — nil if FS does not cache per-file metadata }
        openFileCallback        : PPOpenFileHook;
        closeFileCallback       : PPCloseFileHook;
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
        fsPrivate    : pointer;      { FS-driver private data (e.g. PFATCache for FAT32) }
    end;

    { Generic directory entry }
    TDirectory_Entry = record
        fileName     : pchar;
        entryType    : TDirectory_Entry_Type;
        fileSize     : uint32;
        modifiedDate : uint16;   { FAT-style: bits 15-9=year-1980, 8-5=month, 4-0=day }
        modifiedTime : uint16;   { FAT-style: bits 15-11=hour, 10-5=min, 4-0=sec/2 }
        attributes   : uint8;    { FS-specific attribute bits }
    end;

    TDrive_Error = record 
        code : uint16;
        description : pchar;
        recoverable : boolean;
    end;


implementation


end.
