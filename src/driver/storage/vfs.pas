//  Copyright 2021 Kieron Morris
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
    Driver->Storage->VFS - Virtual File System

    @author(Kieron Morris kjm@kieronmorris.me)
    @author(Aaron Hance ah@aaronhance.me)
}
unit vfs;

interface

uses
    console,
    hashmap,
    lists,
    lmemorymanager,
    storagetypes,
    strings,
    tracer;

type
    TOpenMode       = (omReadOnly, omWriteOnly, omReadWrite, omStream);
    TWriteMode      = (wmRewrite, wmAppend, wmNew);
    TIsPathValid    = (pvInvalid, pvFile, pvDirectory);
    TRegError       = (pvUnknown, pvNotRegistered, pvRegistered, pvUnregistered);

    TFileHandle = uint32;

    TObjectType = (otVDIRECTORY, otDRIVE, otDEVICE, otVFILE, otMOUNT, otDIRECTORY, otFILE);
    TVFSMount = record
        Path       : pchar;
        ObjectType : TObjectType;
        Reference  : void;
    end;
    PVFSMount = ^TVFSMount;
    PVFSObject = ^TVFSObject;
    TVFSObject = record
        Parent     : PVFSObject;
        ObjectName : pchar;
        ObjectType : TObjectType;
        Reference  : void;
    end;

var
    Root              : PVFSObject;
    CurrentDirectory  : pchar = nil;
    PushPopDirectory  : PLinkedListBase;

