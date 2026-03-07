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
    fdtable,
    hashmap,
    lists,
    lmemorymanager,
    storagetypes,
    strings,
    syslog,
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
    PushPopDirectory  : PLinkedListBase;

procedure init();
Function OpenFile(Filename : pchar; OpenMode : TOpenMode; WriteMode : TWriteMode; Error : PError) : TFileHandle;
function WriteFile(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
function ReadFile(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
function CloseFile(Filehandle : TFileHandle) : TError;

{ Async public API — return immediately, callback fires on completion.
  Callers (e.g. LVGL callbacks) must keep all buffers alive until the
  callback fires. }
procedure WriteFileAsync(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32; Callback : TIOCallback; CallbackData : pointer);
procedure OpenFileAsync(Filename : pchar; OpenMode : TOpenMode; WriteMode : TWriteMode; var OutHandle : TFileHandle; Error : PError; Callback : TIOCallback; CallbackData : pointer);
function FileSize(Filename : pchar; error : PError) : uint32;
function CreateDirectory(Handle : uint32; Path : pchar) : TError;
function GetDirectories(Handle : uint32; Path : pchar) : PHashMap;
function PathValid(Path : pchar) : TIsPathValid;
function changeDirectory(Path : pchar) : TIsPathValid;
function getWorkingDirectory : pchar;
function makeAbsolutePathFrom(Path : pchar; BaseDir : pchar) : pchar;
function resolvePathFrom(Path : pchar; BaseDir : pchar) : TIsPathValid;
function GetDirectoryListingFrom(Path : pchar; BaseDir : pchar) : PHashMap;
procedure FreeDirectoryListing(map : PHashMap);
function changeDirectoryFrom(Path : pchar; BaseDir : pchar; var NewDir : pchar) : TIsPathValid;
function MakeAbsolutePath(Path : PChar) : pchar;

//VFS Functions
function newVirtualDirectory(Path : pchar) : TError;

//Volume Mount Functions
function mountVolume(mountPath : pchar; volume : PStorage_Volume) : TRegError;
procedure auto_mount_volumes(); //TODO, need to change this when os can be installled to disk and have a config file
procedure UnitTest;

implementation

uses
    filesystemmanager,
    processmanager,
    proctypes,
    stdio,
    util,
    volumemanager;

{ ===================== Async helpers ========================================
  Used by OpenFileAsync to stitch results back into the file descriptor.
  =========================================================================== }

type
    { Used by OpenFileAsync to update the FD when the async read finishes }
    TVFSOpenAsyncCtx = record
        FD          : PFileDescriptor;
        DataBuf     : puint32;    { holder for data pointer — freed by vfs_open_complete }
        DataSize    : puint32;    { holder for byte count  — freed by vfs_open_complete }
        OpenMode    : TOpenMode;
        UserError   : PError;
        UserCallback: TIOCallback;
        UserData    : pointer;
    end;
    PVFSOpenAsyncCtx = ^TVFSOpenAsyncCtx;

{ Completion callback for OpenFileAsync: stitches data into the FD,
  frees temporary holders, then fires the caller's callback. }
procedure vfs_open_complete(error : TError; userdata : pointer);
var
    ctx : PVFSOpenAsyncCtx;
begin
    ctx := PVFSOpenAsyncCtx(userdata);
    if error = eNone then begin
        ctx^.FD^.DataBuffer := puint32(ctx^.DataBuf^);
        ctx^.FD^.DataSize   := ctx^.DataSize^;
        ctx^.FD^.Loaded     := true;
        if ctx^.UserError <> nil then ctx^.UserError^ := eNone;
    end else begin
        { File not found — OK for ReadWrite mode, error for ReadOnly }
        if ctx^.OpenMode = omReadWrite then begin
            if ctx^.UserError <> nil then ctx^.UserError^ := eNone;
        end else begin
            if ctx^.UserError <> nil then ctx^.UserError^ := eFileDoesNotExist;
            ctx^.FD^.InUse := false;
            if ctx^.FD^.Directory <> nil then begin
                kfree(void(ctx^.FD^.Directory));
                ctx^.FD^.Directory := nil;
            end;
            if ctx^.FD^.FileName <> nil then begin
                kfree(void(ctx^.FD^.FileName));
                ctx^.FD^.FileName := nil;
            end;
        end;
    end;
    kfree(puint32(ctx^.DataBuf));
    kfree(puint32(ctx^.DataSize));
    if ctx^.UserCallback <> nil then
        ctx^.UserCallback(error, ctx^.UserData);
    kfree(void(ctx));
end;

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
    cwd : pchar;

begin
    tracer.push_trace('vfs.MakeAbsolutePath.enter');
    if (Path = nil) or (Path[0] = char(0)) then begin
        MakeAbsolutePath := stringNew(1);
        MakeAbsolutePath[0] := '/';
        tracer.push_trace('vfs.MakeAbsolutePath.exit');
        exit;
    end;
    if Path[0] = '/' then AbsPath:= stringCopy(Path) else begin
        { Get per-process working directory }
        cwd := nil;
        if (processmanager.CurrentProcess <> nil) and
           (processmanager.CurrentProcess^.Cwd <> nil) then
            cwd := processmanager.CurrentProcess^.Cwd;
        if (cwd = nil) or (StringSize(cwd) = 0) then begin
            TempPath := stringNew(1);
            TempPath[0] := '/';
        end else begin
            if cwd[StringSize(cwd)-1] <> '/' then
                TempPath:= StringConcat(cwd, '/')
            else
                TempPath:= stringCopy(cwd);
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
            { Handle dot/dotdot traversal }
            if stringEquals(item, '.') then
                continue;
            if stringEquals(item, '..') then begin
                if Obj^.Parent <> nil then
                    Obj := Obj^.Parent;
                continue;
            end;
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
var
    ctx : proctypes.PProcessContext;
begin
    tracer.push_trace('vfs.ChangeCurrentDirectoryValue.enter');
    ctx := processmanager.CurrentProcess;
    if ctx <> nil then begin
        if ctx^.Cwd <> nil then kfree(void(ctx^.Cwd));
        ctx^.Cwd := stringCopy(new);
    end;
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

    if (dirList <> nil) and (status^ = 0) and (LL_Size(dirList) > 0) then begin
        for i := 0 to LL_Size(dirList) - 1 do begin
            entry := PDirectory_Entry(LL_Get(dirList, i));
            if (entry = nil) or (entry^.fileName = nil) then continue;
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
            { Free the fileName allocated by the filesystem's readDirCallback }
            kfree(void(entry^.fileName));
            entry^.fileName := nil;
        end;
        LL_Free(dirList);
    end else if dirList <> nil then
        LL_Free(dirList);

    volumeGetDirectories := resultMap;
    kfree(puint32(status));
    tracer.push_trace('vfs.volumeGetDirectories.exit');
end;

Function GetDirectoryListing(Path : pchar) : PHashMap;
var
    Obj      : PVFSObject;
    ObjPath  : pchar;
    RelPath  : pchar;
    liveMap  : PHashMap;
    snap     : PHashMap;
    si       : uint32;
    liveItem : PHashItem;
    liveObj  : PVFSObject;
    snapObj  : PVFSObject;

begin
    tracer.push_trace('vfs.GetDirectoryListing.enter');
    Obj:= GetObjectFromPath(Path);
    if Obj <> nil then begin
        Case Obj^.ObjectType of
            otVDIRECTORY:begin
                { Return a snapshot copy — FreeDirectoryListing owns the
                  returned map and must NOT free live-tree VFSObjects. }
                liveMap := PHashMap(Obj^.Reference);
                snap    := hashmap.new();
                if liveMap <> nil then begin
                    for si := 0 to liveMap^.Size - 1 do begin
                        liveItem := liveMap^.Table[si];
                        while liveItem <> nil do begin
                            liveObj := PVFSObject(liveItem^.Data);
                            if liveObj <> nil then begin
                                snapObj := PVFSObject(kalloc(sizeof(TVFSObject)));
                                snapObj^.ObjectType := liveObj^.ObjectType;
                                snapObj^.ObjectName := stringCopy(liveItem^.Key);
                                snapObj^.Reference  := liveObj^.Reference;
                                snapObj^.Parent     := liveObj^.Parent;
                                hashmap.add(snap, stringCopy(liveItem^.Key), void(snapObj));
                            end;
                            liveItem := liveItem^.Next;
                        end;
                    end;
                end;
                GetDirectoryListing := snap;
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

type
    PPStorage_Volume = ^PStorage_Volume;
    PPChar = ^pchar;

{ Return the current process's FD table, or nil if no process is running. }
function currentFDTable : PFDTable;
begin
    currentFDTable := nil;
    if processmanager.CurrentProcess <> nil then
        currentFDTable := PFDTable(processmanager.CurrentProcess^.FDTable);
end;

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

Function OpenFile(Filename : pchar; OpenMode : TOpenMode; WriteMode : TWriteMode; Error : PError) : TFileHandle;
var
    tbl      : PFDTable;
    slot     : uint32;
    fd       : PFileDescriptor;
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

    { Get per-process FD table }
    tbl := currentFDTable;
    if tbl = nil then begin
        if Error <> nil then Error^ := eUnknown;
        exit;
    end;

    { Find a free slot }
    slot := fd_alloc(tbl);
    if slot = 0 then begin
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

    { Set up the descriptor }
    fd := @tbl^.Entries[slot - 1];
    fd^.InUse := true;
    fd^.Volume := vol;
    fd^.Directory := dir;
    fd^.FileName := fname;
    fd^.OpenMode := uint8(ord(OpenMode));
    fd^.WriteMode := uint8(ord(WriteMode));
    fd^.DataBuffer := nil;
    fd^.DataSize := 0;
    fd^.Loaded := false;
    fd^.StreamOff := 0;

    { If reading, load the file data now }
    if (OpenMode = omReadOnly) or (OpenMode = omReadWrite) then begin
        if vol^.filesystem <> nil then begin
            dataBuf := puint32(kalloc(4));
            dataBuf^ := 0;
            dataSize := puint32(kalloc(4));
            dataSize^ := 0;

            if vol^.filesystem^.readCallback <> nil then begin
                { Sync path: fat32 uses submit_io_wait which parks the calling
                  process via psAwaiting until the AHCI ISR completes the I/O. }
                readErr := vol^.filesystem^.readCallback(vol, dir, fname, dataBuf, dataSize);
            end else begin
                readErr := 1;
            end;

            if readErr = 0 then begin
                fd^.DataBuffer := puint32(dataBuf^);
                fd^.DataSize := dataSize^;
                fd^.Loaded := true;
                if Error <> nil then Error^ := eNone;
            end else begin
                { File doesn't exist on disk — OK for write mode }
                if OpenMode = omReadWrite then begin
                    if Error <> nil then Error^ := eNone;
                end else begin
                    if Error <> nil then Error^ := eFileDoesNotExist;
                    fd^.InUse := false;
                    kfree(void(dir));
                    kfree(void(fname));
                    fd^.Directory := nil;
                    fd^.FileName := nil;
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

    OpenFile := slot; { Handle is 1-based from fd_alloc }
    tracer.push_trace('vfs.OpenFile.exit');
end;

function WriteFile(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
var
    fd       : PFileDescriptor;
    vol      : PStorage_Volume;
    dirEntry : TDirectory_Entry;
    status   : puint32;
    padBuf   : puint32;
    padSize  : uint32;
begin
    tracer.push_trace('vfs.WriteFile.enter');
    WriteFile := 0;

    fd := fd_get(currentFDTable, FileHandle);
    if fd = nil then exit;

    if (TOpenMode(fd^.OpenMode) <> omWriteOnly) and (TOpenMode(fd^.OpenMode) <> omReadWrite) then exit;
    if Buffer = nil then exit;

    vol := fd^.Volume;
    if vol = nil then exit;
    if vol^.filesystem = nil then exit;

    { Build a TDirectory_Entry for the write callback }
    dirEntry.fileName  := fd^.FileName;
    dirEntry.entryType := fileEntry;

    { Filesystem writeFile may read full sectors from the buffer regardless of Length.
      Pad to at least 4096 bytes to prevent reading past the allocation. }
    padSize := Length;
    if padSize < 4096 then padSize := 4096;
    padBuf := puint32(kalloc(padSize));
    memset(uint32(padBuf), 0, padSize);
    if Length > 0 then
        util.memcpy(uint32(Buffer), uint32(padBuf), Length);

    if vol^.filesystem^.writeCallback <> nil then begin
        { Sync path: fat32 uses submit_io_wait which parks the calling process
          via psAwaiting until the AHCI ISR completes the I/O. }
        status := puint32(kalloc(4));
        status^ := 0;
        vol^.filesystem^.writeCallback(vol, fd^.Directory, @dirEntry, Length, padBuf, status);
        if status^ = 0 then
            WriteFile := Length
        else
            WriteFile := 0;
        kfree(puint32(status));
        kfree(padBuf);
    end else begin
        kfree(padBuf);
    end;

    tracer.push_trace('vfs.WriteFile.exit');
end;

function ReadFile(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
var
    fd       : PFileDescriptor;
    copyLen  : uint32;
begin
    tracer.push_trace('vfs.ReadFile.enter');
    ReadFile := 0;

    fd := fd_get(currentFDTable, FileHandle);
    if fd = nil then exit;

    { Streaming mode: call readOffsetCallback on demand — no pre-loaded buffer needed }
    if TOpenMode(fd^.OpenMode) = omStream then begin
        if Buffer = nil then exit;
        if fd^.Volume = nil then exit;
        if fd^.Volume^.filesystem = nil then exit;
        if fd^.Volume^.filesystem^.readOffsetCallback = nil then exit;
        ReadFile := fd^.Volume^.filesystem^.readOffsetCallback(
            fd^.Volume, fd^.Directory, fd^.FileName,
            fd^.StreamOff, puint32(Buffer), Length);
        fd^.StreamOff := fd^.StreamOff + ReadFile;
        tracer.push_trace('vfs.ReadFile.exit');
        exit;
    end;

    if not fd^.Loaded then exit;
    if fd^.DataBuffer = nil then exit;
    if Buffer = nil then exit;

    { Copy from loaded buffer at Position into caller's buffer }
    if Position >= fd^.DataSize then exit;

    { Clamp copyLen without relying on (Position + copyLen) which can overflow }
    copyLen := fd^.DataSize - Position;
    if Length < copyLen then
        copyLen := Length;

    if copyLen > 0 then
        util.memcpy(uint32(fd^.DataBuffer) + Position, uint32(Buffer), copyLen);

    ReadFile := copyLen;
    tracer.push_trace('vfs.ReadFile.exit');
end;

function CloseFile(Filehandle : TFileHandle) : TError;
begin
    tracer.push_trace('vfs.CloseFile.enter');
    if fd_close(currentFDTable, FileHandle) then
        CloseFile := eNone
    else
        CloseFile := eInvalidHandle;
    tracer.push_trace('vfs.CloseFile.exit');
end;

function FileSize(Filename : pchar; error : PError) : uint32;
var
    fError  : TError;
    fHandle : TFileHandle;
    fd      : PFileDescriptor;
begin
    tracer.push_trace('vfs.FileSize.enter');
    FileSize := 0;
    if error <> nil then error^ := eUnknown;

    fHandle := OpenFile(Filename, omReadOnly, wmRewrite, @fError);
    if (fHandle <> 0) and (fError = eNone) then begin
        fd := fd_get(currentFDTable, fHandle);
        if fd <> nil then
            FileSize := fd^.DataSize;
        if error <> nil then error^ := eNone;
        CloseFile(fHandle);
    end;
    tracer.push_trace('vfs.FileSize.exit');
end;

{ === Async public API === }

{ WriteFileAsync — set up a write and return immediately.
  fat32 deep-copies the buffer on entry so the caller can free it after this returns.
  Callback fires with eNone on success, or a TError code on failure. }
procedure WriteFileAsync(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32; Callback : TIOCallback; CallbackData : pointer);
var
    fd       : PFileDescriptor;
    vol      : PStorage_Volume;
    dirEntry : TDirectory_Entry;
    padBuf   : puint32;
    padSize  : uint32;
begin
    tracer.push_trace('vfs.WriteFileAsync.enter');

    fd := fd_get(currentFDTable, FileHandle);
    if fd = nil then begin
        if Callback <> nil then Callback(eInvalidHandle, CallbackData);
        exit;
    end;

    if (TOpenMode(fd^.OpenMode) <> omWriteOnly) and (TOpenMode(fd^.OpenMode) <> omReadWrite) then begin
        if Callback <> nil then Callback(eReadOnly, CallbackData);
        exit;
    end;

    if Buffer = nil then begin
        if Callback <> nil then Callback(eInvalidArgument, CallbackData);
        exit;
    end;

    vol := fd^.Volume;
    if (vol = nil) or (vol^.filesystem = nil) then begin
        if Callback <> nil then Callback(eInvalidArgument, CallbackData);
        exit;
    end;

    { Prefer async hook; fall back to sync if not available }
    if vol^.filesystem^.writeAsyncCallback <> nil then begin
        dirEntry.fileName  := fd^.FileName;
        dirEntry.entryType := fileEntry;
        padSize := Length;
        if padSize < 4096 then padSize := 4096;
        padBuf := puint32(kalloc(padSize));
        util.memset(uint32(padBuf), 0, padSize);
        if Length > 0 then
            util.memcpy(uint32(Buffer), uint32(padBuf), Length);
        { fat32 writeFile_async deep-copies padBuf synchronously before returning }
        vol^.filesystem^.writeAsyncCallback(vol, fd^.Directory, @dirEntry, Length, padBuf, Callback, CallbackData);
        kfree(padBuf);
    end else if vol^.filesystem^.writeCallback <> nil then begin
        { Sync fallback — call directly and fake immediate completion }
        dirEntry.fileName  := fd^.FileName;
        dirEntry.entryType := fileEntry;
        padSize := Length;
        if padSize < 4096 then padSize := 4096;
        padBuf := puint32(kalloc(padSize));
        util.memset(uint32(padBuf), 0, padSize);
        if Length > 0 then
            util.memcpy(uint32(Buffer), uint32(padBuf), Length);
        vol^.filesystem^.writeCallback(vol, fd^.Directory, @dirEntry, Length, padBuf, nil);
        kfree(padBuf);
        if Callback <> nil then Callback(eNone, CallbackData);
    end else begin
        if Callback <> nil then Callback(eNotSupported, CallbackData);
    end;

    tracer.push_trace('vfs.WriteFileAsync.exit');
end;

{ OpenFileAsync — resolve the path, allocate an FD, kick off async data load.
  OutHandle is set before returning; the FD is not usable until Callback fires.
  If OpenMode is write-only or stream, Callback fires immediately (no disk read). }
procedure OpenFileAsync(Filename : pchar; OpenMode : TOpenMode; WriteMode : TWriteMode; var OutHandle : TFileHandle; Error : PError; Callback : TIOCallback; CallbackData : pointer);
var
    tbl     : PFDTable;
    slot    : uint32;
    fd      : PFileDescriptor;
    vol     : PStorage_Volume;
    dir     : pchar;
    fname   : pchar;
    dataBuf : puint32;
    dataSize: puint32;
    octx    : PVFSOpenAsyncCtx;
begin
    tracer.push_trace('vfs.OpenFileAsync.enter');
    OutHandle := 0;
    if Error <> nil then Error^ := eUnknown;

    if (Filename = nil) or (Filename[0] = char(0)) then begin
        if Error <> nil then Error^ := eInvalidPath;
        if Callback <> nil then Callback(eInvalidPath, CallbackData);
        exit;
    end;

    tbl := currentFDTable;
    if tbl = nil then begin
        if Callback <> nil then Callback(eUnknown, CallbackData);
        exit;
    end;

    slot := fd_alloc(tbl);
    if slot = 0 then begin
        if Error <> nil then Error^ := eTooManyOpenFiles;
        if Callback <> nil then Callback(eTooManyOpenFiles, CallbackData);
        exit;
    end;

    if not ResolveFilePath(Filename, PPStorage_Volume(@vol), PPChar(@dir), PPChar(@fname)) then begin
        if Error <> nil then Error^ := eFileDoesNotExist;
        if Callback <> nil then Callback(eFileDoesNotExist, CallbackData);
        exit;
    end;

    if (fname = nil) or (fname[0] = char(0)) then begin
        if Error <> nil then Error^ := eInvalidFileName;
        if Callback <> nil then Callback(eInvalidFileName, CallbackData);
        if dir <> nil then kfree(void(dir));
        if fname <> nil then kfree(void(fname));
        exit;
    end;

    fd := @tbl^.Entries[slot - 1];
    fd^.InUse     := true;
    fd^.Volume    := vol;
    fd^.Directory := dir;
    fd^.FileName  := fname;
    fd^.OpenMode  := uint8(ord(OpenMode));
    fd^.WriteMode := uint8(ord(WriteMode));
    fd^.DataBuffer:= nil;
    fd^.DataSize  := 0;
    fd^.Loaded    := false;
    fd^.StreamOff := 0;
    OutHandle := slot;

    if (OpenMode = omReadOnly) or (OpenMode = omReadWrite) then begin
        if (vol^.filesystem <> nil) and (vol^.filesystem^.readAsyncCallback <> nil) then begin
            { True async: build completion context; callback fires when data is loaded }
            dataBuf  := puint32(kalloc(4));
            dataBuf^ := 0;
            dataSize  := puint32(kalloc(4));
            dataSize^ := 0;
            octx := PVFSOpenAsyncCtx(kalloc(sizeof(TVFSOpenAsyncCtx)));
            octx^.FD           := fd;
            octx^.DataBuf      := dataBuf;
            octx^.DataSize     := dataSize;
            octx^.OpenMode     := OpenMode;
            octx^.UserError    := Error;
            octx^.UserCallback := Callback;
            octx^.UserData     := CallbackData;
            vol^.filesystem^.readAsyncCallback(vol, dir, fname, dataBuf, dataSize, @vfs_open_complete, octx);
            { Return immediately — caller must not use OutHandle until Callback fires }
        end else if (vol^.filesystem <> nil) and (vol^.filesystem^.readCallback <> nil) then begin
            { Sync fallback: load now, then fire callback }
            dataBuf  := puint32(kalloc(4));
            dataBuf^ := 0;
            dataSize  := puint32(kalloc(4));
            dataSize^ := 0;
            if vol^.filesystem^.readCallback(vol, dir, fname, dataBuf, dataSize) = 0 then begin
                fd^.DataBuffer := puint32(dataBuf^);
                fd^.DataSize   := dataSize^;
                fd^.Loaded     := true;
                if Error <> nil then Error^ := eNone;
            end else begin
                if OpenMode = omReadWrite then begin
                    if Error <> nil then Error^ := eNone;
                end else begin
                    if Error <> nil then Error^ := eFileDoesNotExist;
                    fd^.InUse := false;
                    kfree(void(dir));
                    kfree(void(fname));
                    fd^.Directory := nil;
                    fd^.FileName  := nil;
                    OutHandle := 0;
                end;
            end;
            kfree(puint32(dataBuf));
            kfree(puint32(dataSize));
            if Callback <> nil then Callback(Error^, CallbackData);
        end else begin
            if Callback <> nil then Callback(eNone, CallbackData);
        end;
    end else begin
        { Write-only or streaming mode — no file data read needed }
        if Error <> nil then Error^ := eNone;
        if Callback <> nil then Callback(eNone, CallbackData);
    end;

    tracer.push_trace('vfs.OpenFileAsync.exit');
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
    pvSplitRel  : PLinkedListBase;
    pvSegCount  : uint32;
    pvIdx       : uint32;
    pvLeafName  : pchar;
    pvParentDir : pchar;
    pvTmpConcat : pchar;
    pvEntry     : PDirectory_Entry;

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
                { Verify the path exists on the volume }
                if (pvVol^.filesystem <> nil) and (pvVol^.filesystem^.readDirCallback <> nil) then begin
                    { If RelPath is just '/' we're at volume root — always valid }
                    if StringEquals(RelPath, '/') then begin
                        PathValid := pvDirectory;
                    end else begin
                        { Split RelPath into parent directory and leaf name,
                          then list the parent and look for the leaf entry. }
                        pvSplitRel := STRLL_FromString(RelPath, '/');
                        pvSegCount := STRLL_Size(pvSplitRel);
                        if pvSegCount = 0 then begin
                            PathValid := pvInvalid;
                        end else begin
                            pvLeafName := STRLL_Get(pvSplitRel, pvSegCount - 1);
                            { Build parent directory path from all segments except the last }
                            if pvSegCount <= 1 then begin
                                pvParentDir := stringNew(1);
                                pvParentDir[0] := '/';
                            end else begin
                                pvParentDir := stringNew(0);
                                for pvIdx := 0 to pvSegCount - 2 do begin
                                    if stringSize(pvParentDir) > 0 then begin
                                        pvTmpConcat := stringConcat(pvParentDir, '/');
                                        kfree(void(pvParentDir));
                                        pvParentDir := pvTmpConcat;
                                    end;
                                    pvTmpConcat := stringConcat(pvParentDir, STRLL_Get(pvSplitRel, pvIdx));
                                    kfree(void(pvParentDir));
                                    pvParentDir := pvTmpConcat;
                                end;
                            end;
                            { List parent directory }
                            pvStatus := puint32(kalloc(4));
                            pvStatus^ := 0;
                            pvDirList := pvVol^.filesystem^.readDirCallback(pvVol, pvParentDir, pvStatus);
                            PathValid := pvInvalid;
                            if (pvDirList <> nil) and (pvStatus^ = 0) and (LL_Size(pvDirList) > 0) then begin
                                for pvIdx := 0 to LL_Size(pvDirList) - 1 do begin
                                    pvEntry := PDirectory_Entry(LL_Get(pvDirList, pvIdx));
                                    if (pvEntry <> nil) and (pvEntry^.fileName <> nil) then begin
                                        if stringEquals(pvEntry^.fileName, pvLeafName) then begin
                                            case pvEntry^.entryType of
                                                fileEntry:      PathValid := pvFile;
                                                directoryEntry: PathValid := pvDirectory;
                                                mountEntry:     PathValid := pvDirectory;
                                            end;
                                            break;
                                        end;
                                    end;
                                end;
                                { Free entry file names and list }
                                for pvIdx := 0 to LL_Size(pvDirList) - 1 do begin
                                    pvEntry := PDirectory_Entry(LL_Get(pvDirList, pvIdx));
                                    if (pvEntry <> nil) and (pvEntry^.fileName <> nil) then
                                        kfree(void(pvEntry^.fileName));
                                end;
                                LL_Free(pvDirList);
                            end else if pvDirList <> nil then
                                LL_Free(pvDirList);
                            kfree(puint32(pvStatus));
                            kfree(void(pvParentDir));
                        end;
                        STRLL_Free(pvSplitRel);
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
            newVirtualDirectory := eNone;
        end else begin
            newVirtualDirectory := eDirectoryAlreadyExists;
        end;
    end;

    STRLL_Free(SplitPath);
    tracer.push_trace('vfs.newVirtualDirectory.exit');
end;

function getWorkingDirectory : pchar;
var
    cwd : pchar;
begin
    tracer.push_trace('vfs.getWorkingDirectory.enter');
    { Return a copy so callers cannot hold a dangling pointer after a cd }
    cwd := nil;
    if (processmanager.CurrentProcess <> nil) and
       (processmanager.CurrentProcess^.Cwd <> nil) then
        cwd := processmanager.CurrentProcess^.Cwd;
    if cwd <> nil then
        getWorkingDirectory := stringCopy(cwd)
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

{ Free a map returned by GetDirectoryListingFrom / volumeGetDirectories.
  Only call this on maps returned for real volumes (otDRIVE / otMOUNT paths),
  NOT on maps for virtual VFS directories (otVDIRECTORY). }
procedure FreeDirectoryListing(map : PHashMap);
var
    i    : uint32;
    item : PHashItem;
    next : PHashItem;
    obj  : PVFSObject;
begin
    if map = nil then exit;
    for i := 0 to map^.Size - 1 do begin
        item := map^.Table[i];
        while item <> nil do begin
            next := item^.Next;
            obj  := PVFSObject(item^.Data);
            if obj <> nil then begin
                if obj^.ObjectName <> nil then kfree(void(obj^.ObjectName));
                kfree(void(obj));
            end;
            if item^.Key <> nil then kfree(void(item^.Key));
            kfree(void(item));
            item := next;
        end;
    end;
    if map^.Table <> nil then kfree(void(map^.Table));
    kfree(void(map));
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

procedure VFS_COMMAND_PUSHD(params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    Output : pchar;
    WD     : pchar;

begin
    WD:= getWorkingDirectory;
    if WD = nil then exit;
    STRLL_Add(PushPopDirectory, WD);
    Output:= StringConcat(WD, ' saved to stack.');
    stdio.bufWriteStrLn(stdout_buf, Output);
    kfree(void(Output));
end;

procedure VFS_COMMAND_POPD(params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    Output : pchar;
    WD     : pchar;

begin
    if STRLL_Size(PushPopDirectory) > 0 then begin
        WD:= STRLL_Get(PushPopDirectory, STRLL_Size(PushPopDirectory)-1);
        if changeDirectory(WD) = pvDirectory then begin
            Output:= StringConcat(WD, ' popped from the stack.');
            stdio.bufWriteStrLn(stdout_buf, Output);
            kfree(void(Output));
        end else begin
            Output:= StringConcat(WD, ' popped, but was invalid!');
            stdio.bufWriteStrLn(stdout_buf, Output);
            kfree(void(Output));
        end;
        STRLL_Delete(PushPopDirectory, STRLL_Size(PushPopDirectory)-1);
    end else begin
        stdio.bufWriteStrLn(stdout_buf, 'No working directory in the stack!');
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

procedure VFS_COMMAND_LS(params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    Map      : PHashMap;
    Item     : PHashItem;
    dirObj   : PVFSObject;
    obj      : PVFSObject;
    i        : uint32;
    col      : uint32;
    mapOwned : boolean;
    wd       : pchar;

begin
    tracer.push_trace('vfs.VFS_COMMAND_LS.enter');
    wd := getWorkingDirectory;
    { Determine if GetDirectoryListing will return a caller-owned (freshly allocated) map }
    dirObj := GetObjectFromPath(wd);
    mapOwned := (dirObj <> nil) and (dirObj^.ObjectType = otDRIVE);
    Map := GetDirectoryListing(wd);
    kfree(void(wd));
    if Map <> nil then begin
        for i:=0 to Map^.Size-1 do begin
            Item:= Map^.Table[i];
            while Item <> nil do begin
                obj:= PVFSObject(Item^.Data);
                stdio.bufWriteStr(stdout_buf, ' ');
                case obj^.ObjectType of
                    otVDIRECTORY : col:= 0;
                    otDRIVE      : col:= 0;
                    otDEVICE     : col:= 0;
                    otVFILE      : col:= 0;
                    otMOUNT      : col:= 0;
                    otFILE       : col:= 0;
                    otDIRECTORY  : col:= 0;
                end;
                stdio.bufWriteStrLn(stdout_buf, Item^.Key);
                Item:= Item^.Next;
            end;
        end;
        if mapOwned then
            freeOwnedDirListing(Map);
    end else begin
        stdio.bufWriteStrLn(stdout_buf, 'An internal error occured!');
    end;
    tracer.push_trace('vfs.VFS_COMMAND_LS.exit');
end;

procedure VFS_COMMAND_CD(params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
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
                stdio.bufWriteStr(stdout_buf, '"');
                stdio.bufWriteStr(stdout_buf, Path);
                stdio.bufWriteStrLn(stdout_buf, '" is not a valid path.');
            end;
            pvFile:begin
                stdio.bufWriteStr(stdout_buf, '"');
                stdio.bufWriteStr(stdout_buf, Path);
                stdio.bufWriteStrLn(stdout_buf, '" is not a directory.');
            end;
        end;
        kfree(void(Path));
    end;
    tracer.push_trace('vfs.VFS_COMMAND_CD.exit');
end;

{ MKDIR command: MKDIR <path> }
procedure VFS_COMMAND_MKDIR(params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
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
        stdio.bufWriteStrLn(stdout_buf, 'Usage: MKDIR <path>');
        tracer.push_trace('vfs.VFS_COMMAND_MKDIR.exit');
        exit;
    end;

    Path := StringCopy(GetParam(0, params));

    { Resolve the path into volume + parent directory + new directory name }
    if not ResolveFilePath(Path, PPStorage_Volume(@vol), PPChar(@dir), PPChar(@dirName)) then begin
        stdio.bufWriteStr(stdout_buf, 'Invalid path: ');
        stdio.bufWriteStrLn(stdout_buf, Path);
        kfree(void(Path));
        tracer.push_trace('vfs.VFS_COMMAND_MKDIR.exit');
        exit;
    end;

    if vol^.filesystem = nil then begin
        stdio.bufWriteStrLn(stdout_buf, 'Volume has no filesystem.');
        kfree(void(Path));
        kfree(void(dir));
        kfree(void(dirName));
        tracer.push_trace('vfs.VFS_COMMAND_MKDIR.exit');
        exit;
    end;

    if vol^.filesystem^.createDirCallback = nil then begin
        stdio.bufWriteStrLn(stdout_buf, 'Filesystem does not support creating directories.');
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
            stdio.bufWriteStrLn(stdout_buf, 'Directory created.');
        eDirectoryDoesNotExist: begin
            stdio.bufWriteStr(stdout_buf, 'Parent directory does not exist: ');
            stdio.bufWriteStrLn(stdout_buf, dir);
        end;
        eDirectoryAlreadyExists:
            stdio.bufWriteStrLn(stdout_buf, 'Directory already exists.');
        eInvalidFileName:
            stdio.bufWriteStrLn(stdout_buf, 'Invalid directory name.');
        eDiskFull:
            stdio.bufWriteStrLn(stdout_buf, 'Disk is full.');
        eDirectoryFull:
            stdio.bufWriteStrLn(stdout_buf, 'Parent directory is full.');
    else
        stdio.bufWriteStrLn(stdout_buf, 'Failed to create directory.');
    end;

    kfree(puint32(status));
    kfree(void(Path));
    kfree(void(dir));
    kfree(void(dirName));
    tracer.push_trace('vfs.VFS_COMMAND_MKDIR.exit');
end;

{ RM command: RM <path> }
procedure VFS_COMMAND_RM(params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
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
        stdio.bufWriteStrLn(stdout_buf, 'Usage: RM <file_path>');
        tracer.push_trace('vfs.VFS_COMMAND_RM.exit');
        exit;
    end;

    Path := StringCopy(GetParam(0, params));

    if not ResolveFilePath(Path, PPStorage_Volume(@vol), PPChar(@dir), PPChar(@fname)) then begin
        stdio.bufWriteStr(stdout_buf, 'Invalid path: ');
        stdio.bufWriteStrLn(stdout_buf, Path);
        kfree(void(Path));
        tracer.push_trace('vfs.VFS_COMMAND_RM.exit');
        exit;
    end;

    if vol^.filesystem = nil then begin
        stdio.bufWriteStrLn(stdout_buf, 'Volume has no filesystem.');
        kfree(void(Path));
        kfree(void(dir));
        kfree(void(fname));
        tracer.push_trace('vfs.VFS_COMMAND_RM.exit');
        exit;
    end;

    if vol^.filesystem^.deleteFileCallback = nil then begin
        stdio.bufWriteStrLn(stdout_buf, 'Filesystem does not support file deletion.');
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
            stdio.bufWriteStr(stdout_buf, 'Deleted: ');
            stdio.bufWriteStrLn(stdout_buf, fname);
        end;
        eFileDoesNotExist:
            stdio.bufWriteStrLn(stdout_buf, 'File not found.');
        ePermissionDenied:
            stdio.bufWriteStrLn(stdout_buf, 'Permission denied.');
        eNotADirectory:
            stdio.bufWriteStrLn(stdout_buf, 'Is a directory. Use RMDIR instead.');
    else
        stdio.bufWriteStrLn(stdout_buf, 'Failed to delete file.');
    end;

    kfree(puint32(status));
    kfree(void(Path));
    kfree(void(fullPath));
    kfree(void(fname));
    tracer.push_trace('vfs.VFS_COMMAND_RM.exit');
end;

{ RMDIR command: RMDIR <path> }
procedure VFS_COMMAND_RMDIR(params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
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
        stdio.bufWriteStrLn(stdout_buf, 'Usage: RMDIR <path>');
        tracer.push_trace('vfs.VFS_COMMAND_RMDIR.exit');
        exit;
    end;

    Path := StringCopy(GetParam(0, params));

    if not ResolveFilePath(Path, PPStorage_Volume(@vol), PPChar(@dir), PPChar(@dirName)) then begin
        stdio.bufWriteStr(stdout_buf, 'Invalid path: ');
        stdio.bufWriteStrLn(stdout_buf, Path);
        kfree(void(Path));
        tracer.push_trace('vfs.VFS_COMMAND_RMDIR.exit');
        exit;
    end;

    if vol^.filesystem = nil then begin
        stdio.bufWriteStrLn(stdout_buf, 'Volume has no filesystem.');
        kfree(void(Path));
        kfree(void(dir));
        kfree(void(dirName));
        tracer.push_trace('vfs.VFS_COMMAND_RMDIR.exit');
        exit;
    end;

    if vol^.filesystem^.deleteDirCallback = nil then begin
        stdio.bufWriteStrLn(stdout_buf, 'Filesystem does not support directory deletion.');
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
            stdio.bufWriteStr(stdout_buf, 'Removed directory: ');
            stdio.bufWriteStrLn(stdout_buf, dirName);
        end;
        eDirectoryDoesNotExist:
            stdio.bufWriteStrLn(stdout_buf, 'Directory not found.');
        eNotADirectory:
            stdio.bufWriteStrLn(stdout_buf, 'Not a directory.');
        eDirectoryNotEmpty:
            stdio.bufWriteStrLn(stdout_buf, 'Directory is not empty.');
        ePermissionDenied:
            stdio.bufWriteStrLn(stdout_buf, 'Permission denied.');
    else
        stdio.bufWriteStrLn(stdout_buf, 'Failed to remove directory.');
    end;

    kfree(puint32(status));
    kfree(void(Path));
    kfree(void(fullPath));
    kfree(void(dirName));
    tracer.push_trace('vfs.VFS_COMMAND_RMDIR.exit');
end;

{ MOUNT command: MOUNT <vol_index> <path> [p] }
procedure VFS_COMMAND_MOUNT(params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
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
        stdio.bufWriteStrLn(stdout_buf, 'Usage: MOUNT <vol_index> <path> [p]');
        stdio.bufWriteStrLn(stdout_buf, '  vol_index  Volume number (see VOL LIST)');
        stdio.bufWriteStrLn(stdout_buf, '  path       VFS mount point, e.g. /mnt/data');
        stdio.bufWriteStrLn(stdout_buf, '  p          Persistent: remount on boot');
        tracer.push_trace('vfs.VFS_COMMAND_MOUNT.exit');
        exit;
    end;

    volIdx := stringToInt(GetParam(0, params));
    if volIdx >= volumemanager.get_volume_count() then begin
        stdio.bufWriteStrLn(stdout_buf, 'Invalid volume index.');
        tracer.push_trace('vfs.VFS_COMMAND_MOUNT.exit');
        exit;
    end;

    vol := volumemanager.get_volume(volIdx);
    if vol = nil then begin
        stdio.bufWriteStrLn(stdout_buf, 'Volume not found.');
        tracer.push_trace('vfs.VFS_COMMAND_MOUNT.exit');
        exit;
    end;

    if vol^.filesystem = nil then begin
        { Try probing as a last resort }
        filesystemmanager.probe_volume(vol);
    end;

    if vol^.filesystem = nil then begin
        stdio.bufWriteStrLn(stdout_buf, 'Volume has no detected filesystem. Format it first.');
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
            stdio.bufWriteStr(stdout_buf, 'Mounted volume ');
            volIdxStr := intToString(volIdx);
            stdio.bufWriteStr(stdout_buf, volIdxStr);
            kfree(void(volIdxStr));
            stdio.bufWriteStr(stdout_buf, ' (');
            stdio.bufWriteStr(stdout_buf, vol^.filesystem^.sName);
            stdio.bufWriteStr(stdout_buf, ') at ');
            stdio.bufWriteStrLn(stdout_buf, path);

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
                        stdio.bufWriteStrLn(stdout_buf, 'Persistent mount saved (asr.mnt).')
                    else
                        stdio.bufWriteStrLn(stdout_buf, 'Warning: could not write asr.mnt.');

                    kfree(puint32(status));
                    kfree(void(dirEntry.fileName));
                end else begin
                    stdio.bufWriteStrLn(stdout_buf, 'Warning: filesystem is read-only, cannot persist.');
                end;
            end;
        end;
    else
        stdio.bufWriteStrLn(stdout_buf, 'Failed to mount volume.');
    end;

    kfree(void(path));
    tracer.push_trace('vfs.VFS_COMMAND_MOUNT.exit');
end;

{ UMOUNT command: UMOUNT <path> }
procedure VFS_COMMAND_UMOUNT(params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    path    : pchar;
    obj     : PVFSObject;
    parentObj : PVFSObject;
    ht      : PHashMap;

begin
    tracer.push_trace('vfs.VFS_COMMAND_UMOUNT.enter');
    if ParamCount(params) < 1 then begin
        stdio.bufWriteStrLn(stdout_buf, 'Usage: UMOUNT <path>');
        tracer.push_trace('vfs.VFS_COMMAND_UMOUNT.exit');
        exit;
    end;

    path := StringCopy(GetParam(0, params));

    obj := GetObjectFromPath(path);
    if obj = nil then begin
        stdio.bufWriteStr(stdout_buf, 'Path not found: ');
        stdio.bufWriteStrLn(stdout_buf, path);
        kfree(void(path));
        tracer.push_trace('vfs.VFS_COMMAND_UMOUNT.exit');
        exit;
    end;

    if obj^.ObjectType <> otDRIVE then begin
        stdio.bufWriteStrLn(stdout_buf, 'Path is not a mount point.');
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

    stdio.bufWriteStr(stdout_buf, 'Unmounted ');
    stdio.bufWriteStrLn(stdout_buf, path);

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

        syslog.writestring('VFS: Mounted ');
        syslog.writestring(vol^.filesystem^.sName);
        syslog.writestring(' volume at ');
        syslog.writestringln(mountPath);

        { If this is the boot volume, also mount it at /boot }
        if vol^.isBootDrive then begin
            mountVolume('/boot', vol);
            syslog.writestringln('VFS: Boot volume mounted at /boot');
        end;

        kfree(void(volName));
        kfree(void(prefix));
        kfree(void(mountPath));

        { Check for persistent mount file asr.mnt — only on writable filesystems
          since read-only media (ISO9660) can never contain an ASR.MNT written by us,
          and attempting to read from a broken/unsupported device can hang. }
        if (vol^.filesystem^.writeCallback <> nil) and
           (vol^.filesystem^.readCallback <> nil) then begin
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

    { Per-process Cwd is initialised to '/' by processmanager.create }

    { Create the Default VFS Directories }
    newVirtualDirectory('/dev');
    newVirtualDirectory('/disk');
    newVirtualDirectory('/mnt');
    newVirtualDirectory('/cfg');
    newVirtualDirectory('/boot');

    { Register Terminal Commands }
    stdio.registerCommand('LS',      @VFS_COMMAND_LS,    'List directory contents.');
    stdio.registerCommand('CD',      @VFS_COMMAND_CD,    'Set working directory.');
    stdio.registerCommand('PUSHD',   @VFS_COMMAND_PUSHD, 'Push the working directory.');
    stdio.registerCommand('POPD',    @VFS_COMMAND_POPD,  'Pop the working directory.');
    stdio.registerCommand('MKDIR',   @VFS_COMMAND_MKDIR, 'Create a directory.');
    stdio.registerCommand('RM',      @VFS_COMMAND_RM,    'Delete a file.');
    stdio.registerCommand('RMDIR',   @VFS_COMMAND_RMDIR, 'Delete a directory.');
    stdio.registerCommand('MOUNT',   @VFS_COMMAND_MOUNT, 'Mount a volume at a path.');
    stdio.registerCommand('UMOUNT',  @VFS_COMMAND_UMOUNT,'Unmount a mounted path.');

    tracer.push_trace('vfs.init.exit');
end;

{ ---- VFS Unit Tests ---- }
procedure UnitTest;
var
    passed, failed : uint32;
    result         : TIsPathValid;
    errCode        : TError;
    absPath        : pchar;
    map            : PHashMap;

    procedure Assert(condition : boolean; testName : pchar);
    var
        msg : pchar;
    begin
        if condition then
            inc(passed)
        else begin
            inc(failed);
            msg := stringConcat('FAIL: ', testName);
            syslog.logln('VFS', msg);
            kfree(void(msg));
        end;
    end;

    procedure PrintSummary;
    var
        pStr, fStr, msg, tmp : pchar;
    begin
        pStr := intToString(passed);
        fStr := intToString(failed);
        msg  := stringConcat(pStr, ' passed, ');
        tmp  := stringConcat(msg, fStr);
        kfree(void(msg));
        msg  := stringConcat(tmp, ' failed.');
        kfree(void(tmp));
        syslog.logln('VFS', msg);
        kfree(void(msg));
        kfree(void(pStr));
        kfree(void(fStr));
    end;

begin
    passed := 0;
    failed := 0;
    syslog.logln('VFS', 'Unit tests starting...');

    { === PathValid: virtual directories created at init === }
    Assert(PathValid('/')      = pvDirectory, 'PathValid(/) = dir');
    Assert(PathValid('/dev')   = pvDirectory, 'PathValid(/dev) = dir');
    Assert(PathValid('/disk')  = pvDirectory, 'PathValid(/disk) = dir');
    Assert(PathValid('/mnt')   = pvDirectory, 'PathValid(/mnt) = dir');
    Assert(PathValid('/cfg')   = pvDirectory, 'PathValid(/cfg) = dir');

    { === PathValid: non-existent paths === }
    Assert(PathValid('/doesnotexist999') = pvInvalid, 'PathValid(nonexistent) = invalid');
    Assert(PathValid('/dev/fakefile')    = pvInvalid, 'PathValid(dev/fake) = invalid');

    { === MakeAbsolutePath: absolute input returned unchanged === }
    absPath := MakeAbsolutePath('/already/abs');
    Assert(stringEquals(absPath, '/already/abs'), 'MakeAbsolutePath absolute passthrough');
    kfree(void(absPath));

    absPath := MakeAbsolutePath('/');
    Assert(stringEquals(absPath, '/'), 'MakeAbsolutePath root');
    kfree(void(absPath));

    { === MakeAbsolutePath: nil/empty becomes root === }
    absPath := MakeAbsolutePath('');
    Assert(absPath <> nil, 'MakeAbsolutePath empty not nil');
    Assert(absPath[0] = '/', 'MakeAbsolutePath empty returns /');
    kfree(void(absPath));

    { === newVirtualDirectory: create a test directory === }
    errCode := newVirtualDirectory('/utest_vfs');
    Assert(errCode = eNone, 'newVirtualDirectory /utest_vfs = eNone');
    Assert(PathValid('/utest_vfs') = pvDirectory, 'PathValid /utest_vfs after create');

    { === newVirtualDirectory: create a nested directory === }
    errCode := newVirtualDirectory('/utest_vfs/sub');
    Assert(errCode = eNone, 'newVirtualDirectory /utest_vfs/sub = eNone');
    Assert(PathValid('/utest_vfs/sub') = pvDirectory, 'PathValid /utest_vfs/sub after create');

    { === newVirtualDirectory: duplicate creation === }
    errCode := newVirtualDirectory('/utest_vfs');
    Assert(errCode <> eNone, 'newVirtualDirectory duplicate fails');

    { === GetDirectoryListingFrom: root should have entries === }
    map := GetDirectoryListingFrom('/', '/');
    Assert(map <> nil, 'GetDirectoryListingFrom(/) not nil');
    { Do not free: root map is VFS-owned, not caller-owned }

    { === GetDirectoryListingFrom: with known virtual dir === }
    map := GetDirectoryListingFrom('/utest_vfs', '/');
    Assert(map <> nil, 'GetDirectoryListingFrom(/utest_vfs) not nil');

    PrintSummary;
end;

end.