procedure init();
Function OpenFile(Filename : pchar; OpenMode : TOpenMode; WriteMode : TWriteMode; Lock : Boolean; Error : PError) : TFileHandle;
function WriteFile(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
function ReadFile(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
function CloseFile(Filehandle : TFileHandle) : boolean;
function FileSize(Filename : pchar; error : puint8) : uint32;
function CreateDirectory(Handle : uint32; Path : pchar) : TError;
function GetDirectories(Handle : uint32; Path : pchar) : PHashMap;
function PathValid(Path : pchar) : TIsPathValid;
function changeDirectory(Path : pchar) : TIsPathValid;
function getWorkingDirectory : pchar;
function makeAbsolutePathFrom(Path : pchar; BaseDir : pchar) : pchar;
function resolvePathFrom(Path : pchar; BaseDir : pchar) : TIsPathValid;
function GetDirectoryListingFrom(Path : pchar; BaseDir : pchar) : PHashMap;
function changeDirectoryFrom(Path : pchar; BaseDir : pchar; var NewDir : pchar) : TIsPathValid;
function MakeAbsolutePath(Path : PChar) : pchar;

//VFS Functions
function newVirtualDirectory(Path : pchar) : TError;

//Volume Mount Functions
function mountVolume(mountPath : pchar; volume : PStorage_Volume) : TRegError;
procedure auto_mount_volumes(); //TODO, need to change this when os can be installled to disk and have a config file

implementation

uses
    filesystemmanager,
    terminal,
    util,
    volumemanager;

{ Internal Functions }

function makeRelative(Path : pchar; From : pchar) : pchar;
var
    Result : pchar;
    Tmp    : pchar;

begin
    tracer.push_trace('vfs.makeRelative.enter');
    Result:= nil;
    if (Path = nil) or (From = nil) then begin
        makeRelative:= nil;
        tracer.push_trace('vfs.makeRelative.exit');
        exit;
    end;
    if StringEquals(Path, From) then begin
        Result:= stringNew(1);
        Result[0]:= '/';
    end else begin
        if (StringSize(From) > 0) and StringContains(Path, From) then begin
            Tmp:= Path;
            inc(tmp, StringSize(From));
            Result:= stringCopy(tmp);
        end;
    end;
    makeRelative:= Result;
    tracer.push_trace('vfs.makeRelative.exit');
end;

function createDummyObject(ObjType : TObjectType) : PVFSObject;
begin
    tracer.push_trace('vfs.createDummyObject.enter');
    createDummyObject:= PVFSObject(kalloc(sizeof(TVFSObject)));
    createDummyObject^.ObjectType:= ObjType;
    tracer.push_trace('vfs.createDummyObject.exit');
end;

function  createVirtualDirectory : PVFSObject;
begin
    tracer.push_trace('vfs.createVirtualDirectory.enter');
    createVirtualDirectory:= PVFSObject(kalloc(sizeof(TVFSObject)));
    createVirtualDirectory^.ObjectType:= otVDIRECTORY;
    createVirtualDirectory^.Reference:= void(hashmap.newEx(512, 0.5));
    tracer.push_trace('vfs.createVirtualDirectory.exit');
end;

function CombineToAbsolutePath(List : PLinkedListBase; Count : uint32) : pchar;
var
    new, old : pchar;
    i : uint32;

begin
    tracer.push_trace('vfs.CombineToAbsolutePath.enter');
    CombineToAbsolutePath:= nil;
    if (Count > 0) and (STRLL_Size(List) < (Count - 1)) then begin
        tracer.push_trace('vfs.CombineToAbsolutePath.shortexit');
        exit;
    end;
    new:= stringNew(1);
    new[0]:= '/';
    If Count > 0 then begin
        for i:=0 to Count-1 do begin
            if i = 0 then begin
                old:= StringConcat(new, STRLL_Get(List, i));
            end else begin
                old:= StringConcat(new, '/');
                kfree(void(new));
                new:= old;
                old:= StringConcat(new, STRLL_Get(List, i));
            end;
            kfree(void(new));
            new:= old;
        end;
    end;
    CombineToAbsolutePath:= new;
    tracer.push_trace('vfs.CombineToAbsolutePath.exit');
end;

function evaluatePath(Path : pchar) : pchar;
var
    List : PLinkedListBase;
    i : uint32;
    elm : pchar;

begin
    tracer.push_trace('vfs.evaluatePath.enter');
    List:= STRLL_FromString(Path, '/');
    { Forward-scan with stack semantics: safe for consecutive '..' sequences }
    i := 0;
    while i < STRLL_Size(List) do begin
        elm := STRLL_Get(List, i);
        if (elm <> nil) and StringEquals(elm, '..') then begin
            STRLL_Delete(List, i);        { remove '..' }
            if i > 0 then begin
                STRLL_Delete(List, i - 1);  { remove preceding segment }
                if i > 0 then i := i - 1;  { rewind }
            end;
        end else if (elm <> nil) and StringEquals(elm, '.') then begin
            STRLL_Delete(List, i);        { remove '.' — index stays }
        end else begin
            i := i + 1;
        end;
    end;
    evaluatePath:= CombineToAbsolutePath(List, STRLL_Size(List));
    STRLL_Free(List);
    tracer.push_trace('vfs.evaluatePath.exit');
end;

function getAbsolutePath(Obj : PVFSObject) : pchar;
var
    buf, new, old : pchar;
    iter : PVFSObject;

begin
    tracer.push_trace('vfs.getAbsolutePath.enter');

    buf:= nil;

    iter:= Obj;
    if iter <> nil then begin
        if iter^.Parent = nil then buf:= stringCopy(iter^.ObjectName);
        while iter^.Parent <> nil do begin
            new:= StringConcat('/', iter^.ObjectName);
            if buf = nil then
                buf:= stringCopy(new)
            else begin
                old:= buf;
                buf:= StringConcat(new, buf);
                kfree(void(old));
            end;
            kfree(void(new));
            iter:= iter^.Parent;
        end;
    end;

    getAbsolutePath:= buf;

    tracer.push_trace('vfs.getAbsolutePath.exit');
end;

function MakeAbsolutePath(Path : PChar) : pchar;
var
    AbsPath : pchar;
    TempPath : pchar;

begin
    tracer.push_trace('vfs.MakeAbsolutePath.enter');
    if (Path = nil) or (Path[0] = char(0)) then begin
        MakeAbsolutePath := stringNew(1);
        MakeAbsolutePath[0] := '/';
        tracer.push_trace('vfs.MakeAbsolutePath.exit');
        exit;
    end;
    if Path[0] = '/' then AbsPath:= stringCopy(Path) else begin
        if (CurrentDirectory = nil) or (StringSize(CurrentDirectory) = 0) then begin
            TempPath := stringNew(1);
            TempPath[0] := '/';
        end else begin
            if CurrentDirectory[StringSize(CurrentDirectory)-1] <> '/' then
                TempPath:= StringConcat(CurrentDirectory, '/')
            else
                TempPath:= stringCopy(CurrentDirectory);
        end;
        AbsPath:= StringConcat(TempPath, Path);
        kfree(void(TempPath));
    end;
    MakeAbsolutePath:= AbsPath;
    tracer.push_trace('vfs.MakeAbsolutePath.exit');
end;

function GetObjectFromPath(path : pchar) : PVFSObject;
var
    Obj         : PVFSObject;
    NewObj      : PVFSObject;
    SplitPath   : PLinkedListBase;
    ht          : PHashMap;
    i           : uint32;
    item        : pchar;

begin
    tracer.push_trace('vfs.GetObjectFromPath.enter');
    SplitPath:= STRLL_FromString(path, '/');                                                        
    Obj:= Root;                                                                                     
    if STRLL_Size(SplitPath) > 0 then begin                                                         
        for i:=0 to STRLL_Size(SplitPath)-1 do begin                                                
            { Only otVDIRECTORY objects carry a hashmap in Reference }
            if Obj^.ObjectType <> otVDIRECTORY then begin
                break;
            end;
            ht:= PHashMap(Obj^.Reference);
            if ht = nil then begin
                GetObjectFromPath:= nil;
                STRLL_Free(SplitPath);
                tracer.push_trace('vfs.GetObjectFromPath.shortexit_nil_ref');
                exit;
            end;
            item:= STRLL_Get(SplitPath, i);
            NewObj:= PVFSObject(hashmap.get(ht, item));                                            
            if NewObj = nil then begin                                                              
                GetObjectFromPath:= nil;
                STRLL_Free(SplitPath);
                tracer.push_trace('vfs.GetObjectFromPath.shortexit_1');
                exit;
            end;
            Case NewObj^.ObjectType of
                otVDIRECTORY,otMOUNT:begin                                                          
                    Obj:= NewObj;
                end;
                else begin                                                                         
                    Obj:= NewObj;
                    tracer.push_trace('vfs.GetObjectFromPath.shortexit_2');
                    Break;
                end;
            end;
        end;
    end;                                                                                           
    STRLL_Free(SplitPath);
    GetObjectFromPath:= Obj;
    tracer.push_trace('vfs.GetObjectFromPath.exit');
end;

Procedure ChangeCurrentDirectoryValue(new : pchar);
begin
    tracer.push_trace('vfs.ChangeCurrentDirectoryValue.enter');
    if CurrentDirectory <> nil then kfree(void(CurrentDirectory));
    CurrentDirectory:= nil;
    CurrentDirectory:= stringCopy(new);
    tracer.push_trace('vfs.ChangeCurrentDirectoryValue.exit');
end;

{ Volume helper: convert readDirCallback results to a VFS hashmap }

function volumeGetDirectories(vol : PStorage_Volume; RelPath : pchar; Parent : PVFSObject) : PHashMap;
var
    dirList    : PLinkedListBase;
    resultMap  : PHashMap;
    status     : puint32;
    entry      : PDirectory_Entry;
    newObj     : PVFSObject;
    i          : uint32;

begin
    tracer.push_trace('vfs.volumeGetDirectories.enter');
    volumeGetDirectories := nil;

    if vol = nil then exit;
    if vol^.filesystem = nil then exit;
    if vol^.filesystem^.readDirCallback = nil then exit;

    status := puint32(kalloc(4));
    status^ := 0;
    dirList := vol^.filesystem^.readDirCallback(vol, RelPath, status);

    resultMap := hashmap.new();

    if (dirList <> nil) and (status^ = 0) then begin
        for i := 0 to LL_Size(dirList) - 1 do begin
            entry := PDirectory_Entry(LL_Get(dirList, i));
            newObj := PVFSObject(kalloc(sizeof(TVFSObject)));
            newObj^.Parent := Parent;
            newObj^.Reference := nil;
            case entry^.entryType of
                directoryEntry: newObj^.ObjectType := otDIRECTORY;
                fileEntry:      newObj^.ObjectType := otFILE;
                mountEntry:     newObj^.ObjectType := otMOUNT;
            end;

            { Filesystem provides the display name directly in entry^.fileName }
            newObj^.ObjectName := stringCopy(entry^.fileName);
            hashmap.add(resultMap, stringCopy(entry^.fileName), void(newObj));
        end;
        LL_Free(dirList);
    end;

    volumeGetDirectories := resultMap;
    kfree(puint32(status));
    tracer.push_trace('vfs.volumeGetDirectories.exit');
end;

Function GetDirectoryListing(Path : pchar) : PHashMap;
var
    Obj : PVFSObject;
    ObjPath : pchar;
    RelPath : pchar;

begin
    tracer.push_trace('vfs.GetDirectoryListing.enter');
    Obj:= GetObjectFromPath(Path);
    if Obj <> nil then begin
        Case Obj^.ObjectType of
            otVDIRECTORY:begin
                GetDirectoryListing:= PHashMap(Obj^.Reference);
            end;
            otDRIVE:begin
                ObjPath:= getAbsolutePath(Obj);
                RelPath:= makeRelative(Path, ObjPath);
                if RelPath = nil then begin
                    RelPath:= stringNew(1);
                    RelPath[0]:= '/';
                end;
                GetDirectoryListing:= volumeGetDirectories(PStorage_Volume(Obj^.Reference), RelPath, Obj);
                kfree(void(ObjPath));
                kfree(void(RelPath));
            end; 
            otDEVICE:begin
                GetDirectoryListing:= nil;
            end;
            otFILE, otDIRECTORY, otVFILE:begin
                GetDirectoryListing:= nil;
            end; 
            otMOUNT:begin
                GetDirectoryListing:= GetDirectoryListing(PVFSMount(Obj^.Reference)^.Path);
            end;
        end;
    end else begin
        GetDirectoryListing:= nil;
    end;
    tracer.push_trace('vfs.GetDirectoryListing.exit');
end;

{ Volume Mount Functions }

function mountVolume(mountPath : pchar; volume : PStorage_Volume) : TRegError;
var
    parentObj   : PVFSObject;
    mountObj    : PVFSObject;
    ht          : PHashMap;
    splitPath   : PLinkedListBase;
    mountName   : pchar;
    parentPath  : pchar;

begin
    tracer.push_trace('vfs.mountVolume.enter');
    mountVolume := pvUnknown;

    splitPath := STRLL_FromString(mountPath, '/');
    if STRLL_Size(splitPath) = 0 then begin
        STRLL_Free(splitPath);
        exit;
    end;

    mountName := STRLL_Get(splitPath, STRLL_Size(splitPath) - 1);
    parentPath := CombineToAbsolutePath(splitPath, STRLL_Size(splitPath) - 1);

    { Ensure parent directory exists }
    parentObj := GetObjectFromPath(parentPath);
    if parentObj = nil then begin
        newVirtualDirectory(parentPath);
        parentObj := GetObjectFromPath(parentPath);
    end;

    if parentObj = nil then begin
        kfree(void(parentPath));
        STRLL_Free(splitPath);
        exit;
    end;

    if parentObj^.ObjectType <> otVDIRECTORY then begin
        kfree(void(parentPath));
        STRLL_Free(splitPath);
        exit;
    end;

    ht := PHashMap(parentObj^.Reference);
    if ht = nil then begin
        kfree(void(parentPath));
        STRLL_Free(splitPath);
        exit;
    end;

    { Create the mount object storing the volume pointer }
    mountObj := PVFSObject(kalloc(sizeof(TVFSObject)));

    mountObj^.Parent := parentObj;
    mountObj^.ObjectName := stringCopy(mountName);
    mountObj^.ObjectType := otDRIVE;
    mountObj^.Reference := void(volume);

    hashmap.add(ht, stringCopy(mountName), void(mountObj));
    mountVolume := pvRegistered;

    kfree(void(parentPath));
    STRLL_Free(splitPath);
    tracer.push_trace('vfs.mountVolume.exit');
end;

{ Filesystem Functions }

const
    MAX_OPEN_FILES = 16;

type
    TOpenFileEntry = record
        inUse      : boolean;
        volume     : PStorage_Volume;
        directory  : pchar;     { Directory path within volume, e.g. 'SYSTEM' or '' for root }
        fileName   : pchar;     { Full filename including extension, e.g. 'README.TXT' }
        openMode   : TOpenMode;
        writeMode  : TWriteMode;
        dataBuffer : puint32;   { Pointer to loaded data (nil for omStream) }
        dataSize   : uint32;    { Size of loaded data in bytes }
        loaded     : boolean;   { True if data has been read from disk }
        { Current byte position for omStream mode; 0 on open, advanced by each ReadFile call }
        streamOffset : uint32;
    end;
    POpenFileEntry = ^TOpenFileEntry;

var
    OpenFiles : array[0..15] of TOpenFileEntry;

type
    PPStorage_Volume = ^PStorage_Volume;
    PPChar = ^pchar;

{ Resolve a full VFS path into a volume + relative dir + filename.
  Returns true if successful.
  dirOut, nameOut are allocated on the heap — caller must free them. }
function ResolveFilePath(FullPath : pchar; volOut : PPStorage_Volume;
                         dirOut : PPChar; nameOut : PPChar) : boolean;
var
    AbsPath    : pchar;
    EvalPath   : pchar;
    SplitFull  : PLinkedListBase;
    Obj        : PVFSObject;
    relCount   : uint32;
    i          : uint32;
    j          : uint32;
    dirBuf     : pchar;
    tmpBuf     : pchar;
begin
    tracer.push_trace('vfs.ResolveFilePath.enter');
    ResolveFilePath := false;
    volOut^ := nil;
    dirOut^ := nil;
    nameOut^ := nil;

    { Make absolute and evaluate . / .. }
    AbsPath := MakeAbsolutePath(FullPath);
    EvalPath := evaluatePath(AbsPath);
    kfree(void(AbsPath));

    { Walk path segments to find the DRIVE (mounted volume) object }
    SplitFull := STRLL_FromString(EvalPath, '/');
    Obj := Root;

    if STRLL_Size(SplitFull) = 0 then begin
        kfree(void(EvalPath));
        STRLL_Free(SplitFull);
        exit;
    end;

    { Walk down until we hit a DRIVE node }
    for i := 0 to STRLL_Size(SplitFull) - 1 do begin
        if Obj^.ObjectType <> otVDIRECTORY then begin
            break;
        end;

        if Obj^.Reference = nil then begin
            break;
        end;

        Obj := PVFSObject(hashmap.get(PHashMap(Obj^.Reference), STRLL_Get(SplitFull, i)));
        if Obj = nil then begin
            kfree(void(EvalPath));
            STRLL_Free(SplitFull);
            exit;
        end;

        if Obj^.ObjectType = otDRIVE then begin
            volOut^ := PStorage_Volume(Obj^.Reference);

            { Everything after this segment is relative path within the volume }
            relCount := STRLL_Size(SplitFull) - i - 1;
            if relCount = 0 then begin
                kfree(void(EvalPath));
                STRLL_Free(SplitFull);
                exit;
            end;

            { Last segment is the filename — pass it as-is to the filesystem }
            nameOut^ := stringCopy(STRLL_Get(SplitFull, STRLL_Size(SplitFull) - 1));

            { Build directory path from segments between drive and filename }
            if relCount <= 1 then begin
                dirOut^ := stringNew(0);
            end else begin
                dirBuf := stringNew(0);
                for j := i + 1 to STRLL_Size(SplitFull) - 2 do begin
                    if stringSize(dirBuf) > 0 then begin
                        tmpBuf := stringConcat(dirBuf, '/');
                        kfree(void(dirBuf));
                        dirBuf := tmpBuf;
                    end;
                    tmpBuf := stringConcat(dirBuf, STRLL_Get(SplitFull, j));
                    kfree(void(dirBuf));
                    dirBuf := tmpBuf;
                end;
                dirOut^ := dirBuf;
            end;

            ResolveFilePath := true;
            kfree(void(EvalPath));
            STRLL_Free(SplitFull);
            tracer.push_trace('vfs.ResolveFilePath.exit');
            exit;
        end;
    end;

    kfree(void(EvalPath));
    STRLL_Free(SplitFull);
    tracer.push_trace('vfs.ResolveFilePath.exit');
end;

Function OpenFile(Filename : pchar; OpenMode : TOpenMode; WriteMode : TWriteMode; Lock : Boolean; Error : PError) : TFileHandle;
var
    i        : uint32;
    slot     : sint32;
    vol      : PStorage_Volume;
    dir      : pchar;
    fname    : pchar;
    dataBuf  : puint32;
    dataSize : puint32;
    readErr  : uint32;
begin
    tracer.push_trace('vfs.OpenFile.enter');
    OpenFile := 0;
    if Error <> nil then Error^ := eUnknown;

    { Validate input }
    if (Filename = nil) or (Filename[0] = char(0)) then begin
        if Error <> nil then Error^ := eInvalidPath;
        exit;
    end;

    { Find a free slot }
    slot := -1;
    for i := 0 to MAX_OPEN_FILES - 1 do begin
        if not OpenFiles[i].inUse then begin
            slot := i;
            break;
        end;
    end;
    if slot = -1 then begin
        if Error <> nil then Error^ := eTooManyOpenFiles;
        exit;
    end;

    { Resolve path — filesystem handles name/extension splitting }
    if not ResolveFilePath(Filename, PPStorage_Volume(@vol), PPChar(@dir), PPChar(@fname)) then begin
        if Error <> nil then Error^ := eFileDoesNotExist;
        exit;
    end;

    { Validate resolved filename }
    if (fname = nil) or (fname[0] = char(0)) then begin
        if Error <> nil then Error^ := eInvalidFileName;
        if dir <> nil then kfree(void(dir));
        if fname <> nil then kfree(void(fname));
        exit;
    end;

    { Set up the entry }
    OpenFiles[slot].inUse := true;
    OpenFiles[slot].volume := vol;
    OpenFiles[slot].directory := dir;
    OpenFiles[slot].fileName := fname;
    OpenFiles[slot].openMode := OpenMode;
    OpenFiles[slot].writeMode := WriteMode;
    OpenFiles[slot].dataBuffer := nil;
    OpenFiles[slot].dataSize := 0;
    OpenFiles[slot].loaded := false;
    OpenFiles[slot].streamOffset := 0;

    { If reading, load the file data now }
    if (OpenMode = omReadOnly) or (OpenMode = omReadWrite) then begin
        if (vol^.filesystem <> nil) and (vol^.filesystem^.readCallback <> nil) then begin
            dataBuf := puint32(kalloc(4));
            dataBuf^ := 0;
            dataSize := puint32(kalloc(4));
            dataSize^ := 0;

            readErr := vol^.filesystem^.readCallback(vol, dir, fname, dataBuf, dataSize);

            if readErr = 0 then begin
                OpenFiles[slot].dataBuffer := puint32(dataBuf^);
                OpenFiles[slot].dataSize := dataSize^;
                OpenFiles[slot].loaded := true;
                if Error <> nil then Error^ := eNone;
            end else begin
                { File doesn't exist on disk — OK for write mode }
                if OpenMode = omReadWrite then begin
                    if Error <> nil then Error^ := eNone;
                end else begin
                    if Error <> nil then Error^ := eFileDoesNotExist;
                    OpenFiles[slot].inUse := false;
                    kfree(void(dir));
                    kfree(void(fname));
                    kfree(puint32(dataBuf));
                    kfree(puint32(dataSize));
                    exit;
                end;
            end;

            kfree(puint32(dataBuf));
            kfree(puint32(dataSize));
        end;
    end else begin
        { Write-only or streaming mode — no pre-load }
        if Error <> nil then Error^ := eNone;
    end;

    OpenFile := slot + 1; { Handle is 1-based, 0 = invalid }
    tracer.push_trace('vfs.OpenFile.exit');
end;

function WriteFile(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
var
    idx    : uint32;
    entry  : POpenFileEntry;
    vol    : PStorage_Volume;
    dirEntry : TDirectory_Entry;
    status : puint32;
    padBuf : puint32;
    padSize : uint32;
begin
    tracer.push_trace('vfs.WriteFile.enter');
    WriteFile := 0;

    if (FileHandle = 0) or (FileHandle > MAX_OPEN_FILES) then exit;
    idx := FileHandle - 1;
    entry := @OpenFiles[idx];

    if not entry^.inUse then exit;
    if (entry^.openMode <> omWriteOnly) and (entry^.openMode <> omReadWrite) then exit;
    if Buffer = nil then exit;

    vol := entry^.volume;
    if vol = nil then exit;
    if vol^.filesystem = nil then exit;
    if vol^.filesystem^.writeCallback = nil then exit;

    { Build a TDirectory_Entry for the write callback }
    dirEntry.fileName := entry^.fileName;
    dirEntry.entryType := fileEntry;

    status := puint32(kalloc(4));
    status^ := 0;

    { Filesystem writeFile may read full sectors from the buffer regardless of Length.
      Pad to at least 4096 bytes to prevent reading past the allocation. }
    padSize := Length;
    if padSize < 4096 then padSize := 4096;
    padBuf := puint32(kalloc(padSize));
    memset(uint32(padBuf), 0, padSize);
    if Length > 0 then
        util.memcpy(uint32(Buffer), uint32(padBuf), Length);

    vol^.filesystem^.writeCallback(vol, entry^.directory, @dirEntry, Length, padBuf, status);

    { Only report success if the filesystem callback reports no error }
    if status^ = 0 then
        WriteFile := Length
    else
        WriteFile := 0;

    kfree(padBuf);
    kfree(puint32(status));
    tracer.push_trace('vfs.WriteFile.exit');
end;

function ReadFile(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
var
    idx      : uint32;
    entry    : POpenFileEntry;
    copyLen  : uint32;
begin
    tracer.push_trace('vfs.ReadFile.enter');
    ReadFile := 0;

    if (FileHandle = 0) or (FileHandle > MAX_OPEN_FILES) then exit;
    idx := FileHandle - 1;
    entry := @OpenFiles[idx];

    if not entry^.inUse then exit;

    { Streaming mode: call readOffsetCallback on demand — no pre-loaded buffer needed }
    if entry^.openMode = omStream then begin
        if Buffer = nil then exit;
        if entry^.volume = nil then exit;
        if entry^.volume^.filesystem = nil then exit;
        if entry^.volume^.filesystem^.readOffsetCallback = nil then exit;
        ReadFile := entry^.volume^.filesystem^.readOffsetCallback(
            entry^.volume, entry^.directory, entry^.fileName,
            entry^.streamOffset, puint32(Buffer), Length);
        entry^.streamOffset := entry^.streamOffset + ReadFile;
        tracer.push_trace('vfs.ReadFile.exit');
        exit;
    end;

    if not entry^.loaded then exit;
    if entry^.dataBuffer = nil then exit;
    if Buffer = nil then exit;

    { Copy from loaded buffer at Position into caller's buffer }
    if Position >= entry^.dataSize then exit;

    { Clamp copyLen without relying on (Position + copyLen) which can overflow }
    copyLen := entry^.dataSize - Position;
    if Length < copyLen then
        copyLen := Length;

    if copyLen > 0 then
        util.memcpy(uint32(entry^.dataBuffer) + Position, uint32(Buffer), copyLen);

    ReadFile := copyLen;
    tracer.push_trace('vfs.ReadFile.exit');
end;

function CloseFile(Filehandle : TFileHandle) : boolean;
var
    idx   : uint32;
    entry : POpenFileEntry;
begin
    tracer.push_trace('vfs.CloseFile.enter');
    CloseFile := false;

    if (FileHandle = 0) or (FileHandle > MAX_OPEN_FILES) then exit;
    idx := FileHandle - 1;
    entry := @OpenFiles[idx];

    if not entry^.inUse then exit;

    { Free loaded data buffer }
    if entry^.dataBuffer <> nil then begin
        kfree(entry^.dataBuffer);
        entry^.dataBuffer := nil;
    end;

    { Free path strings }
    if entry^.directory <> nil then begin
        kfree(void(entry^.directory));
        entry^.directory := nil;
    end;
    if entry^.fileName <> nil then begin
        kfree(void(entry^.fileName));
        entry^.fileName := nil;
    end;

    entry^.inUse := false;
    entry^.loaded := false;
    entry^.dataSize := 0;

    CloseFile := true;
    tracer.push_trace('vfs.CloseFile.exit');
end;

function FileSize(Filename : pchar; error : puint8) : uint32;
var
    fError  : TError;
    fHandle : TFileHandle;
    idx     : uint32;
begin
    tracer.push_trace('vfs.FileSize.enter');
    FileSize := 0;
    if error <> nil then error^ := 1;

    fHandle := OpenFile(Filename, omReadOnly, wmRewrite, false, @fError);
    if (fHandle <> 0) and (fError = eNone) then begin
        idx := fHandle - 1;
        FileSize := OpenFiles[idx].dataSize;
        if error <> nil then error^ := 0;
        CloseFile(fHandle);
    end;
    tracer.push_trace('vfs.FileSize.exit');
end;

function CreateDirectory(Handle : uint32; Path : pchar) : TError;
begin
    CreateDirectory := eUnknown;
end;

function GetDirectories(Handle : uint32; Path : pchar) : PHashMap;
begin
    GetDirectories := nil;
end;

function PathValid(Path : pchar) : TIsPathValid;
var
    Obj : PVFSObject;
    ObjPath : pchar;
    RelPath : pchar;
    AbsPath : pchar;
    CopyPath : pchar;
    MntPath  : pchar;
    pvVol    : PStorage_Volume;
    pvStatus : puint32;
    pvDirList: PLinkedListBase;

begin
    tracer.push_trace('vfs.PathValid.enter');
    PathValid:= pvInvalid;
    Obj:= GetObjectFromPath(Path);
    if Obj <> nil then begin
        Case Obj^.ObjectType of
            otVDIRECTORY:begin
                PathValid:= pvDirectory;
            end;
            otDRIVE:begin
                ObjPath:= getAbsolutePath(Obj);
                RelPath:= makeRelative(Path, ObjPath);
                if RelPath = nil then begin
                    RelPath := stringNew(1);
                    RelPath[0] := '/';
                end;
                pvVol := PStorage_Volume(Obj^.Reference);
                { Actually verify the path exists on the volume }
                if (pvVol^.filesystem <> nil) and (pvVol^.filesystem^.readDirCallback <> nil) then begin
                    { If RelPath is just '/' we're at volume root — always valid }
                    if StringEquals(RelPath, '/') then begin
                        PathValid := pvDirectory;
                    end else begin
                        { Ask the filesystem if this directory actually exists }
                        pvStatus := puint32(kalloc(4));
                        pvStatus^ := 0;
                        pvDirList := pvVol^.filesystem^.readDirCallback(pvVol, RelPath, pvStatus);
                        if pvStatus^ = 0 then
                            PathValid := pvDirectory
                        else
                            PathValid := pvInvalid;
                        if pvDirList <> nil then LL_Free(pvDirList);
                        kfree(puint32(pvStatus));
                    end;
                end else
                    PathValid := pvInvalid;
                kfree(void(ObjPath));
                kfree(void(RelPath));
            end; 
            otDEVICE:begin
                PathValid:= pvInvalid;
            end;
            otFILE, otVFILE:begin
                PathValid:= pvFile;
            end; 
            otMOUNT:begin
                { Get the absolute path of this object, i.e. /mnt/mount1 }
                ObjPath:= getAbsolutePath(Obj);                      
                { Make our path relative, i.e. /mnt/mount1/myfile becomes /myfile }
                RelPath:= makeRelative(Path, ObjPath);
                if RelPath = nil then begin
                    kfree(void(ObjPath));
                    PathValid:= pvInvalid;
                    tracer.push_trace('vfs.PathValid.exit');
                    exit;
                end;
                { Grab the Redirect Path i.e. /disk/disk1 }
                MntPath:= PVFSMount(Obj^.Reference)^.Path;
                if MntPath = nil then begin
                    kfree(void(RelPath));
                    kfree(void(ObjPath));
                    PathValid := pvInvalid;
                    tracer.push_trace('vfs.PathValid.exit');
                    exit;
                end;
                { Ensure that if there isn't a '/' between the RelPath & MntPath we add one }
                If (StringSize(MntPath) > 0) and
                   (MntPath[StringSize(MntPath)-1] <> '/') and (RelPath[0] <> '/') then
                    CopyPath:= StringConcat(MntPath, '/')
                else
                    CopyPath:= StringCopy(MntPath);
                { Concat CopyPath + RelPath, i.e. above examples would become /disk/disk1/myfile }
                AbsPath:= StringConcat(CopyPath, RelPath);
                { Recursively call PathValid on our new path }
                PathValid:= PathValid(AbsPath);
                { Free everything we allocated }
                kfree(void(AbsPath));
                kfree(void(RelPath));
                kfree(void(CopyPath));
                kfree(void(ObjPath));
            end;
        end;
    end;
    tracer.push_trace('vfs.PathValid.exit');
end;

function changeDirectory(Path : pchar) : TIsPathValid;
var
    TempPath : pchar;
    AbsPath : pchar;
    Validity : TIsPathValid;

begin
    tracer.push_trace('vfs.changeDirectory.enter');
    TempPath:= MakeAbsolutePath(Path);
    AbsPath:= evaluatePath(TempPath);
    kfree(void(TempPath));
    Validity:= PathValid(AbsPath);
    if (Validity = pvDirectory) then begin
        ChangeCurrentDirectoryValue(AbsPath);
    end;
    changeDirectory:= Validity;
    kfree(void(AbsPath));
    tracer.push_trace('vfs.changeDirectory.exit');
end;

{ VFS Functions }

function newVirtualDirectory(Path : pchar) : TError;
var
    AbsPath               : pchar;
    SplitPath             : PLinkedListBase;
    ParentDirectoryPath   : pchar;
    ObjectName            : pchar;
    splitSize             : uint32;
    Obj                   : PVFSObject;
    Map                   : PHashMap;
    Entry                 : PVFSObject;
    Key                   : pchar;

begin
    tracer.push_trace('vfs.newVirtualDirectory.enter');
    newVirtualDirectory := eUnknown;

    AbsPath := MakeAbsolutePath(Path);
    SplitPath := STRLL_FromString(AbsPath, '/');
    kfree(void(AbsPath));

    splitSize := STRLL_Size(SplitPath);
    if splitSize = 0 then begin
        STRLL_Free(SplitPath);
        newVirtualDirectory := eInvalidPath;
        tracer.push_trace('vfs.newVirtualDirectory.exit');
        exit;
    end;

    ObjectName := STRLL_Get(SplitPath, splitSize - 1);
    ParentDirectoryPath := CombineToAbsolutePath(SplitPath, splitSize - 1);
    Obj := GetObjectFromPath(ParentDirectoryPath);
    kfree(void(ParentDirectoryPath));

    if Obj = nil then begin
        newVirtualDirectory := eDirectoryDoesNotExist;
    end else begin
        Case Obj^.ObjectType of
            otDRIVE, otDEVICE, otVFILE:begin
                newVirtualDirectory := eNotADirectory;
                STRLL_Free(SplitPath);
                tracer.push_trace('vfs.newVirtualDirectory.shortexit');
                exit;
            end;
        end;
        Map := PHashMap(Obj^.Reference);
        Key := STRLL_Get(SplitPath, STRLL_Size(SplitPath) - 1);
        Entry := PVFSObject(hashmap.get(Map, Key));
        If Entry = nil then begin
            Entry := createVirtualDirectory();
            Entry^.ObjectName := stringCopy(ObjectName);
            Entry^.Parent := Obj;
            hashmap.add(Map, stringCopy(Key), void(Entry));
        end else begin
            newVirtualDirectory := eDirectoryAlreadyExists;
        end;
    end;

    STRLL_Free(SplitPath);
    tracer.push_trace('vfs.newVirtualDirectory.exit');
end;

function getWorkingDirectory : pchar;
begin
    tracer.push_trace('vfs.getWorkingDirectory.enter');
    { Return a copy so callers cannot hold a dangling pointer after a cd }
    if CurrentDirectory <> nil then
        getWorkingDirectory := stringCopy(CurrentDirectory)
    else
        getWorkingDirectory := nil;
    tracer.push_trace('vfs.getWorkingDirectory.exit');
end;

function makeAbsolutePathFrom(Path : pchar; BaseDir : pchar) : pchar;
var
    AbsPath  : pchar;
    TempPath : pchar;
begin
    if Path[0] = '/' then
        AbsPath := stringCopy(Path)
    else begin
        if BaseDir[StringSize(BaseDir)-1] <> '/' then
            TempPath := StringConcat(BaseDir, '/')
        else
            TempPath := stringCopy(BaseDir);
        AbsPath := StringConcat(TempPath, Path);
        kfree(void(TempPath));
    end;
    makeAbsolutePathFrom := AbsPath;
end;

function resolvePathFrom(Path : pchar; BaseDir : pchar) : TIsPathValid;
var
    TempPath : pchar;
    AbsPath  : pchar;
begin
    TempPath := makeAbsolutePathFrom(Path, BaseDir);
    AbsPath := evaluatePath(TempPath);
    kfree(void(TempPath));
    resolvePathFrom := PathValid(AbsPath);
    kfree(void(AbsPath));
end;

function GetDirectoryListingFrom(Path : pchar; BaseDir : pchar) : PHashMap;
var
    TempPath : pchar;
    AbsPath  : pchar;
begin
    TempPath := makeAbsolutePathFrom(Path, BaseDir);
    AbsPath := evaluatePath(TempPath);
    kfree(void(TempPath));
    GetDirectoryListingFrom := GetDirectoryListing(AbsPath);
    kfree(void(AbsPath));
end;

function changeDirectoryFrom(Path : pchar; BaseDir : pchar; var NewDir : pchar) : TIsPathValid;
var
    TempPath : pchar;
    AbsPath  : pchar;
    Validity : TIsPathValid;
begin
    TempPath := makeAbsolutePathFrom(Path, BaseDir);
    AbsPath := evaluatePath(TempPath);
    kfree(void(TempPath));
    Validity := PathValid(AbsPath);
    if Validity = pvDirectory then
        NewDir := AbsPath
    else begin
        NewDir := nil;
        kfree(void(AbsPath));
    end;
    changeDirectoryFrom := Validity;
end;

{ Terminal Commands }

procedure VFS_COMMAND_PUSHD(params : PParamList);
var
    Output : pchar;
    WD     : pchar;

begin
    WD:= StringCopy(CurrentDirectory);
    STRLL_Add(PushPopDirectory, WD);
    Output:= StringConcat(WD, ' saved to stack.');
    WritestringlnWND(Output, getTerminalHWND);
    kfree(void(Output));
end;

procedure VFS_COMMAND_POPD(params : PParamList);
var
    Output : pchar;
    WD     : pchar;

begin
    if STRLL_Size(PushPopDirectory) > 0 then begin
        WD:= STRLL_Get(PushPopDirectory, STRLL_Size(PushPopDirectory)-1);
        if changeDirectory(WD) = pvDirectory then begin
            Output:= StringConcat(WD, ' popped from the stack.');
            WritestringlnWND(Output, getTerminalHWND);
            kfree(void(Output));
        end else begin
            Output:= StringConcat(WD, ' popped, but was invalid!');
            WritestringlnWND(Output, getTerminalHWND);
            kfree(void(Output));
        end;
        STRLL_Delete(PushPopDirectory, STRLL_Size(PushPopDirectory)-1);
    end else begin
        WritestringlnWND('No working directory in the stack!', getTerminalHWND);
    end;
end;

{ Free a directory listing map that was freshly allocated by volumeGetDirectories.
  Only call this when the map is caller-owned (i.e. the current directory is a DRIVE). }
procedure freeOwnedDirListing(Map : PHashMap);
var
    i        : uint32;
    Item     : PHashItem;
    nextItem : PHashItem;
    vfsObj   : PVFSObject;
begin
    if Map = nil then exit;
    for i := 0 to Map^.Size - 1 do begin
        Item := Map^.Table[i];
        while Item <> nil do begin
            nextItem := Item^.Next;
            { Free the PVFSObject and its ObjectName string that we allocated }
            if Item^.Data <> nil then begin
                vfsObj := PVFSObject(Item^.Data);
                if vfsObj^.ObjectName <> nil then
                    kfree(void(vfsObj^.ObjectName));
                kfree(Item^.Data);
            end;
            { Free the key string that was stringCopy'd by volumeGetDirectories }
            if Item^.Key <> nil then
                kfree(void(Item^.Key));
            { Free the PHashItem node itself }
            kfree(void(Item));
            Item := nextItem;
        end;
        Map^.Table[i] := nil;
    end;
    kfree(void(Map));
end;

procedure VFS_COMMAND_LS(params : PParamList);
var
    Map      : PHashMap;
    Item     : PHashItem;
    dirObj   : PVFSObject;
    obj      : PVFSObject;
    i        : uint32;
    col      : uint32;
    mapOwned : boolean;

begin
    tracer.push_trace('vfs.VFS_COMMAND_LS.enter');
    { Determine if GetDirectoryListing will return a caller-owned (freshly allocated) map }
    dirObj := GetObjectFromPath(CurrentDirectory);
    mapOwned := (dirObj <> nil) and (dirObj^.ObjectType = otDRIVE);
    Map := GetDirectoryListing(CurrentDirectory);
    if Map <> nil then begin
        for i:=0 to Map^.Size-1 do begin
            Item:= Map^.Table[i];
            while Item <> nil do begin
                obj:= PVFSObject(Item^.Data);
                console.writestringWND(' ', getTerminalHWND);
                col:= console.combinecolors($FFFF, $0000);
                case obj^.ObjectType of
                    otVDIRECTORY : col:= console.combinecolors($1587, $0000);
                    otDRIVE      : col:= console.combinecolors($F000, $0000);
                    otDEVICE     : col:= console.combinecolors($FFFF, $F000);
                    otVFILE      : col:= console.combinecolors($FFFF, $C018);
                    otMOUNT      : col:= console.combinecolors($0000, $2638);
                    otFILE       : col:= console.combinecolors($FFFF, $0000);
                    otDIRECTORY  : col:= console.combinecolors($547F, $0000);
                end;
                WritestringlnExWND(Item^.Key, col, getTerminalHWND);
                Item:= Item^.Next;
            end;
        end;
        if mapOwned then
            freeOwnedDirListing(Map);
    end else begin
        writestringlnWND('An internal error occured!', getTerminalHWND);
    end;
    tracer.push_trace('vfs.VFS_COMMAND_LS.exit');
end;

procedure VFS_COMMAND_CD(params : PParamList);
var
    Path : pchar;
    Temp1, Temp2 : pchar;
    Result : TIsPathValid;
    i : uint32;

begin
    tracer.push_trace('vfs.VFS_COMMAND_CD.enter');
    if ParamCount(Params) > 0 then begin
        for i:=0 to ParamCount(Params)-1 do begin
            if i = 0 then begin
                Temp1:= StringCopy(GetParam(i, params));
                Path:= StringCopy(Temp1);
                kfree(void(Temp1));
            end else begin
                Temp1:= StringConcat(' ', GetParam(i, Params));
                Temp2:= StringConcat(Path, Temp1);
                kfree(void(Temp1));
                kfree(void(Path));
                Path:= Temp2;
            end;
        end;
        Result:= changeDirectory(Path);
        case Result of
            pvInvalid:begin
                writestringWND('"', getTerminalHWND);
                writestringWND(Path, getTerminalHWND);
                writestringlnWND('" is not a valid path.', getTerminalHWND);
            end;
            pvFile:begin
                writestringWND('"', getTerminalHWND);
                writestringWND(Path, getTerminalHWND);
                writestringlnWND('" is not a directory.', getTerminalHWND);
            end;
        end;
        kfree(void(Path));
    end;
    tracer.push_trace('vfs.VFS_COMMAND_CD.exit');
end;

{ MKDIR command: MKDIR <path> }
procedure VFS_COMMAND_MKDIR(params : PParamList);
var
    Path     : pchar;
    AbsPath  : pchar;
    vol      : PStorage_Volume;
    dir      : pchar;
    dirName  : pchar;
    status   : puint32;
    errCode  : TError;
begin
    tracer.push_trace('vfs.VFS_COMMAND_MKDIR.enter');
    if ParamCount(params) < 1 then begin
        writestringlnWND('Usage: MKDIR <path>', getTerminalHWND);
        tracer.push_trace('vfs.VFS_COMMAND_MKDIR.exit');
        exit;
    end;

    Path := StringCopy(GetParam(0, params));

    { Resolve the path into volume + parent directory + new directory name }
    if not ResolveFilePath(Path, PPStorage_Volume(@vol), PPChar(@dir), PPChar(@dirName)) then begin
        writestringWND('Invalid path: ', getTerminalHWND);
        writestringlnWND(Path, getTerminalHWND);
        kfree(void(Path));
        tracer.push_trace('vfs.VFS_COMMAND_MKDIR.exit');
        exit;
    end;

    if vol^.filesystem = nil then begin
        writestringlnWND('Volume has no filesystem.', getTerminalHWND);
        kfree(void(Path));
        kfree(void(dir));
        kfree(void(dirName));
        tracer.push_trace('vfs.VFS_COMMAND_MKDIR.exit');
        exit;
    end;

    if vol^.filesystem^.createDirCallback = nil then begin
        writestringlnWND('Filesystem does not support creating directories.', getTerminalHWND);
        kfree(void(Path));
        kfree(void(dir));
        kfree(void(dirName));
        tracer.push_trace('vfs.VFS_COMMAND_MKDIR.exit');
        exit;
    end;

    status := puint32(kalloc(4));
    status^ := 0;

    vol^.filesystem^.createDirCallback(vol, dir, dirName, $10, status);

    errCode := TError(status^);
    case errCode of
        eNone:
            writestringlnWND('Directory created.', getTerminalHWND);
        eDirectoryDoesNotExist: begin
            writestringWND('Parent directory does not exist: ', getTerminalHWND);
            writestringlnWND(dir, getTerminalHWND);
        end;
        eDirectoryAlreadyExists:
            writestringlnWND('Directory already exists.', getTerminalHWND);
        eInvalidFileName:
            writestringlnWND('Invalid directory name.', getTerminalHWND);
        eDiskFull:
            writestringlnWND('Disk is full.', getTerminalHWND);
        eDirectoryFull:
            writestringlnWND('Parent directory is full.', getTerminalHWND);
    else
        writestringlnWND('Failed to create directory.', getTerminalHWND);
    end;

    kfree(puint32(status));
    kfree(void(Path));
    kfree(void(dir));
    kfree(void(dirName));
    tracer.push_trace('vfs.VFS_COMMAND_MKDIR.exit');
end;

{ RM command: RM <path> }
procedure VFS_COMMAND_RM(params : PParamList);
var
    Path    : pchar;
    vol     : PStorage_Volume;
    dir     : pchar;
    fname   : pchar;
    status  : puint32;
    errCode : TError;
    dirEntry : TDirectory_Entry;
    fullPath : pchar;
    tmpPath  : pchar;
begin
    tracer.push_trace('vfs.VFS_COMMAND_RM.enter');
    if ParamCount(params) < 1 then begin
        writestringlnWND('Usage: RM <file_path>', getTerminalHWND);
        tracer.push_trace('vfs.VFS_COMMAND_RM.exit');
        exit;
    end;

    Path := StringCopy(GetParam(0, params));

    if not ResolveFilePath(Path, PPStorage_Volume(@vol), PPChar(@dir), PPChar(@fname)) then begin
        writestringWND('Invalid path: ', getTerminalHWND);
        writestringlnWND(Path, getTerminalHWND);
        kfree(void(Path));
        tracer.push_trace('vfs.VFS_COMMAND_RM.exit');
        exit;
    end;

    if vol^.filesystem = nil then begin
        writestringlnWND('Volume has no filesystem.', getTerminalHWND);
        kfree(void(Path));
        kfree(void(dir));
        kfree(void(fname));
        tracer.push_trace('vfs.VFS_COMMAND_RM.exit');
        exit;
    end;

    if vol^.filesystem^.deleteFileCallback = nil then begin
        writestringlnWND('Filesystem does not support file deletion.', getTerminalHWND);
        kfree(void(Path));
        kfree(void(dir));
        kfree(void(fname));
        tracer.push_trace('vfs.VFS_COMMAND_RM.exit');
        exit;
    end;

    status := puint32(kalloc(4));
    status^ := 0;

    { Build the full relative path within the volume: dir/fname }
    if (dir <> nil) and (stringSize(dir) > 0) then begin
        tmpPath := stringConcat(dir, '/');
        fullPath := stringConcat(tmpPath, fname);
        kfree(void(tmpPath));
        kfree(void(dir));
        dir := nil;
    end else begin
        if dir <> nil then kfree(void(dir));
        fullPath := stringCopy(fname);
    end;

    vol^.filesystem^.deleteFileCallback(vol, fullPath, status);

    errCode := TError(status^);
    case errCode of
        eNone: begin
            writestringWND('Deleted: ', getTerminalHWND);
            writestringlnWND(fname, getTerminalHWND);
        end;
        eFileDoesNotExist:
            writestringlnWND('File not found.', getTerminalHWND);
        ePermissionDenied:
            writestringlnWND('Permission denied.', getTerminalHWND);
        eNotADirectory:
            writestringlnWND('Is a directory. Use RMDIR instead.', getTerminalHWND);
    else
        writestringlnWND('Failed to delete file.', getTerminalHWND);
    end;

    kfree(puint32(status));
    kfree(void(Path));
    kfree(void(fullPath));
    kfree(void(fname));
    tracer.push_trace('vfs.VFS_COMMAND_RM.exit');
end;

{ RMDIR command: RMDIR <path> }
procedure VFS_COMMAND_RMDIR(params : PParamList);
var
    Path    : pchar;
    vol     : PStorage_Volume;
    dir     : pchar;
    dirName : pchar;
    fullPath: pchar;
    tmpPath : pchar;
    status  : puint32;
    errCode : TError;
begin
    tracer.push_trace('vfs.VFS_COMMAND_RMDIR.enter');
    if ParamCount(params) < 1 then begin
        writestringlnWND('Usage: RMDIR <path>', getTerminalHWND);
        tracer.push_trace('vfs.VFS_COMMAND_RMDIR.exit');
        exit;
    end;

    Path := StringCopy(GetParam(0, params));

    if not ResolveFilePath(Path, PPStorage_Volume(@vol), PPChar(@dir), PPChar(@dirName)) then begin
        writestringWND('Invalid path: ', getTerminalHWND);
        writestringlnWND(Path, getTerminalHWND);
        kfree(void(Path));
        tracer.push_trace('vfs.VFS_COMMAND_RMDIR.exit');
        exit;
    end;

    if vol^.filesystem = nil then begin
        writestringlnWND('Volume has no filesystem.', getTerminalHWND);
        kfree(void(Path));
        kfree(void(dir));
        kfree(void(dirName));
        tracer.push_trace('vfs.VFS_COMMAND_RMDIR.exit');
        exit;
    end;

    if vol^.filesystem^.deleteDirCallback = nil then begin
        writestringlnWND('Filesystem does not support directory deletion.', getTerminalHWND);
        kfree(void(Path));
        kfree(void(dir));
        kfree(void(dirName));
        tracer.push_trace('vfs.VFS_COMMAND_RMDIR.exit');
        exit;
    end;

    status := puint32(kalloc(4));
    status^ := 0;

    { Build full relative path for the directory }
    if (dir <> nil) and (stringSize(dir) > 0) then begin
        tmpPath := stringConcat(dir, '/');
        fullPath := stringConcat(tmpPath, dirName);
        kfree(void(tmpPath));
        kfree(void(dir));
        dir := nil;
    end else begin
        if dir <> nil then kfree(void(dir));
        fullPath := stringCopy(dirName);
    end;

    vol^.filesystem^.deleteDirCallback(vol, fullPath, status);

    errCode := TError(status^);
    case errCode of
        eNone: begin
            writestringWND('Removed directory: ', getTerminalHWND);
            writestringlnWND(dirName, getTerminalHWND);
        end;
        eDirectoryDoesNotExist:
            writestringlnWND('Directory not found.', getTerminalHWND);
        eNotADirectory:
            writestringlnWND('Not a directory.', getTerminalHWND);
        eDirectoryNotEmpty:
            writestringlnWND('Directory is not empty.', getTerminalHWND);
        ePermissionDenied:
            writestringlnWND('Permission denied.', getTerminalHWND);
    else
        writestringlnWND('Failed to remove directory.', getTerminalHWND);
    end;

    kfree(puint32(status));
    kfree(void(Path));
    kfree(void(fullPath));
    kfree(void(dirName));
    tracer.push_trace('vfs.VFS_COMMAND_RMDIR.exit');
end;

{ MOUNT command: MOUNT <vol_index> <path> [p] }
procedure VFS_COMMAND_MOUNT(params : PParamList);
var
    volIdx    : uint32;
    volIdxStr : pchar;
    vol       : PStorage_Volume;
    path      : pchar;
    res       : TRegError;
    persist   : boolean;
    dirEntry  : TDirectory_Entry;
    status    : puint32;
    padBuf    : puint32;

begin
    tracer.push_trace('vfs.VFS_COMMAND_MOUNT.enter');
    if ParamCount(params) < 2 then begin
        writestringlnWND('Usage: MOUNT <vol_index> <path> [p]', getTerminalHWND);
        writestringlnWND('  vol_index  Volume number (see VOL LIST)', getTerminalHWND);
        writestringlnWND('  path       VFS mount point, e.g. /mnt/data', getTerminalHWND);
        writestringlnWND('  p          Persistent: remount on boot', getTerminalHWND);
        tracer.push_trace('vfs.VFS_COMMAND_MOUNT.exit');
        exit;
    end;

    volIdx := stringToInt(GetParam(0, params));
    if volIdx >= volumemanager.get_volume_count() then begin
        writestringlnWND('Invalid volume index.', getTerminalHWND);
        tracer.push_trace('vfs.VFS_COMMAND_MOUNT.exit');
        exit;
    end;

    vol := volumemanager.get_volume(volIdx);
    if vol = nil then begin
        writestringlnWND('Volume not found.', getTerminalHWND);
        tracer.push_trace('vfs.VFS_COMMAND_MOUNT.exit');
        exit;
    end;

    if vol^.filesystem = nil then begin
        { Try probing as a last resort }
        filesystemmanager.probe_volume(vol);
    end;

    if vol^.filesystem = nil then begin
        writestringlnWND('Volume has no detected filesystem. Format it first.', getTerminalHWND);
        tracer.push_trace('vfs.VFS_COMMAND_MOUNT.exit');
        exit;
    end;

    { Check for persistent flag }
    persist := false;
    if ParamCount(params) >= 3 then begin
        if stringEquals(GetParam(2, params), 'p') then
            persist := true;
    end;

    path := StringCopy(GetParam(1, params));

    res := mountVolume(path, vol);
    case res of
        pvRegistered: begin
            writestringWND('Mounted volume ', getTerminalHWND);
            volIdxStr := intToString(volIdx);
            writestringWND(volIdxStr, getTerminalHWND);
            kfree(void(volIdxStr));
            writestringWND(' (', getTerminalHWND);
            writestringWND(vol^.filesystem^.sName, getTerminalHWND);
            writestringWND(') at ', getTerminalHWND);
            writestringlnWND(path, getTerminalHWND);

            { Write asr.mnt to volume root if persistent }
            if persist then begin
                if vol^.filesystem^.writeCallback <> nil then begin
                    dirEntry.fileName := stringCopy('ASR.MNT');
                    dirEntry.entryType := fileEntry;

                    status := puint32(kalloc(4));
                    status^ := 0;

                    { Pad buffer to 4096 to prevent filesystem reading past allocation }
                    padBuf := puint32(kalloc(4096));
                    memset(uint32(padBuf), 0, 4096);
                    util.memcpy(uint32(path), uint32(padBuf), stringSize(path));

                    vol^.filesystem^.writeCallback(vol, '', @dirEntry, stringSize(path), padBuf, status);

                    kfree(padBuf);

                    if status^ = 0 then
                        writestringlnWND('Persistent mount saved (asr.mnt).', getTerminalHWND)
                    else
                        writestringlnWND('Warning: could not write asr.mnt.', getTerminalHWND);

                    kfree(puint32(status));
                    kfree(void(dirEntry.fileName));
                end else begin
                    writestringlnWND('Warning: filesystem is read-only, cannot persist.', getTerminalHWND);
                end;
            end;
        end;
    else
        writestringlnWND('Failed to mount volume.', getTerminalHWND);
    end;

    kfree(void(path));
    tracer.push_trace('vfs.VFS_COMMAND_MOUNT.exit');
end;

{ UMOUNT command: UMOUNT <path> }
procedure VFS_COMMAND_UMOUNT(params : PParamList);
var
    path    : pchar;
    obj     : PVFSObject;
    parentObj : PVFSObject;
    ht      : PHashMap;

begin
    tracer.push_trace('vfs.VFS_COMMAND_UMOUNT.enter');
    if ParamCount(params) < 1 then begin
        writestringlnWND('Usage: UMOUNT <path>', getTerminalHWND);
        tracer.push_trace('vfs.VFS_COMMAND_UMOUNT.exit');
        exit;
    end;

    path := StringCopy(GetParam(0, params));

    obj := GetObjectFromPath(path);
    if obj = nil then begin
        writestringWND('Path not found: ', getTerminalHWND);
        writestringlnWND(path, getTerminalHWND);
        kfree(void(path));
        tracer.push_trace('vfs.VFS_COMMAND_UMOUNT.exit');
        exit;
    end;

    if obj^.ObjectType <> otDRIVE then begin
        writestringlnWND('Path is not a mount point.', getTerminalHWND);
        kfree(void(path));
        tracer.push_trace('vfs.VFS_COMMAND_UMOUNT.exit');
        exit;
    end;

    { Remove from parent hashmap (freeItem=false so we control freeing) }
    parentObj := obj^.Parent;
    if parentObj <> nil then begin
        ht := PHashMap(parentObj^.Reference);
        hashmap.delete(ht, obj^.ObjectName, false);
    end;

    { Free the object }
    kfree(void(obj^.ObjectName));
    kfree(void(obj));

    writestringWND('Unmounted ', getTerminalHWND);
    writestringlnWND(path, getTerminalHWND);

    kfree(void(path));
    tracer.push_trace('vfs.VFS_COMMAND_UMOUNT.exit');
end;

{ Auto-mount all discovered volumes into /disk/ and honour persistent mounts }

procedure auto_mount_volumes();
var
    i         : uint32;
    vol       : PStorage_Volume;
    volName   : pchar;
    volNumStr : pchar;
    mountPath : pchar;
    prefix    : pchar;
    dataBuf   : puint32;
    dataSize  : puint32;
    readErr   : uint32;
    mntPath   : pchar;
    mntLen    : uint32;
    volCount  : uint32;
begin
    tracer.push_trace('vfs.auto_mount_volumes.enter');

    volCount := volumemanager.get_volume_count();
    if volCount = 0 then begin
        tracer.push_trace('vfs.auto_mount_volumes.exit');
        exit;
    end;

    if volCount > 256 then volCount := 256; { sanity cap }

    for i := 0 to volCount - 1 do begin
        vol := volumemanager.get_volume(i);
        if vol = nil then continue;
        if vol^.filesystem = nil then continue;


        { Build mount name: e.g. 'vol0', 'vol1' }
        volNumStr := intToString(i);
        volName := stringConcat('vol', volNumStr);
        kfree(void(volNumStr));
        prefix := stringNew(6);
        prefix[0] := '/';
        prefix[1] := 'd';
        prefix[2] := 'i';
        prefix[3] := 's';
        prefix[4] := 'k';
        prefix[5] := '/';
        mountPath := stringConcat(prefix, volName);

        mountVolume(mountPath, vol);

        console.writestring('VFS: Mounted ');
        console.writestring(vol^.filesystem^.sName);
        console.writestring(' volume at ');
        console.writestringln(mountPath);

        kfree(void(volName));
        kfree(void(prefix));
        kfree(void(mountPath));

        { Check for persistent mount file asr.mnt }
        if vol^.filesystem^.readCallback <> nil then begin
            dataBuf  := puint32(kalloc(4));
            dataBuf^ := 0;
            dataSize := puint32(kalloc(4));
            dataSize^ := 0;

            readErr := vol^.filesystem^.readCallback(vol, '', 'ASR.MNT', dataBuf, dataSize);

            if (readErr = 0) and (dataSize^ > 0) and (dataBuf^ <> 0) then begin
                { dataBuf^ points to the file data containing the mount path }
                mntLen := dataSize^;
                mntPath := pchar(kalloc(mntLen + 1));
                util.memcpy(dataBuf^, uint32(mntPath), mntLen);
                mntPath[mntLen] := char(0);

                { Strip trailing whitespace / CR / LF / null bytes }
                while (mntLen > 0) and ((mntPath[mntLen - 1] = char(0)) or
                      (mntPath[mntLen - 1] = char(10)) or
                      (mntPath[mntLen - 1] = char(13)) or
                      (mntPath[mntLen - 1] = ' ')) do begin
                    mntLen := mntLen - 1;
                    mntPath[mntLen] := char(0);
                end;

                if mntLen > 0 then begin
                    mountVolume(mntPath, vol);
                end;

                kfree(void(mntPath));
                kfree(puint32(dataBuf^));
            end;

            kfree(puint32(dataBuf));
            kfree(puint32(dataSize));
        end;
    end;
    tracer.push_trace('vfs.auto_mount_volumes.exit');
end;

{ Init }

procedure init();
var
    ht : PHashMap;
    obj : PVFSObject;

begin
    tracer.push_trace('vfs.init.enter');

    { VFS Root Creation }
    Root:= createVirtualDirectory();
    Root^.Parent:= nil;
    Root^.ObjectName:= stringNew(1);
    Root^.ObjectName[0]:= '/';

    { Init Push/Pop Stack for PUSHD & POPD }
    PushPopDirectory:= STRLL_New;

    { Move to root of VFS }
    ChangeCurrentDirectoryValue('/');

    { Create the Default VFS Directories }
    newVirtualDirectory('/dev');
    newVirtualDirectory('/disk');
    newVirtualDirectory('/mnt');
    newVirtualDirectory('/cfg');

    { Register Terminal Commands }
    terminal.registerCommand('LS',      @VFS_COMMAND_LS,    'List directory contents.');
    terminal.registerCommand('CD',      @VFS_COMMAND_CD,    'Set working directory.');
    terminal.registerCommand('PUSHD',   @VFS_COMMAND_PUSHD, 'Push the working directory.');
    terminal.registerCommand('POPD',    @VFS_COMMAND_POPD,  'Pop the working directory.');
    terminal.registerCommand('MKDIR',   @VFS_COMMAND_MKDIR, 'Create a directory.');
    terminal.registerCommand('RM',      @VFS_COMMAND_RM,    'Delete a file.');
    terminal.registerCommand('RMDIR',   @VFS_COMMAND_RMDIR, 'Delete a directory.');
    terminal.registerCommand('MOUNT',   @VFS_COMMAND_MOUNT, 'Mount a volume at a path.');
    terminal.registerCommand('UMOUNT',  @VFS_COMMAND_UMOUNT,'Unmount a mounted path.');

    tracer.push_trace('vfs.init.exit');
end;

end.