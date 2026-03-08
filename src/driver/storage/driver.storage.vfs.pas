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

    @author(Aaron Hance ah@aaronhance.me)
    @author(Kieron Morris kjm@kieronmorris.me)
}
unit driver.storage.vfs;

interface

uses
    driver.storage.fdtable,
    core.ds.hashmap,
    core.ds.lists,
    memory.heap,
    driver.storage.types,
    core.strings,
    io.syslog,
    debug.tracer;

type
    TOpenMode       = (omRead, omWrite, omCreate, omReadWrite, omStream);
    TIsPathValid    = (pvInvalid, pvFile, pvDirectory);
    TRegError       = (pvUnknown, pvNotRegistered, pvRegistered, pvUnregistered);

    TFileHandle = uint32;

    TObjectType = (otVDIRECTORY, otDRIVE, otDEVICE, otVFILE, otMOUNT, otDIRECTORY, otFILE, otSYMLINK);
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
        FileSize   : uint32;
    end;

    PPHashMap = ^PHashMap;

    { Character/block device support — register virtual devices at VFS paths }
    TVFSDevReadFunc  = function(devData : pointer; offset : uint32; buffer : puint8; length : uint32) : uint32;
    TVFSDevWriteFunc = function(devData : pointer; offset : uint32; buffer : puint8; length : uint32) : uint32;
    TVFSDevSizeFunc  = function(devData : pointer) : uint32;

    PVFSDeviceOps = ^TVFSDeviceOps;
    TVFSDeviceOps = record
        Read  : TVFSDevReadFunc;
        Write : TVFSDevWriteFunc;
        Size  : TVFSDevSizeFunc;
    end;

    PVFSDevice = ^TVFSDevice;
    TVFSDevice = record
        Ops     : PVFSDeviceOps;
        DevData : pointer;
    end;

    { Watch/Notify — observe directory mutations }
    TVFSWatchEvent  = (weCreated, weDeleted, weRenamed, weModified);
    TVFSWatchCallback = procedure(event : TVFSWatchEvent; path : pchar; userdata : pointer);

procedure init();
Function OpenFile(Filename : pchar; OpenMode : TOpenMode; Error : PError) : TFileHandle;
function WriteFile(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
function ReadFile(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
function CloseFile(Filehandle : TFileHandle) : TError;

{ Async public API — return immediately, callback fires on completion.
  Callers (e.g. LVGL callbacks) must keep all buffers alive until the
  callback fires. }
procedure WriteFileAsync(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32; Callback : TIOCallback; CallbackData : pointer);
procedure ReadFileAsync(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32; BytesRead : puint32; Callback : TIOCallback; CallbackData : pointer);
procedure OpenFileAsync(Filename : pchar; OpenMode : TOpenMode; var OutHandle : TFileHandle; Error : PError; Callback : TIOCallback; CallbackData : pointer);
procedure DeleteFileAsync(Path : pchar; Error : PError; Callback : TIOCallback; CallbackData : pointer);
procedure DeleteDirectoryAsync(Path : pchar; Error : PError; Callback : TIOCallback; CallbackData : pointer);
{ Async directory listing — callback fires when the snapshot PHashMap is ready.
  The caller must FreeDirectoryListing() the result when done.
  ResultMap^ is set before the callback fires. }
procedure GetDirectoryListingAsync(Path : pchar; ResultMap : PPHashMap; Callback : TIOCallback; CallbackData : pointer);
function FileSize(Filename : pchar; error : PError) : uint32;
function PathValid(Path : pchar) : TIsPathValid;
function ChangeDirectory(Path : pchar) : TIsPathValid;
{ Returns a heap-allocated copy of the current working directory.
  Caller must kfree() the returned pchar when done. }
function GetWorkingDirectory : pchar;
{ Returns a heap-allocated absolute path. Caller must kfree(). }
function MakeAbsolutePathFrom(Path : pchar; BaseDir : pchar) : pchar;
function ResolvePathFrom(Path : pchar; BaseDir : pchar) : TIsPathValid;
{ Returns a caller-owned PHashMap snapshot. Caller must call FreeDirectoryListing(). }
function GetDirectoryListingFrom(Path : pchar; BaseDir : pchar) : PHashMap;
procedure FreeDirectoryListing(map : PHashMap);
function ChangeDirectoryFrom(Path : pchar; BaseDir : pchar; var NewDir : pchar) : TIsPathValid;
{ Returns a heap-allocated absolute path. Caller must kfree(). }
function MakeAbsolutePath(Path : PChar) : pchar;

{ File/Directory management }
function DeleteFile(Path : pchar; Error : PError) : TError;
function DeleteDirectory(Path : pchar; Error : PError) : TError;
function CreateDirectory(Path : pchar; Error : PError) : TError;
function RenameFile(OldPath : pchar; NewName : pchar; Error : PError) : TError;
function SeekFile(Handle : TFileHandle; Offset : uint32) : TError;
function FileSizeFromHandle(Handle : TFileHandle) : uint32;

{ Symlinks }
function CreateSymlink(LinkPath : pchar; TargetPath : pchar) : TError;

{ Register a device node at Path with the given ops table.
  Ops record is deep-copied. DevData pointer is stored as-is. }
function RegisterDevice(Path : pchar; Ops : PVFSDeviceOps; DevData : pointer) : TError;

function WatchDirectory(Path : pchar; Callback : TVFSWatchCallback; UserData : pointer) : uint32;
procedure UnwatchDirectory(WatchID : uint32);

{ VFS Functions }
function newVirtualDirectory(Path : pchar) : TError;
procedure RemoveVirtualTree(Path : pchar);

{ Volume Mount Functions }
function mountVolume(mountPath : pchar; volume : PStorage_Volume) : TRegError;
procedure auto_mount_volumes();
procedure UnitTest;

implementation

uses
    driver.storage.fs.mgr,
    proc.mgr,
    proc.types,
    io.stdio,
    core.util, arch.x86.util,
    driver.storage.vol.mgr;

{ ===================== Implementation constants ============================
  Gathered from watch, symlink, and cache subsystems.
  =========================================================================== }
const
    MAX_VFS_WATCHES   = 1024;
    MAX_SYMLINK_DEPTH = 8;    { maximum symlink hops during path resolution }
    DIR_CACHE_SLOTS   = 64;

{ ===================== Implementation types =================================
  Async-helper contexts, watch entries, directory-cache entries, and private
  pointer-to-pointer aliases.
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

    { GetDirectoryListingAsync context }
    TVFSDirAsyncCtx = record
        Path         : pchar;     { absolute path to list (freed by completion) }
        ResultMap    : PPHashMap;  { caller's pointer — written before callback }
        UserCallback : TIOCallback;
        UserData     : pointer;
    end;
    PVFSDirAsyncCtx = ^TVFSDirAsyncCtx;

    { Watch/Notify infrastructure }
    TVFSWatch = record
        Active     : boolean;
        Path       : pchar;      { absolute watched path }
        Callback   : TVFSWatchCallback;
        UserData   : pointer;
    end;
    PVFSWatch = ^TVFSWatch;

    { Directory Cache (LRU) }
    TVFSDirCacheEntry = record
        Active   : boolean;
        Volume   : PStorage_Volume;
        Path     : pchar;          { heap-allocated relative path key }
        Map      : PHashMap;       { deep-owned snapshot — freed on evict }
        Tick     : uint32;         { last-access tick for LRU eviction }
    end;

    PPStorage_Volume = ^PStorage_Volume;
    PPChar = ^pchar;

var
    Root              : PVFSObject;
    PushPopDirectory  : PLinkedListBase;
    WatchTable        : array[0..MAX_VFS_WATCHES-1] of TVFSWatch;
    WatchInited       : boolean;
    DirCache          : array[0..DIR_CACHE_SLOTS-1] of TVFSDirCacheEntry;
    DirCacheTick      : uint32;
    DirCacheReady     : boolean;

{ ===================== Async helpers ========================================
  Used by OpenFileAsync to stitch results back into the file descriptor.
  =========================================================================== }

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

{ ===================== Watch/Notify infrastructure ========================= }

procedure InitWatchTable;
var
    i : uint32;
begin
    if WatchInited then exit;
    for i := 0 to MAX_VFS_WATCHES - 1 do begin
        WatchTable[i].Active   := false;
        WatchTable[i].Path     := nil;
        WatchTable[i].Callback := nil;
        WatchTable[i].UserData := nil;
    end;
    WatchInited := true;
end;

{ Fire all matching watch callbacks for a given directory path }
procedure FireWatchEvent(event : TVFSWatchEvent; dirPath : pchar; itemPath : pchar);
var
    i : uint32;
begin
    if not WatchInited then exit;
    for i := 0 to MAX_VFS_WATCHES - 1 do begin
        if WatchTable[i].Active and (WatchTable[i].Path <> nil)
           and StringEquals(WatchTable[i].Path, dirPath) then begin
            WatchTable[i].Callback(event, itemPath, WatchTable[i].UserData);
        end;
    end;
end;

{ Internal Functions }

{ ===================== Directory Cache (16-slot LRU) ======================= }

procedure DirCache_Init;
var
    i : uint32;
begin
    if DirCacheReady then exit;
    for i := 0 to DIR_CACHE_SLOTS - 1 do begin
        DirCache[i].Active := false;
        DirCache[i].Volume := nil;
        DirCache[i].Path   := nil;
        DirCache[i].Map    := nil;
        DirCache[i].Tick   := 0;
    end;
    DirCacheTick  := 0;
    DirCacheReady := true;
end;

{ Deep-copy a PHashMap directory listing (same layout as FreeDirectoryListing frees). }
function CloneDirectoryListing(src : PHashMap) : PHashMap;
var
    dst     : PHashMap;
    si      : uint32;
    srcItem : PHashItem;
    srcObj  : PVFSObject;
    dstObj  : PVFSObject;
begin
    CloneDirectoryListing := nil;
    if src = nil then exit;
    dst := core.ds.hashmap.new();
    for si := 0 to src^.Size - 1 do begin
        srcItem := src^.Table[si];
        while srcItem <> nil do begin
            srcObj := PVFSObject(srcItem^.Data);
            if srcObj <> nil then begin
                dstObj := PVFSObject(kalloc(sizeof(TVFSObject)));
                dstObj^.ObjectType := srcObj^.ObjectType;
                dstObj^.ObjectName := stringCopy(srcItem^.Key);
                dstObj^.Reference  := srcObj^.Reference;
                dstObj^.Parent     := srcObj^.Parent;
                dstObj^.FileSize   := srcObj^.FileSize;
                core.ds.hashmap.add(dst, stringCopy(srcItem^.Key), void(dstObj));
            end;
            srcItem := srcItem^.Next;
        end;
    end;
    CloneDirectoryListing := dst;
end;

{ Lookup a cached directory listing. Returns a deep copy (caller owns) or nil on miss. }
function DirCache_Lookup(vol : PStorage_Volume; relPath : pchar) : PHashMap;
var
    i : uint32;
begin
    DirCache_Lookup := nil;
    if not DirCacheReady then exit;
    for i := 0 to DIR_CACHE_SLOTS - 1 do begin
        if DirCache[i].Active and (DirCache[i].Volume = vol)
           and StringEquals(DirCache[i].Path, relPath) then begin
            inc(DirCacheTick);
            DirCache[i].Tick := DirCacheTick;
            debug.tracer.push_trace('DirCache_Lookup.HIT');
            DirCache_Lookup := CloneDirectoryListing(DirCache[i].Map);
            exit;
        end;
    end;
    debug.tracer.push_trace('DirCache_Lookup.MISS');
end;

{ Evict a single cache entry, freeing its owned map. }
procedure DirCache_EvictSlot(idx : uint32);
begin
    if not DirCache[idx].Active then exit;
    if DirCache[idx].Path <> nil then begin
        kfree(void(DirCache[idx].Path));
        DirCache[idx].Path := nil;
    end;
    if DirCache[idx].Map <> nil then begin
        FreeDirectoryListing(DirCache[idx].Map);
        DirCache[idx].Map := nil;
    end;
    DirCache[idx].Active := false;
    DirCache[idx].Volume := nil;
    DirCache[idx].Tick   := 0;
end;

{ Store a directory listing in the cache. Takes a deep copy of map (caller still owns original). }
procedure DirCache_Store(vol : PStorage_Volume; relPath : pchar; map : PHashMap);
var
    i       : uint32;
    minTick : uint32;
    minIdx  : uint32;
begin
    if not DirCacheReady then exit;
    if map = nil then exit;

    { First pass: find an empty slot }
    for i := 0 to DIR_CACHE_SLOTS - 1 do begin
        if not DirCache[i].Active then begin
            inc(DirCacheTick);
            DirCache[i].Active := true;
            DirCache[i].Volume := vol;
            DirCache[i].Path   := stringCopy(relPath);
            DirCache[i].Map    := CloneDirectoryListing(map);
            DirCache[i].Tick   := DirCacheTick;
            debug.tracer.push_trace('DirCache_Store.NEW');
            exit;
        end;
    end;

    { All slots full — evict LRU (lowest Tick) }
    minTick := DirCache[0].Tick;
    minIdx  := 0;
    for i := 1 to DIR_CACHE_SLOTS - 1 do begin
        if DirCache[i].Tick < minTick then begin
            minTick := DirCache[i].Tick;
            minIdx  := i;
        end;
    end;

    DirCache_EvictSlot(minIdx);
    inc(DirCacheTick);
    DirCache[minIdx].Active := true;
    DirCache[minIdx].Volume := vol;
    DirCache[minIdx].Path   := stringCopy(relPath);
    DirCache[minIdx].Map    := CloneDirectoryListing(map);
    DirCache[minIdx].Tick   := DirCacheTick;
    debug.tracer.push_trace('DirCache_Store.EVICT');
end;

{ Invalidate all cache entries for a given volume whose path matches or is
  a prefix of dirPath. E.g. invalidating '/foo' also invalidates '/foo/bar'. }
procedure DirCache_Invalidate(vol : PStorage_Volume; dirPath : pchar);
var
    i : uint32;
begin
    if not DirCacheReady then exit;
    for i := 0 to DIR_CACHE_SLOTS - 1 do begin
        if DirCache[i].Active then begin
            { Match entries for the same volume where the cached path is a
              prefix of the invalidated path, or vice versa, or exact match.
              This ensures parent directories are also invalidated when a
              child is mutated. }
            if (vol = nil) or (DirCache[i].Volume = vol) then begin
                if (dirPath = nil)
                   or StringEquals(DirCache[i].Path, dirPath)
                   or StringContains(DirCache[i].Path, dirPath)
                   or StringContains(dirPath, DirCache[i].Path) then begin
                    debug.tracer.push_trace('DirCache_Invalidate.HIT');
                    DirCache_EvictSlot(i);
                end;
            end;
        end;
    end;
end;

{ ===================== Consolidated Mutation Hook =========================== }
{ Called on every VFS mutation. Invalidates directory cache, then fires
  watch notifications. All mutation call sites should use this instead of
  calling FireWatchEvent directly. }
procedure VFS_OnMutation(event : TVFSWatchEvent; dirPath : pchar; itemPath : pchar; vol : PStorage_Volume; relPath : pchar);
begin
    { Invalidate cache for the volume + relative path }
    DirCache_Invalidate(vol, relPath);
    { Fire watch callbacks }
    FireWatchEvent(event, dirPath, itemPath);
end;

{ =========================================================================== }

function makeRelative(Path : pchar; From : pchar) : pchar;
var
    Result : pchar;
    Tmp    : pchar;

begin
    debug.tracer.push_trace('driver.storage.vfs.makeRelative.enter');
    Result:= nil;
    if (Path = nil) or (From = nil) then begin
        makeRelative:= nil;
        debug.tracer.push_trace('driver.storage.vfs.makeRelative.exit');
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
    debug.tracer.push_trace('driver.storage.vfs.makeRelative.exit');
end;

function createDummyObject(ObjType : TObjectType) : PVFSObject;
begin
    debug.tracer.push_trace('driver.storage.vfs.createDummyObject.enter');
    createDummyObject:= PVFSObject(kalloc(sizeof(TVFSObject)));
    createDummyObject^.ObjectType:= ObjType;
    createDummyObject^.FileSize:= 0;
    debug.tracer.push_trace('driver.storage.vfs.createDummyObject.exit');
end;

function  createVirtualDirectory : PVFSObject;
begin
    debug.tracer.push_trace('driver.storage.vfs.createVirtualDirectory.enter');
    createVirtualDirectory:= PVFSObject(kalloc(sizeof(TVFSObject)));
    createVirtualDirectory^.ObjectType:= otVDIRECTORY;
    createVirtualDirectory^.Reference:= void(core.ds.hashmap.newEx(512, 0.5));
    createVirtualDirectory^.FileSize:= 0;
    debug.tracer.push_trace('driver.storage.vfs.createVirtualDirectory.exit');
end;

function CombineToAbsolutePath(List : PLinkedListBase; Count : uint32) : pchar;
var
    new, old : pchar;
    i : uint32;

begin
    debug.tracer.push_trace('driver.storage.vfs.CombineToAbsolutePath.enter');
    CombineToAbsolutePath:= nil;
    if (Count > 0) and (STRLL_Size(List) < (Count - 1)) then begin
        debug.tracer.push_trace('driver.storage.vfs.CombineToAbsolutePath.shortexit');
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
    debug.tracer.push_trace('driver.storage.vfs.CombineToAbsolutePath.exit');
end;

function evaluatePath(Path : pchar) : pchar;
var
    List : PLinkedListBase;
    i : uint32;
    elm : pchar;

begin
    debug.tracer.push_trace('driver.storage.vfs.evaluatePath.enter');
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
    debug.tracer.push_trace('driver.storage.vfs.evaluatePath.exit');
end;

function getAbsolutePath(Obj : PVFSObject) : pchar;
var
    buf, new, old : pchar;
    iter : PVFSObject;

begin
    debug.tracer.push_trace('driver.storage.vfs.getAbsolutePath.enter');

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

    debug.tracer.push_trace('driver.storage.vfs.getAbsolutePath.exit');
end;

function MakeAbsolutePath(Path : PChar) : pchar;
var
    AbsPath : pchar;
    TempPath : pchar;
    cwd : pchar;

begin
    debug.tracer.push_trace('driver.storage.vfs.MakeAbsolutePath.enter');
    if (Path = nil) or (Path[0] = char(0)) then begin
        MakeAbsolutePath := stringNew(1);
        MakeAbsolutePath[0] := '/';
        debug.tracer.push_trace('driver.storage.vfs.MakeAbsolutePath.exit');
        exit;
    end;
    if Path[0] = '/' then AbsPath:= stringCopy(Path) else begin
        { Get per-process working directory }
        cwd := nil;
        if (proc.mgr.CurrentProcess <> nil) and
           (proc.mgr.CurrentProcess^.Cwd <> nil) then
            cwd := proc.mgr.CurrentProcess^.Cwd;
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
    debug.tracer.push_trace('driver.storage.vfs.MakeAbsolutePath.exit');
end;

function GetObjectFromPathEx(path : pchar; var volRelPath : pchar) : PVFSObject;

    function Depth(path : pchar; dpth : uint32; var vRel : pchar) : PVFSObject;
    var
        Obj         : PVFSObject;
        NewObj      : PVFSObject;
        SplitPath   : PLinkedListBase;
        ht          : PHashMap;
        i           : uint32;
        item        : pchar;
        linkTarget  : pchar;
        resolved    : PVFSObject;
        remainPath  : pchar;
        tmpConcat   : pchar;
        tmpConcat2  : pchar;
        j           : uint32;
        hitDrive    : boolean;
        driveIdx    : uint32;

    begin
        debug.tracer.push_trace('driver.storage.vfs.GetObjectFromPath.enter');
        vRel := nil;
        if dpth > MAX_SYMLINK_DEPTH then begin
            Depth := nil;
            exit;
        end;
        hitDrive := false;
        driveIdx := 0;
        SplitPath:= STRLL_FromString(path, '/');                                                        
        Obj:= Root;                                                                                     
        if STRLL_Size(SplitPath) > 0 then begin                                                         
            for i:=0 to STRLL_Size(SplitPath)-1 do begin                                                
                { Only otVDIRECTORY objects carry a core.ds.hashmap in Reference }
                if Obj^.ObjectType <> otVDIRECTORY then begin
                    break;
                end;
                ht:= PHashMap(Obj^.Reference);
                if ht = nil then begin
                    Depth:= nil;
                    STRLL_Free(SplitPath);
                    debug.tracer.push_trace('driver.storage.vfs.GetObjectFromPath.shortexit_nil_ref');
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
                NewObj:= PVFSObject(core.ds.hashmap.get(ht, item));                                            
                if NewObj = nil then begin                                                              
                    Depth:= nil;
                    STRLL_Free(SplitPath);
                    debug.tracer.push_trace('driver.storage.vfs.GetObjectFromPath.shortexit_1');
                    exit;
                end;
                { Follow symlinks transparently }
                if NewObj^.ObjectType = otSYMLINK then begin
                    linkTarget := pchar(NewObj^.Reference);
                    if linkTarget = nil then begin
                        Depth := nil;
                        STRLL_Free(SplitPath);
                        exit;
                    end;
                    { Build remaining path: linkTarget + rest of segments }
                    remainPath := stringCopy(linkTarget);
                    if i + 1 < STRLL_Size(SplitPath) then begin
                        for j := i + 1 to STRLL_Size(SplitPath) - 1 do begin
                            tmpConcat := stringConcat(remainPath, '/');
                            tmpConcat2 := stringConcat(tmpConcat, STRLL_Get(SplitPath, j));
                            kfree(void(tmpConcat));
                            kfree(void(remainPath));
                            remainPath := tmpConcat2;
                        end;
                    end;
                    resolved := Depth(remainPath, dpth + 1, vRel);
                    kfree(void(remainPath));
                    STRLL_Free(SplitPath);
                    Depth := resolved;
                    exit;
                end;
                Case NewObj^.ObjectType of
                    otVDIRECTORY,otMOUNT:begin                                                          
                        Obj:= NewObj;
                    end;
                    else begin                                                                         
                        Obj:= NewObj;
                        if NewObj^.ObjectType = otDRIVE then begin
                            hitDrive := true;
                            driveIdx := i;
                        end;
                        debug.tracer.push_trace('driver.storage.vfs.GetObjectFromPath.shortexit_2');
                        Break;
                    end;
                end;
            end;
        end;
        { Build volume-relative path from unconsumed segments after DRIVE }
        if hitDrive and (vRel = nil) then begin
            if driveIdx + 1 < STRLL_Size(SplitPath) then begin
                vRel := stringNew(0);
                for j := driveIdx + 1 to STRLL_Size(SplitPath) - 1 do begin
                    tmpConcat := stringConcat(vRel, '/');
                    kfree(void(vRel));
                    tmpConcat2 := stringConcat(tmpConcat, STRLL_Get(SplitPath, j));
                    kfree(void(tmpConcat));
                    vRel := tmpConcat2;
                end;
            end else begin
                vRel := stringNew(1);
                vRel[0] := '/';
            end;
        end;
        STRLL_Free(SplitPath);
        Depth:= Obj;
        debug.tracer.push_trace('driver.storage.vfs.GetObjectFromPath.exit');
    end;

begin
    volRelPath := nil;
    GetObjectFromPathEx := Depth(path, 0, volRelPath);
end;

function GetObjectFromPath(path : pchar) : PVFSObject;
var
    dummy : pchar;
begin
    dummy := nil;
    GetObjectFromPath := GetObjectFromPathEx(path, dummy);
    if dummy <> nil then kfree(void(dummy));
end;

Procedure ChangeCurrentDirectoryValue(new : pchar);
var
    ctx : proc.types.PProcessContext;
begin
    debug.tracer.push_trace('driver.storage.vfs.ChangeCurrentDirectoryValue.enter');
    ctx := proc.mgr.CurrentProcess;
    if ctx <> nil then begin
        if ctx^.Cwd <> nil then kfree(void(ctx^.Cwd));
        ctx^.Cwd := stringCopy(new);
    end;
    debug.tracer.push_trace('driver.storage.vfs.ChangeCurrentDirectoryValue.exit');
end;

{ Volume helper: convert readDirCallback results to a VFS core.ds.hashmap }

function volumeGetDirectories(vol : PStorage_Volume; RelPath : pchar; Parent : PVFSObject) : PHashMap;
var
    dirList    : PLinkedListBase;
    resultMap  : PHashMap;
    status     : puint32;
    entry      : PDirectory_Entry;
    newObj     : PVFSObject;
    i          : uint32;
    cached     : PHashMap;

begin
    debug.tracer.push_trace('driver.storage.vfs.volumeGetDirectories.enter');
    volumeGetDirectories := nil;

    if vol = nil then exit;
    if vol^.filesystem = nil then exit;
    if vol^.filesystem^.readDirCallback = nil then exit;

    { --- Cache lookup --- }
    cached := DirCache_Lookup(vol, RelPath);
    if cached <> nil then begin
        volumeGetDirectories := cached;
        debug.tracer.push_trace('driver.storage.vfs.volumeGetDirectories.cacheHit');
        exit;
    end;

    status := puint32(kalloc(4));
    status^ := 0;
    dirList := vol^.filesystem^.readDirCallback(vol, RelPath, status);

    resultMap := core.ds.hashmap.new();

    if (dirList <> nil) and (status^ = 0) and (LL_Size(dirList) > 0) then begin
        for i := 0 to LL_Size(dirList) - 1 do begin
            entry := PDirectory_Entry(LL_Get(dirList, i));
            if (entry = nil) or (entry^.fileName = nil) then continue;
            newObj := PVFSObject(kalloc(sizeof(TVFSObject)));
            newObj^.Parent := Parent;
            newObj^.Reference := nil;
            newObj^.FileSize := entry^.fileSize;
            case entry^.entryType of
                directoryEntry: newObj^.ObjectType := otDIRECTORY;
                fileEntry:      newObj^.ObjectType := otFILE;
                mountEntry:     newObj^.ObjectType := otMOUNT;
            end;

            { Filesystem provides the display name directly in entry^.fileName }
            newObj^.ObjectName := stringCopy(entry^.fileName);
            core.ds.hashmap.add(resultMap, stringCopy(entry^.fileName), void(newObj));
            { Free the fileName allocated by the filesystem's readDirCallback }
            kfree(void(entry^.fileName));
            entry^.fileName := nil;
        end;
        LL_Free(dirList);
    end else if dirList <> nil then
        LL_Free(dirList);

    { --- Cache store (deep copy kept in cache, caller owns resultMap) --- }
    DirCache_Store(vol, RelPath, resultMap);

    volumeGetDirectories := resultMap;
    kfree(puint32(status));
    debug.tracer.push_trace('driver.storage.vfs.volumeGetDirectories.exit');
end;

Function GetDirectoryListing(Path : pchar) : PHashMap;
var
    Obj      : PVFSObject;
    volRel   : pchar;
    liveMap  : PHashMap;
    snap     : PHashMap;
    si       : uint32;
    liveItem : PHashItem;
    liveObj  : PVFSObject;
    snapObj  : PVFSObject;

begin
    debug.tracer.push_trace('driver.storage.vfs.GetDirectoryListing.enter');
    volRel := nil;
    Obj:= GetObjectFromPathEx(Path, volRel);
    if Obj <> nil then begin
        Case Obj^.ObjectType of
            otVDIRECTORY:begin
                { Return a snapshot copy — FreeDirectoryListing owns the
                  returned map and must NOT free live-tree VFSObjects. }
                liveMap := PHashMap(Obj^.Reference);
                snap    := core.ds.hashmap.new();
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
                                snapObj^.FileSize   := liveObj^.FileSize;
                                core.ds.hashmap.add(snap, stringCopy(liveItem^.Key), void(snapObj));
                            end;
                            liveItem := liveItem^.Next;
                        end;
                    end;
                end;
                GetDirectoryListing := snap;
            end;
            otDRIVE:begin
                if volRel = nil then begin
                    volRel := stringNew(1);
                    volRel[0] := '/';
                end;
                GetDirectoryListing:= volumeGetDirectories(PStorage_Volume(Obj^.Reference), volRel, Obj);
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
    if volRel <> nil then kfree(void(volRel));
    debug.tracer.push_trace('driver.storage.vfs.GetDirectoryListing.exit');
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
    debug.tracer.push_trace('driver.storage.vfs.mountVolume.enter');
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
    mountObj^.FileSize := 0;

    core.ds.hashmap.add(ht, stringCopy(mountName), void(mountObj));
    mountVolume := pvRegistered;

    kfree(void(parentPath));
    STRLL_Free(splitPath);
    debug.tracer.push_trace('driver.storage.vfs.mountVolume.exit');
end;

{ Filesystem Functions }

{ Return the current process's FD table, or nil if no process is running. }
function currentFDTable : PFDTable;
begin
    currentFDTable := nil;
    if proc.mgr.CurrentProcess <> nil then
        currentFDTable := PFDTable(proc.mgr.CurrentProcess^.FDTable);
end;

{ Resolve a full VFS path into a volume + relative dir + filename.
  Returns true if successful.
  dirOut, nameOut are allocated on the heap — caller must free them. }
function ResolveFilePath(FullPath : pchar; volOut : PPStorage_Volume;
                         dirOut : PPChar; nameOut : PPChar) : boolean;
var
    AbsPath    : pchar;
    EvalPath   : pchar;
    Obj        : PVFSObject;
    volRel     : pchar;
    SplitRel   : PLinkedListBase;
    relCount   : uint32;
    j          : uint32;
    dirBuf     : pchar;
    tmpBuf     : pchar;
begin
    debug.tracer.push_trace('driver.storage.vfs.ResolveFilePath.enter');
    ResolveFilePath := false;
    volOut^ := nil;
    dirOut^ := nil;
    nameOut^ := nil;

    { Make absolute and evaluate . / .. }
    AbsPath := MakeAbsolutePath(FullPath);
    EvalPath := evaluatePath(AbsPath);
    kfree(void(AbsPath));

    { Resolve path through VFS (follows symlinks), get remaining in-volume path }
    Obj := GetObjectFromPathEx(EvalPath, volRel);
    kfree(void(EvalPath));

    if (Obj = nil) or (Obj^.ObjectType <> otDRIVE) then begin
        if volRel <> nil then kfree(void(volRel));
        debug.tracer.push_trace('driver.storage.vfs.ResolveFilePath.exit');
        exit;
    end;

    volOut^ := PStorage_Volume(Obj^.Reference);

    { volRel is the path within the volume, e.g. '/mydir/myfile.txt' }
    if (volRel = nil) or StringEquals(volRel, '/') then begin
        { Path points to volume root - no file specified }
        if volRel <> nil then kfree(void(volRel));
        debug.tracer.push_trace('driver.storage.vfs.ResolveFilePath.exit');
        exit;
    end;

    { Split volRel to extract dir + filename }
    SplitRel := STRLL_FromString(volRel, '/');
    kfree(void(volRel));
    relCount := STRLL_Size(SplitRel);

    if relCount = 0 then begin
        STRLL_Free(SplitRel);
        debug.tracer.push_trace('driver.storage.vfs.ResolveFilePath.exit');
        exit;
    end;

    { Last segment is the filename }
    nameOut^ := stringCopy(STRLL_Get(SplitRel, relCount - 1));

    { Build directory path from preceding segments }
    if relCount <= 1 then begin
        dirOut^ := stringNew(0);
    end else begin
        dirBuf := stringNew(0);
        for j := 0 to relCount - 2 do begin
            if stringSize(dirBuf) > 0 then begin
                tmpBuf := stringConcat(dirBuf, '/');
                kfree(void(dirBuf));
                dirBuf := tmpBuf;
            end;
            tmpBuf := stringConcat(dirBuf, STRLL_Get(SplitRel, j));
            kfree(void(dirBuf));
            dirBuf := tmpBuf;
        end;
        dirOut^ := dirBuf;
    end;

    ResolveFilePath := true;
    STRLL_Free(SplitRel);
    debug.tracer.push_trace('driver.storage.vfs.ResolveFilePath.exit');
end;

Function OpenFile(Filename : pchar; OpenMode : TOpenMode; Error : PError) : TFileHandle;
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
    absPath  : pchar;
    vfsObj   : PVFSObject;
    devInfo  : PVFSDevice;
begin
    debug.tracer.push_trace('driver.storage.vfs.OpenFile.enter');
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

    { Check for device node before trying volume resolution }
    absPath := MakeAbsolutePath(Filename);
    vfsObj := GetObjectFromPath(absPath);
    kfree(void(absPath));
    if (vfsObj <> nil) and (vfsObj^.ObjectType = otDEVICE) and (vfsObj^.Reference <> nil) then begin
        devInfo := PVFSDevice(vfsObj^.Reference);
        fd := @tbl^.Entries[slot - 1];
        fd^.InUse := true;
        fd^.Volume := nil;
        fd^.Directory := nil;
        fd^.FileName := stringCopy(vfsObj^.ObjectName);
        fd^.OpenMode := uint8(ord(OpenMode));
        fd^.DataBuffer := nil;
        fd^.DataSize := 0;
        fd^.Loaded := false;
        fd^.StreamOff := 0;
        fd^.DeviceOps := pointer(devInfo^.Ops);
        fd^.DeviceData := devInfo^.DevData;
        if (devInfo^.Ops <> nil) and (devInfo^.Ops^.Size <> nil) then
            fd^.DataSize := devInfo^.Ops^.Size(devInfo^.DevData);
        if Error <> nil then Error^ := eNone;
        OpenFile := slot;
        debug.tracer.push_trace('driver.storage.vfs.OpenFile.exit');
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
    fd^.DataBuffer := nil;
    fd^.DataSize := 0;
    fd^.Loaded := false;
    fd^.StreamOff := 0;

    { If reading, load the file data now }
    if (OpenMode = omRead) or (OpenMode = omReadWrite) then begin
        if vol^.filesystem <> nil then begin
            dataBuf := puint32(kalloc(4));
            dataBuf^ := 0;
            dataSize := puint32(kalloc(4));
            dataSize^ := 0;

            if vol^.filesystem^.readCallback <> nil then begin
                { Sync path: driver.storage.fs.fat32 uses submit_io_wait which parks the calling
                  process via psAwaiting until the driver.storage.ctl.ahci ISR completes the I/O. }
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
    debug.tracer.push_trace('driver.storage.vfs.OpenFile.exit');
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
    debug.tracer.push_trace('driver.storage.vfs.WriteFile.enter');
    WriteFile := 0;

    fd := fd_get(currentFDTable, FileHandle);
    if fd = nil then exit;

    if (TOpenMode(fd^.OpenMode) <> omWrite) and (TOpenMode(fd^.OpenMode) <> omCreate) and (TOpenMode(fd^.OpenMode) <> omReadWrite) and (TOpenMode(fd^.OpenMode) <> omStream) then exit;
    if Buffer = nil then exit;

    { Device dispatch: use the device write callback }
    if fd^.DeviceOps <> nil then begin
        if PVFSDeviceOps(fd^.DeviceOps)^.Write <> nil then begin
            if TOpenMode(fd^.OpenMode) = omStream then begin
                WriteFile := PVFSDeviceOps(fd^.DeviceOps)^.Write(fd^.DeviceData, fd^.StreamOff, Buffer, Length);
                fd^.StreamOff := fd^.StreamOff + WriteFile;
            end else
                WriteFile := PVFSDeviceOps(fd^.DeviceOps)^.Write(fd^.DeviceData, Position, Buffer, Length);
        end;
        debug.tracer.push_trace('driver.storage.vfs.WriteFile.exit');
        exit;
    end;

    { Streaming mode for volume FDs: use writeOffsetCallback }
    if TOpenMode(fd^.OpenMode) = omStream then begin
        vol := fd^.Volume;
        if vol = nil then exit;
        if vol^.filesystem = nil then exit;
        if vol^.filesystem^.writeOffsetCallback = nil then exit;
        WriteFile := vol^.filesystem^.writeOffsetCallback(
            vol, fd^.Directory, fd^.FileName,
            fd^.StreamOff, puint32(Buffer), Length);
        fd^.StreamOff := fd^.StreamOff + WriteFile;
        debug.tracer.push_trace('driver.storage.vfs.WriteFile.exit');
        exit;
    end;

    vol := fd^.Volume;
    if vol = nil then exit;
    if vol^.filesystem = nil then exit;

    { Build a TDirectory_Entry for the write callback }
    dirEntry.fileName  := fd^.FileName;
    dirEntry.entryType := fileEntry;
    dirEntry.fileSize  := Length;
    dirEntry.modifiedDate := 0;
    dirEntry.modifiedTime := 0;
    dirEntry.attributes   := 0;

    { Filesystem writeFile may read full sectors from the buffer regardless of Length.
      Pad to at least 4096 bytes to prevent reading past the allocation. }
    padSize := Length;
    if padSize < 4096 then padSize := 4096;
    padBuf := puint32(kalloc(padSize));
    memset(uint32(padBuf), 0, padSize);
    if Length > 0 then
        core.util.memcpy(uint32(Buffer), uint32(padBuf), Length);

    if vol^.filesystem^.writeCallback <> nil then begin
        { Sync path: driver.storage.fs.fat32 uses submit_io_wait which parks the calling process
          via psAwaiting until the driver.storage.ctl.ahci ISR completes the I/O. }
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

    debug.tracer.push_trace('driver.storage.vfs.WriteFile.exit');
end;

function ReadFile(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
var
    fd       : PFileDescriptor;
    copyLen  : uint32;
begin
    debug.tracer.push_trace('driver.storage.vfs.ReadFile.enter');
    ReadFile := 0;

    fd := fd_get(currentFDTable, FileHandle);
    if fd = nil then exit;

    { Device dispatch: use the device read callback }
    if fd^.DeviceOps <> nil then begin
        if PVFSDeviceOps(fd^.DeviceOps)^.Read = nil then exit;
        if Buffer = nil then exit;
        if TOpenMode(fd^.OpenMode) = omStream then begin
            ReadFile := PVFSDeviceOps(fd^.DeviceOps)^.Read(fd^.DeviceData, fd^.StreamOff, Buffer, Length);
            fd^.StreamOff := fd^.StreamOff + ReadFile;
        end else begin
            ReadFile := PVFSDeviceOps(fd^.DeviceOps)^.Read(fd^.DeviceData, Position, Buffer, Length);
        end;
        debug.tracer.push_trace('driver.storage.vfs.ReadFile.exit');
        exit;
    end;

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
        debug.tracer.push_trace('driver.storage.vfs.ReadFile.exit');
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
        core.util.memcpy(uint32(fd^.DataBuffer) + Position, uint32(Buffer), copyLen);

    ReadFile := copyLen;
    debug.tracer.push_trace('driver.storage.vfs.ReadFile.exit');
end;

function CloseFile(Filehandle : TFileHandle) : TError;
begin
    debug.tracer.push_trace('driver.storage.vfs.CloseFile.enter');
    if fd_close(currentFDTable, FileHandle) then
        CloseFile := eNone
    else
        CloseFile := eInvalidHandle;
    debug.tracer.push_trace('driver.storage.vfs.CloseFile.exit');
end;

function FileSize(Filename : pchar; error : PError) : uint32;
var
    fError  : TError;
    fHandle : TFileHandle;
    fd      : PFileDescriptor;
begin
    debug.tracer.push_trace('driver.storage.vfs.FileSize.enter');
    FileSize := 0;
    if error <> nil then error^ := eUnknown;

    fHandle := OpenFile(Filename, omRead, @fError);
    if (fHandle <> 0) and (fError = eNone) then begin
        fd := fd_get(currentFDTable, fHandle);
        if fd <> nil then
            FileSize := fd^.DataSize;
        if error <> nil then error^ := eNone;
        CloseFile(fHandle);
    end;
    debug.tracer.push_trace('driver.storage.vfs.FileSize.exit');
end;

{ === Async public API === }

{ WriteFileAsync — set up a write and return immediately.
  driver.storage.fs.fat32 deep-copies the buffer on entry so the caller can free it after this returns.
  Callback fires with eNone on success, or a TError code on failure. }
procedure WriteFileAsync(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32; Callback : TIOCallback; CallbackData : pointer);
var
    fd       : PFileDescriptor;
    vol      : PStorage_Volume;
    dirEntry : TDirectory_Entry;
    padBuf   : puint32;
    padSize  : uint32;
begin
    debug.tracer.push_trace('driver.storage.vfs.WriteFileAsync.enter');

    fd := fd_get(currentFDTable, FileHandle);
    if fd = nil then begin
        if Callback <> nil then Callback(eInvalidHandle, CallbackData);
        exit;
    end;

    if (TOpenMode(fd^.OpenMode) <> omWrite) and (TOpenMode(fd^.OpenMode) <> omCreate) and (TOpenMode(fd^.OpenMode) <> omReadWrite) and (TOpenMode(fd^.OpenMode) <> omStream) then begin
        if Callback <> nil then Callback(eReadOnly, CallbackData);
        exit;
    end;

    if Buffer = nil then begin
        if Callback <> nil then Callback(eInvalidArgument, CallbackData);
        exit;
    end;

    { Device dispatch: sync call + immediate callback }
    if fd^.DeviceOps <> nil then begin
        if PVFSDeviceOps(fd^.DeviceOps)^.Write <> nil then begin
            if TOpenMode(fd^.OpenMode) = omStream then begin
                padSize := PVFSDeviceOps(fd^.DeviceOps)^.Write(fd^.DeviceData, fd^.StreamOff, Buffer, Length);
                fd^.StreamOff := fd^.StreamOff + padSize;
            end else
                padSize := PVFSDeviceOps(fd^.DeviceOps)^.Write(fd^.DeviceData, Position, Buffer, Length);
        end else
            padSize := 0;
        if Callback <> nil then Callback(eNone, CallbackData);
        debug.tracer.push_trace('driver.storage.vfs.WriteFileAsync.exit');
        exit;
    end;

    { Streaming mode for volume FDs: use writeOffsetCallback }
    if TOpenMode(fd^.OpenMode) = omStream then begin
        vol := fd^.Volume;
        if (vol = nil) or (vol^.filesystem = nil)
           or (vol^.filesystem^.writeOffsetCallback = nil) then begin
            if Callback <> nil then Callback(eNotSupported, CallbackData);
            exit;
        end;
        padSize := vol^.filesystem^.writeOffsetCallback(
            vol, fd^.Directory, fd^.FileName,
            fd^.StreamOff, puint32(Buffer), Length);
        fd^.StreamOff := fd^.StreamOff + padSize;
        if Callback <> nil then Callback(eNone, CallbackData);
        debug.tracer.push_trace('driver.storage.vfs.WriteFileAsync.exit');
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
        dirEntry.fileSize  := Length;
        dirEntry.modifiedDate := 0;
        dirEntry.modifiedTime := 0;
        dirEntry.attributes   := 0;
        padSize := Length;
        if padSize < 4096 then padSize := 4096;
        padBuf := puint32(kalloc(padSize));
        core.util.memset(uint32(padBuf), 0, padSize);
        if Length > 0 then
            core.util.memcpy(uint32(Buffer), uint32(padBuf), Length);
        { driver.storage.fs.fat32 writeFile_async deep-copies padBuf synchronously before returning }
        vol^.filesystem^.writeAsyncCallback(vol, fd^.Directory, @dirEntry, Length, padBuf, Callback, CallbackData);
        kfree(padBuf);
    end else if vol^.filesystem^.writeCallback <> nil then begin
        { Sync fallback — call directly and fake immediate completion }
        dirEntry.fileName  := fd^.FileName;
        dirEntry.entryType := fileEntry;
        dirEntry.fileSize  := Length;
        dirEntry.modifiedDate := 0;
        dirEntry.modifiedTime := 0;
        dirEntry.attributes   := 0;
        padSize := Length;
        if padSize < 4096 then padSize := 4096;
        padBuf := puint32(kalloc(padSize));
        core.util.memset(uint32(padBuf), 0, padSize);
        if Length > 0 then
            core.util.memcpy(uint32(Buffer), uint32(padBuf), Length);
        vol^.filesystem^.writeCallback(vol, fd^.Directory, @dirEntry, Length, padBuf, nil);
        kfree(padBuf);
        if Callback <> nil then Callback(eNone, CallbackData);
    end else begin
        if Callback <> nil then Callback(eNotSupported, CallbackData);
    end;

    debug.tracer.push_trace('driver.storage.vfs.WriteFileAsync.exit');
end;

{ OpenFileAsync — resolve the path, allocate an FD, kick off async data load.
  OutHandle is set before returning; the FD is not usable until Callback fires.
  If OpenMode is write-only or stream, Callback fires immediately (no disk read). }
procedure OpenFileAsync(Filename : pchar; OpenMode : TOpenMode; var OutHandle : TFileHandle; Error : PError; Callback : TIOCallback; CallbackData : pointer);
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
    debug.tracer.push_trace('driver.storage.vfs.OpenFileAsync.enter');
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
    fd^.DataBuffer:= nil;
    fd^.DataSize  := 0;
    fd^.Loaded    := false;
    fd^.StreamOff := 0;
    OutHandle := slot;

    if (OpenMode = omRead) or (OpenMode = omReadWrite) then begin
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

    debug.tracer.push_trace('driver.storage.vfs.OpenFileAsync.exit');
end;

function PathValid(Path : pchar) : TIsPathValid;
var
    Obj : PVFSObject;
    ObjPath : pchar;
    RelPath : pchar;
    AbsPath : pchar;
    CopyPath : pchar;
    MntPath  : pchar;
    volRel   : pchar;
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
    debug.tracer.push_trace('driver.storage.vfs.PathValid.enter');
    PathValid:= pvInvalid;
    volRel := nil;
    Obj:= GetObjectFromPathEx(Path, volRel);
    if Obj <> nil then begin
        Case Obj^.ObjectType of
            otVDIRECTORY:begin
                PathValid:= pvDirectory;
            end;
            otDRIVE:begin
                RelPath := volRel;
                volRel := nil; { ownership transferred to RelPath }
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
                kfree(void(RelPath));
            end; 
            otDEVICE:begin
                PathValid:= pvFile;
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
                    debug.tracer.push_trace('driver.storage.vfs.PathValid.exit');
                    exit;
                end;
                { Grab the Redirect Path i.e. /disk/disk1 }
                MntPath:= PVFSMount(Obj^.Reference)^.Path;
                if MntPath = nil then begin
                    kfree(void(RelPath));
                    kfree(void(ObjPath));
                    PathValid := pvInvalid;
                    debug.tracer.push_trace('driver.storage.vfs.PathValid.exit');
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
    if volRel <> nil then kfree(void(volRel));
    debug.tracer.push_trace('driver.storage.vfs.PathValid.exit');
end;

function ChangeDirectory(Path : pchar) : TIsPathValid;
var
    TempPath : pchar;
    AbsPath : pchar;
    Validity : TIsPathValid;

begin
    debug.tracer.push_trace('driver.storage.vfs.ChangeDirectory.enter');
    TempPath:= MakeAbsolutePath(Path);
    AbsPath:= evaluatePath(TempPath);
    kfree(void(TempPath));
    Validity:= PathValid(AbsPath);
    if (Validity = pvDirectory) then begin
        ChangeCurrentDirectoryValue(AbsPath);
    end;
    ChangeDirectory:= Validity;
    kfree(void(AbsPath));
    debug.tracer.push_trace('driver.storage.vfs.ChangeDirectory.exit');
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
    debug.tracer.push_trace('driver.storage.vfs.newVirtualDirectory.enter');
    newVirtualDirectory := eUnknown;

    AbsPath := MakeAbsolutePath(Path);
    SplitPath := STRLL_FromString(AbsPath, '/');
    kfree(void(AbsPath));

    splitSize := STRLL_Size(SplitPath);
    if splitSize = 0 then begin
        STRLL_Free(SplitPath);
        newVirtualDirectory := eInvalidPath;
        debug.tracer.push_trace('driver.storage.vfs.newVirtualDirectory.exit');
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
                debug.tracer.push_trace('driver.storage.vfs.newVirtualDirectory.shortexit');
                exit;
            end;
        end;
        Map := PHashMap(Obj^.Reference);
        Key := STRLL_Get(SplitPath, STRLL_Size(SplitPath) - 1);
        Entry := PVFSObject(core.ds.hashmap.get(Map, Key));
        If Entry = nil then begin
            Entry := createVirtualDirectory();
            Entry^.ObjectName := stringCopy(ObjectName);
            Entry^.Parent := Obj;
            core.ds.hashmap.add(Map, stringCopy(Key), void(Entry));
            newVirtualDirectory := eNone;
        end else begin
            newVirtualDirectory := eDirectoryAlreadyExists;
        end;
    end;

    STRLL_Free(SplitPath);
    debug.tracer.push_trace('driver.storage.vfs.newVirtualDirectory.exit');
end;

{ Recursively free a VFS object tree (vdirs + symlinks).
  Does NOT remove the object from its parent hashmap — caller must do that. }
procedure FreeVFSObjTree(obj : PVFSObject);
var
    ht    : PHashMap;
    i     : uint32;
    item  : PHashItem;
    next  : PHashItem;
    child : PVFSObject;
begin
    if obj = nil then exit;
    if (obj^.ObjectType = otVDIRECTORY) and (obj^.Reference <> nil) then begin
        ht := PHashMap(obj^.Reference);
        if (ht <> nil) and (ht^.Table <> nil) and (ht^.Size > 0) then begin
            for i := 0 to ht^.Size - 1 do begin
                item := ht^.Table[i];
                while item <> nil do begin
                    next := item^.Next;
                    child := PVFSObject(item^.Data);
                    if child <> nil then
                        FreeVFSObjTree(child);
                    if item^.Key <> nil then kfree(void(item^.Key));
                    kfree(void(item));
                    item := next;
                end;
            end;
        end;
        if ht <> nil then begin
            if ht^.Table <> nil then kfree(void(ht^.Table));
            kfree(void(ht));
        end;
    end else if obj^.ObjectType = otSYMLINK then begin
        if obj^.Reference <> nil then kfree(void(obj^.Reference));
    end;
    if obj^.ObjectName <> nil then kfree(void(obj^.ObjectName));
    kfree(void(obj));
end;

procedure RemoveVirtualTree(Path : pchar);
var
    splitPath  : PLinkedListBase;
    parentPath : pchar;
    leafName   : pchar;
    leafCopy   : pchar;
    parentObj  : PVFSObject;
    childObj   : PVFSObject;
    ht         : PHashMap;
begin
    if Path = nil then exit;
    splitPath := STRLL_FromString(Path, '/');
    if STRLL_Size(splitPath) = 0 then begin
        STRLL_Free(splitPath);
        exit;
    end;
    leafName := STRLL_Get(splitPath, STRLL_Size(splitPath) - 1);
    leafCopy := stringCopy(leafName);
    parentPath := CombineToAbsolutePath(splitPath, STRLL_Size(splitPath) - 1);
    STRLL_Free(splitPath);

    parentObj := GetObjectFromPath(parentPath);
    kfree(void(parentPath));

    if parentObj = nil then begin
        kfree(void(leafCopy));
        exit;
    end;
    if parentObj^.ObjectType <> otVDIRECTORY then begin
        kfree(void(leafCopy));
        exit;
    end;
    ht := PHashMap(parentObj^.Reference);
    if ht = nil then begin
        kfree(void(leafCopy));
        exit;
    end;

    childObj := PVFSObject(core.ds.hashmap.get(ht, leafCopy));
    if childObj = nil then begin
        kfree(void(leafCopy));
        exit;
    end;

    { Remove from parent hashmap (frees the hashmap's key copy) }
    core.ds.hashmap.delete(ht, leafCopy, false);
    kfree(void(leafCopy));

    { Recursively free the object tree }
    FreeVFSObjTree(childObj);
end;

function GetWorkingDirectory : pchar;
var
    cwd : pchar;
begin
    debug.tracer.push_trace('driver.storage.vfs.GetWorkingDirectory.enter');
    { Return a heap-allocated copy so callers cannot hold a dangling pointer after a cd.
      Caller must kfree() the returned pchar when done. }
    cwd := nil;
    if (proc.mgr.CurrentProcess <> nil) and
       (proc.mgr.CurrentProcess^.Cwd <> nil) then
        cwd := proc.mgr.CurrentProcess^.Cwd;
    if cwd <> nil then
        GetWorkingDirectory := stringCopy(cwd)
    else
        GetWorkingDirectory := nil;
    debug.tracer.push_trace('driver.storage.vfs.GetWorkingDirectory.exit');
end;

function MakeAbsolutePathFrom(Path : pchar; BaseDir : pchar) : pchar;
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
    MakeAbsolutePathFrom := AbsPath;
end;

function ResolvePathFrom(Path : pchar; BaseDir : pchar) : TIsPathValid;
var
    TempPath : pchar;
    AbsPath  : pchar;
begin
    TempPath := MakeAbsolutePathFrom(Path, BaseDir);
    AbsPath := evaluatePath(TempPath);
    kfree(void(TempPath));
    ResolvePathFrom := PathValid(AbsPath);
    kfree(void(AbsPath));
end;

function GetDirectoryListingFrom(Path : pchar; BaseDir : pchar) : PHashMap;
var
    TempPath : pchar;
    AbsPath  : pchar;
begin
    TempPath := MakeAbsolutePathFrom(Path, BaseDir);
    AbsPath := evaluatePath(TempPath);
    kfree(void(TempPath));
    GetDirectoryListingFrom := GetDirectoryListing(AbsPath);
    kfree(void(AbsPath));
end;

{ Free a caller-owned directory listing snapshot returned by
  GetDirectoryListing / GetDirectoryListingFrom. Always safe to call. }
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

function ChangeDirectoryFrom(Path : pchar; BaseDir : pchar; var NewDir : pchar) : TIsPathValid;
var
    TempPath : pchar;
    AbsPath  : pchar;
    Validity : TIsPathValid;
begin
    TempPath := MakeAbsolutePathFrom(Path, BaseDir);
    AbsPath := evaluatePath(TempPath);
    kfree(void(TempPath));
    Validity := PathValid(AbsPath);
    if Validity = pvDirectory then
        NewDir := AbsPath
    else begin
        NewDir := nil;
        kfree(void(AbsPath));
    end;
    ChangeDirectoryFrom := Validity;
end;

{ ===================== Public File/Directory Management API ================ }

function DeleteFile(Path : pchar; Error : PError) : TError;
var
    vol      : PStorage_Volume;
    dir      : pchar;
    fname    : pchar;
    fullPath : pchar;
    tmpPath  : pchar;
    status   : puint32;
    errCode  : TError;
begin
    debug.tracer.push_trace('driver.storage.vfs.DeleteFile.enter');
    DeleteFile := eUnknown;
    if Error <> nil then Error^ := eUnknown;

    if Path = nil then begin
        DeleteFile := eInvalidArgument;
        if Error <> nil then Error^ := eInvalidArgument;
        debug.tracer.push_trace('driver.storage.vfs.DeleteFile.exit');
        exit;
    end;

    if not ResolveFilePath(Path, PPStorage_Volume(@vol), PPChar(@dir), PPChar(@fname)) then begin
        DeleteFile := eInvalidPath;
        if Error <> nil then Error^ := eInvalidPath;
        debug.tracer.push_trace('driver.storage.vfs.DeleteFile.exit');
        exit;
    end;

    if (vol^.filesystem = nil) or (vol^.filesystem^.deleteFileCallback = nil) then begin
        DeleteFile := eNotSupported;
        if Error <> nil then Error^ := eNotSupported;
        kfree(void(dir));
        kfree(void(fname));
        debug.tracer.push_trace('driver.storage.vfs.DeleteFile.exit');
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

    DeleteFile := errCode;
    if Error <> nil then Error^ := errCode;

    if errCode = eNone then
        VFS_OnMutation(weDeleted, Path, Path, vol, fullPath);

    kfree(puint32(status));
    kfree(void(fullPath));
    kfree(void(fname));
    debug.tracer.push_trace('driver.storage.vfs.DeleteFile.exit');
end;

function DeleteDirectory(Path : pchar; Error : PError) : TError;
var
    vol      : PStorage_Volume;
    dir      : pchar;
    dirName  : pchar;
    fullPath : pchar;
    tmpPath  : pchar;
    status   : puint32;
    errCode  : TError;
begin
    debug.tracer.push_trace('driver.storage.vfs.DeleteDirectory.enter');
    DeleteDirectory := eUnknown;
    if Error <> nil then Error^ := eUnknown;

    if Path = nil then begin
        DeleteDirectory := eInvalidArgument;
        if Error <> nil then Error^ := eInvalidArgument;
        debug.tracer.push_trace('driver.storage.vfs.DeleteDirectory.exit');
        exit;
    end;

    if not ResolveFilePath(Path, PPStorage_Volume(@vol), PPChar(@dir), PPChar(@dirName)) then begin
        DeleteDirectory := eInvalidPath;
        if Error <> nil then Error^ := eInvalidPath;
        debug.tracer.push_trace('driver.storage.vfs.DeleteDirectory.exit');
        exit;
    end;

    if (vol^.filesystem = nil) or (vol^.filesystem^.deleteDirCallback = nil) then begin
        DeleteDirectory := eNotSupported;
        if Error <> nil then Error^ := eNotSupported;
        kfree(void(dir));
        kfree(void(dirName));
        debug.tracer.push_trace('driver.storage.vfs.DeleteDirectory.exit');
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

    DeleteDirectory := errCode;
    if Error <> nil then Error^ := errCode;

    if errCode = eNone then
        VFS_OnMutation(weDeleted, Path, Path, vol, fullPath);

    kfree(puint32(status));
    kfree(void(fullPath));
    kfree(void(dirName));
    debug.tracer.push_trace('driver.storage.vfs.DeleteDirectory.exit');
end;

function CreateDirectory(Path : pchar; Error : PError) : TError;
var
    vol      : PStorage_Volume;
    dir      : pchar;
    dirName  : pchar;
    status   : puint32;
    errCode  : TError;
begin
    debug.tracer.push_trace('driver.storage.vfs.CreateDirectory.enter');
    CreateDirectory := eUnknown;
    if Error <> nil then Error^ := eUnknown;

    if Path = nil then begin
        CreateDirectory := eInvalidArgument;
        if Error <> nil then Error^ := eInvalidArgument;
        debug.tracer.push_trace('driver.storage.vfs.CreateDirectory.exit');
        exit;
    end;

    if not ResolveFilePath(Path, PPStorage_Volume(@vol), PPChar(@dir), PPChar(@dirName)) then begin
        CreateDirectory := eInvalidPath;
        if Error <> nil then Error^ := eInvalidPath;
        debug.tracer.push_trace('driver.storage.vfs.CreateDirectory.exit');
        exit;
    end;

    if (vol^.filesystem = nil) or (vol^.filesystem^.createDirCallback = nil) then begin
        CreateDirectory := eNotSupported;
        if Error <> nil then Error^ := eNotSupported;
        kfree(void(dir));
        kfree(void(dirName));
        debug.tracer.push_trace('driver.storage.vfs.CreateDirectory.exit');
        exit;
    end;

    status := puint32(kalloc(4));
    status^ := 0;

    vol^.filesystem^.createDirCallback(vol, dir, dirName, $10, status);
    errCode := TError(status^);

    CreateDirectory := errCode;
    if Error <> nil then Error^ := errCode;

    if errCode = eNone then
        VFS_OnMutation(weCreated, Path, Path, vol, dir);

    kfree(puint32(status));
    kfree(void(dir));
    kfree(void(dirName));
    debug.tracer.push_trace('driver.storage.vfs.CreateDirectory.exit');
end;

function SeekFile(Handle : TFileHandle; Offset : uint32) : TError;
var
    fd : PFileDescriptor;
begin
    debug.tracer.push_trace('driver.storage.vfs.SeekFile.enter');

    fd := fd_get(currentFDTable, Handle);
    if fd = nil then begin
        SeekFile := eInvalidHandle;
        debug.tracer.push_trace('driver.storage.vfs.SeekFile.exit');
        exit;
    end;

    if TOpenMode(fd^.OpenMode) <> omStream then begin
        SeekFile := eNotStreamMode;
        debug.tracer.push_trace('driver.storage.vfs.SeekFile.exit');
        exit;
    end;

    fd^.StreamOff := Offset;
    SeekFile := eNone;
    debug.tracer.push_trace('driver.storage.vfs.SeekFile.exit');
end;

function FileSizeFromHandle(Handle : TFileHandle) : uint32;
var
    fd : PFileDescriptor;
begin
    debug.tracer.push_trace('driver.storage.vfs.FileSizeFromHandle.enter');
    FileSizeFromHandle := 0;

    fd := fd_get(currentFDTable, Handle);
    if fd = nil then begin
        debug.tracer.push_trace('driver.storage.vfs.FileSizeFromHandle.exit');
        exit;
    end;

    { Device nodes: query size callback if available }
    if (fd^.DeviceOps <> nil) and (PVFSDeviceOps(fd^.DeviceOps)^.Size <> nil) then begin
        FileSizeFromHandle := PVFSDeviceOps(fd^.DeviceOps)^.Size(fd^.DeviceData);
        debug.tracer.push_trace('driver.storage.vfs.FileSizeFromHandle.exit');
        exit;
    end;

    FileSizeFromHandle := fd^.DataSize;
    debug.tracer.push_trace('driver.storage.vfs.FileSizeFromHandle.exit');
end;

{ ===================== Async Read ========================================== }

procedure ReadFileAsync(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32; BytesRead : puint32; Callback : TIOCallback; CallbackData : pointer);
var
    fd       : PFileDescriptor;
    copyLen  : uint32;
begin
    debug.tracer.push_trace('driver.storage.vfs.ReadFileAsync.enter');

    fd := fd_get(currentFDTable, FileHandle);
    if fd = nil then begin
        if BytesRead <> nil then BytesRead^ := 0;
        if Callback <> nil then Callback(eInvalidHandle, CallbackData);
        exit;
    end;

    if Buffer = nil then begin
        if BytesRead <> nil then BytesRead^ := 0;
        if Callback <> nil then Callback(eInvalidArgument, CallbackData);
        exit;
    end;

    { Device dispatch: sync call + immediate callback }
    if fd^.DeviceOps <> nil then begin
        if PVFSDeviceOps(fd^.DeviceOps)^.Read <> nil then begin
            if TOpenMode(fd^.OpenMode) = omStream then begin
                copyLen := PVFSDeviceOps(fd^.DeviceOps)^.Read(fd^.DeviceData, fd^.StreamOff, Buffer, Length);
                fd^.StreamOff := fd^.StreamOff + copyLen;
            end else
                copyLen := PVFSDeviceOps(fd^.DeviceOps)^.Read(fd^.DeviceData, Position, Buffer, Length);
            if BytesRead <> nil then BytesRead^ := copyLen;
        end else begin
            if BytesRead <> nil then BytesRead^ := 0;
        end;
        if Callback <> nil then Callback(eNone, CallbackData);
        debug.tracer.push_trace('driver.storage.vfs.ReadFileAsync.exit');
        exit;
    end;

    { Streaming mode: sync readOffsetCallback, then fire callback }
    if TOpenMode(fd^.OpenMode) = omStream then begin
        if (fd^.Volume = nil) or (fd^.Volume^.filesystem = nil)
           or (fd^.Volume^.filesystem^.readOffsetCallback = nil) then begin
            if BytesRead <> nil then BytesRead^ := 0;
            if Callback <> nil then Callback(eNotSupported, CallbackData);
            exit;
        end;
        copyLen := fd^.Volume^.filesystem^.readOffsetCallback(
            fd^.Volume, fd^.Directory, fd^.FileName,
            fd^.StreamOff, puint32(Buffer), Length);
        fd^.StreamOff := fd^.StreamOff + copyLen;
        if BytesRead <> nil then BytesRead^ := copyLen;
        if Callback <> nil then Callback(eNone, CallbackData);
        debug.tracer.push_trace('driver.storage.vfs.ReadFileAsync.exit');
        exit;
    end;

    { Pre-loaded mode: memcpy from buffer — instant }
    if not fd^.Loaded then begin
        if BytesRead <> nil then BytesRead^ := 0;
        if Callback <> nil then Callback(eFileNotLoaded, CallbackData);
        exit;
    end;

    if fd^.DataBuffer = nil then begin
        if BytesRead <> nil then BytesRead^ := 0;
        if Callback <> nil then Callback(eNone, CallbackData);
        exit;
    end;

    if Position >= fd^.DataSize then begin
        if BytesRead <> nil then BytesRead^ := 0;
        if Callback <> nil then Callback(eNone, CallbackData);
        exit;
    end;

    copyLen := fd^.DataSize - Position;
    if Length < copyLen then
        copyLen := Length;

    if copyLen > 0 then
        core.util.memcpy(uint32(fd^.DataBuffer) + Position, uint32(Buffer), copyLen);

    if BytesRead <> nil then BytesRead^ := copyLen;
    if Callback <> nil then Callback(eNone, CallbackData);
    debug.tracer.push_trace('driver.storage.vfs.ReadFileAsync.exit');
end;

{ ===================== Async Delete ======================================== }

procedure DeleteFileAsync(Path : pchar; Error : PError; Callback : TIOCallback; CallbackData : pointer);
var
    vol      : PStorage_Volume;
    dir      : pchar;
    fname    : pchar;
    fullPath : pchar;
    tmpPath  : pchar;
    status   : puint32;
    errCode  : TError;
begin
    debug.tracer.push_trace('driver.storage.vfs.DeleteFileAsync.enter');
    if Error <> nil then Error^ := eUnknown;

    if Path = nil then begin
        if Error <> nil then Error^ := eInvalidArgument;
        if Callback <> nil then Callback(eInvalidArgument, CallbackData);
        exit;
    end;

    if not ResolveFilePath(Path, PPStorage_Volume(@vol), PPChar(@dir), PPChar(@fname)) then begin
        if Error <> nil then Error^ := eInvalidPath;
        if Callback <> nil then Callback(eInvalidPath, CallbackData);
        exit;
    end;

    if (vol^.filesystem = nil) then begin
        if Error <> nil then Error^ := eNotSupported;
        kfree(void(dir));
        kfree(void(fname));
        if Callback <> nil then Callback(eNotSupported, CallbackData);
        exit;
    end;

    { Build full relative path }
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

    { Try async hook first, then sync fallback }
    if vol^.filesystem^.deleteFileAsyncCallback <> nil then begin
        status := puint32(kalloc(4));
        status^ := 0;
        vol^.filesystem^.deleteFileAsyncCallback(vol, fullPath, status, Callback, CallbackData);
        { Note: status/fullPath/fname ownership — async callback must handle.
          Since no FS currently implements this async hook, this is a placeholder. }
        kfree(puint32(status));
        kfree(void(fullPath));
        kfree(void(fname));
    end else if vol^.filesystem^.deleteFileCallback <> nil then begin
        status := puint32(kalloc(4));
        status^ := 0;
        vol^.filesystem^.deleteFileCallback(vol, fullPath, status);
        errCode := TError(status^);
        if Error <> nil then Error^ := errCode;
        { Fire watch event on success }
        if errCode = eNone then
            VFS_OnMutation(weDeleted, Path, Path, vol, fullPath);
        kfree(puint32(status));
        kfree(void(fullPath));
        kfree(void(fname));
        if Callback <> nil then Callback(errCode, CallbackData);
    end else begin
        if Error <> nil then Error^ := eNotSupported;
        kfree(void(fullPath));
        kfree(void(fname));
        if Callback <> nil then Callback(eNotSupported, CallbackData);
    end;

    debug.tracer.push_trace('driver.storage.vfs.DeleteFileAsync.exit');
end;

procedure DeleteDirectoryAsync(Path : pchar; Error : PError; Callback : TIOCallback; CallbackData : pointer);
var
    vol      : PStorage_Volume;
    dir      : pchar;
    dirName  : pchar;
    fullPath : pchar;
    tmpPath  : pchar;
    status   : puint32;
    errCode  : TError;
begin
    debug.tracer.push_trace('driver.storage.vfs.DeleteDirectoryAsync.enter');
    if Error <> nil then Error^ := eUnknown;

    if Path = nil then begin
        if Error <> nil then Error^ := eInvalidArgument;
        if Callback <> nil then Callback(eInvalidArgument, CallbackData);
        exit;
    end;

    if not ResolveFilePath(Path, PPStorage_Volume(@vol), PPChar(@dir), PPChar(@dirName)) then begin
        if Error <> nil then Error^ := eInvalidPath;
        if Callback <> nil then Callback(eInvalidPath, CallbackData);
        exit;
    end;

    if (vol^.filesystem = nil) then begin
        if Error <> nil then Error^ := eNotSupported;
        kfree(void(dir));
        kfree(void(dirName));
        if Callback <> nil then Callback(eNotSupported, CallbackData);
        exit;
    end;

    { Build full relative path }
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

    { Try async hook first, then sync fallback }
    if vol^.filesystem^.deleteDirAsyncCallback <> nil then begin
        status := puint32(kalloc(4));
        status^ := 0;
        vol^.filesystem^.deleteDirAsyncCallback(vol, fullPath, status, Callback, CallbackData);
        kfree(puint32(status));
        kfree(void(fullPath));
        kfree(void(dirName));
    end else if vol^.filesystem^.deleteDirCallback <> nil then begin
        status := puint32(kalloc(4));
        status^ := 0;
        vol^.filesystem^.deleteDirCallback(vol, fullPath, status);
        errCode := TError(status^);
        if Error <> nil then Error^ := errCode;
        if errCode = eNone then
            VFS_OnMutation(weDeleted, Path, Path, vol, fullPath);
        kfree(puint32(status));
        kfree(void(fullPath));
        kfree(void(dirName));
        if Callback <> nil then Callback(errCode, CallbackData);
    end else begin
        if Error <> nil then Error^ := eNotSupported;
        kfree(void(fullPath));
        kfree(void(dirName));
        if Callback <> nil then Callback(eNotSupported, CallbackData);
    end;

    debug.tracer.push_trace('driver.storage.vfs.DeleteDirectoryAsync.exit');
end;

{ ===================== Async Directory Listing ============================= }

{ Worker process for async directory listing }
procedure vfs_dirlist_worker(pctx : proc.types.PProcessContext);
var
    ctx  : PVFSDirAsyncCtx;
    map  : PHashMap;
begin
    ctx := PVFSDirAsyncCtx(pctx^.Local);
    if ctx = nil then begin
        proc.mgr.proc_exit(1);
        exit;
    end;

    { GetDirectoryListing is sync and may block on disk I/O — safe in a
      dedicated worker process. The result is a caller-owned snapshot. }
    map := GetDirectoryListing(ctx^.Path);
    ctx^.ResultMap^ := map;

    if ctx^.Path <> nil then kfree(void(ctx^.Path));
    if ctx^.UserCallback <> nil then begin
        if map <> nil then
            ctx^.UserCallback(eNone, ctx^.UserData)
        else
            ctx^.UserCallback(eInvalidPath, ctx^.UserData);
    end;
    kfree(void(ctx));
    proc.mgr.proc_exit(0);
end;

procedure GetDirectoryListingAsync(Path : pchar; ResultMap : PPHashMap; Callback : TIOCallback; CallbackData : pointer);
var
    ctx     : PVFSDirAsyncCtx;
    absPath : pchar;
begin
    debug.tracer.push_trace('driver.storage.vfs.GetDirectoryListingAsync.enter');
    if ResultMap <> nil then ResultMap^ := nil;

    if (Path = nil) or (ResultMap = nil) then begin
        if Callback <> nil then Callback(eInvalidArgument, CallbackData);
        exit;
    end;

    absPath := MakeAbsolutePath(Path);

    ctx := PVFSDirAsyncCtx(kalloc(sizeof(TVFSDirAsyncCtx)));
    ctx^.Path         := absPath;
    ctx^.ResultMap    := ResultMap;
    ctx^.UserCallback := Callback;
    ctx^.UserData     := CallbackData;

    proc.mgr.create('vfs.dirls', @vfs_dirlist_worker, void(ctx), 1);
    debug.tracer.push_trace('driver.storage.vfs.GetDirectoryListingAsync.exit');
end;

{ ===================== Rename ============================================== }

function RenameFile(OldPath : pchar; NewName : pchar; Error : PError) : TError;
var
    vol      : PStorage_Volume;
    dir      : pchar;
    fname    : pchar;
    fullPath : pchar;
    tmpPath  : pchar;
    status   : puint32;
    errCode  : TError;
begin
    debug.tracer.push_trace('driver.storage.vfs.RenameFile.enter');
    RenameFile := eUnknown;
    if Error <> nil then Error^ := eUnknown;

    if (OldPath = nil) or (NewName = nil) then begin
        RenameFile := eInvalidArgument;
        if Error <> nil then Error^ := eInvalidArgument;
        debug.tracer.push_trace('driver.storage.vfs.RenameFile.exit');
        exit;
    end;

    if not ResolveFilePath(OldPath, PPStorage_Volume(@vol), PPChar(@dir), PPChar(@fname)) then begin
        RenameFile := eInvalidPath;
        if Error <> nil then Error^ := eInvalidPath;
        debug.tracer.push_trace('driver.storage.vfs.RenameFile.exit');
        exit;
    end;

    if (vol^.filesystem = nil) or (vol^.filesystem^.renameFileCallback = nil) then begin
        RenameFile := eNotSupported;
        if Error <> nil then Error^ := eNotSupported;
        kfree(void(dir));
        kfree(void(fname));
        debug.tracer.push_trace('driver.storage.vfs.RenameFile.exit');
        exit;
    end;

    { Build full relative path within volume: dir/fname }
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

    status := puint32(kalloc(4));
    status^ := 0;

    vol^.filesystem^.renameFileCallback(vol, fullPath, NewName, status);
    errCode := TError(status^);

    RenameFile := errCode;
    if Error <> nil then Error^ := errCode;

    { Fire watch notification on success }
    if errCode = eNone then
        VFS_OnMutation(weRenamed, OldPath, OldPath, vol, fullPath);

    kfree(puint32(status));
    kfree(void(fullPath));
    kfree(void(fname));
    debug.tracer.push_trace('driver.storage.vfs.RenameFile.exit');
end;

{ ===================== Symlinks ============================================ }

function CreateSymlink(LinkPath : pchar; TargetPath : pchar) : TError;
var
    parentObj   : PVFSObject;
    linkObj     : PVFSObject;
    ht          : PHashMap;
    splitPath   : PLinkedListBase;
    linkName    : pchar;
    parentPath  : pchar;
    targetCopy  : pchar;
begin
    debug.tracer.push_trace('driver.storage.vfs.CreateSymlink.enter');
    CreateSymlink := eUnknown;

    if (LinkPath = nil) or (TargetPath = nil) then begin
        CreateSymlink := eInvalidArgument;
        exit;
    end;

    { Split link path into parent + leaf name }
    splitPath := STRLL_FromString(LinkPath, '/');
    if STRLL_Size(splitPath) = 0 then begin
        STRLL_Free(splitPath);
        CreateSymlink := eInvalidPath;
        exit;
    end;

    linkName := STRLL_Get(splitPath, STRLL_Size(splitPath) - 1);
    parentPath := CombineToAbsolutePath(splitPath, STRLL_Size(splitPath) - 1);

    parentObj := GetObjectFromPath(parentPath);
    if parentObj = nil then begin
        kfree(void(parentPath));
        STRLL_Free(splitPath);
        CreateSymlink := eInvalidPath;
        exit;
    end;

    if parentObj^.ObjectType <> otVDIRECTORY then begin
        kfree(void(parentPath));
        STRLL_Free(splitPath);
        CreateSymlink := eNotADirectory;
        exit;
    end;

    ht := PHashMap(parentObj^.Reference);
    if ht = nil then begin
        kfree(void(parentPath));
        STRLL_Free(splitPath);
        CreateSymlink := eUnknown;
        exit;
    end;

    { Check for existing entry with same name }
    if core.ds.hashmap.get(ht, linkName) <> nil then begin
        kfree(void(parentPath));
        STRLL_Free(splitPath);
        CreateSymlink := eAlreadyExists;
        exit;
    end;

    targetCopy := stringCopy(TargetPath);

    linkObj := PVFSObject(kalloc(sizeof(TVFSObject)));
    linkObj^.Parent     := parentObj;
    linkObj^.ObjectName := stringCopy(linkName);
    linkObj^.ObjectType := otSYMLINK;
    linkObj^.Reference  := void(targetCopy);
    linkObj^.FileSize   := 0;

    core.ds.hashmap.add(ht, stringCopy(linkName), void(linkObj));
    CreateSymlink := eNone;

    VFS_OnMutation(weCreated, parentPath, LinkPath, nil, nil);

    kfree(void(parentPath));
    STRLL_Free(splitPath);
    debug.tracer.push_trace('driver.storage.vfs.CreateSymlink.exit');
end;

{ ===================== Device Nodes ======================================== }

function RegisterDevice(Path : pchar; Ops : PVFSDeviceOps; DevData : pointer) : TError;
var
    parentObj  : PVFSObject;
    devObj     : PVFSObject;
    devInfo    : PVFSDevice;
    opsCopy    : PVFSDeviceOps;
    ht         : PHashMap;
    splitPath  : PLinkedListBase;
    devName    : pchar;
    parentPath : pchar;
begin
    debug.tracer.push_trace('driver.storage.vfs.RegisterDevice.enter');
    RegisterDevice := eUnknown;

    if (Path = nil) or (Ops = nil) then begin
        RegisterDevice := eInvalidArgument;
        exit;
    end;

    splitPath := STRLL_FromString(Path, '/');
    if STRLL_Size(splitPath) = 0 then begin
        STRLL_Free(splitPath);
        RegisterDevice := eInvalidPath;
        exit;
    end;

    devName := STRLL_Get(splitPath, STRLL_Size(splitPath) - 1);
    parentPath := CombineToAbsolutePath(splitPath, STRLL_Size(splitPath) - 1);

    parentObj := GetObjectFromPath(parentPath);
    if parentObj = nil then begin
        kfree(void(parentPath));
        STRLL_Free(splitPath);
        RegisterDevice := eDirectoryDoesNotExist;
        exit;
    end;

    if parentObj^.ObjectType <> otVDIRECTORY then begin
        kfree(void(parentPath));
        STRLL_Free(splitPath);
        RegisterDevice := eNotADirectory;
        exit;
    end;

    ht := PHashMap(parentObj^.Reference);
    if ht = nil then begin
        kfree(void(parentPath));
        STRLL_Free(splitPath);
        exit;
    end;

    { Duplicate check }
    if core.ds.hashmap.get(ht, devName) <> nil then begin
        kfree(void(parentPath));
        STRLL_Free(splitPath);
        RegisterDevice := eAlreadyExists;
        exit;
    end;

    { Deep-copy the ops table so caller's record lifetime doesn't matter }
    opsCopy := PVFSDeviceOps(kalloc(sizeof(TVFSDeviceOps)));
    opsCopy^.Read  := Ops^.Read;
    opsCopy^.Write := Ops^.Write;
    opsCopy^.Size  := Ops^.Size;

    { Create the device info record }
    devInfo := PVFSDevice(kalloc(sizeof(TVFSDevice)));
    devInfo^.Ops     := opsCopy;
    devInfo^.DevData := DevData;

    { Create the VFS node }
    devObj := PVFSObject(kalloc(sizeof(TVFSObject)));
    devObj^.Parent     := parentObj;
    devObj^.ObjectName := stringCopy(devName);
    devObj^.ObjectType := otDEVICE;
    devObj^.Reference  := void(devInfo);
    devObj^.FileSize   := 0;

    core.ds.hashmap.add(ht, stringCopy(devName), void(devObj));
    RegisterDevice := eNone;

    kfree(void(parentPath));
    STRLL_Free(splitPath);
    debug.tracer.push_trace('driver.storage.vfs.RegisterDevice.exit');
end;

{ ---- Built-in device callbacks ---- }

{ /dev/null — reads return 0 bytes (EOF), writes are silently discarded }
function DevNull_Read(devData : pointer; offset : uint32; buffer : puint8; length : uint32) : uint32;
begin
    DevNull_Read := 0;
end;

function DevNull_Write(devData : pointer; offset : uint32; buffer : puint8; length : uint32) : uint32;
begin
    DevNull_Write := length;
end;

function DevNull_Size(devData : pointer) : uint32;
begin
    DevNull_Size := 0;
end;

{ /dev/zero — reads return zeroed bytes, writes are silently discarded }
function DevZero_Read(devData : pointer; offset : uint32; buffer : puint8; length : uint32) : uint32;
begin
    if (buffer <> nil) and (length > 0) then
        core.util.memset(uint32(buffer), 0, length);
    DevZero_Read := length;
end;

function DevZero_Write(devData : pointer; offset : uint32; buffer : puint8; length : uint32) : uint32;
begin
    DevZero_Write := length;
end;

function DevZero_Size(devData : pointer) : uint32;
begin
    DevZero_Size := 0;
end;

{ ===================== Watch/Notify ======================================== }

function WatchDirectory(Path : pchar; Callback : TVFSWatchCallback; UserData : pointer) : uint32;
var
    i : uint32;
begin
    debug.tracer.push_trace('driver.storage.vfs.WatchDirectory.enter');
    WatchDirectory := 0;
    InitWatchTable;

    if (Path = nil) or (Callback = nil) then exit;

    for i := 0 to MAX_VFS_WATCHES - 1 do begin
        if not WatchTable[i].Active then begin
            WatchTable[i].Active   := true;
            WatchTable[i].Path     := stringCopy(Path);
            WatchTable[i].Callback := Callback;
            WatchTable[i].UserData := UserData;
            WatchDirectory := i + 1;  { 1-based ID; 0 = failure }
            debug.tracer.push_trace('driver.storage.vfs.WatchDirectory.exit');
            exit;
        end;
    end;

    debug.tracer.push_trace('driver.storage.vfs.WatchDirectory.exit');
end;

procedure UnwatchDirectory(WatchID : uint32);
var
    idx : uint32;
begin
    debug.tracer.push_trace('driver.storage.vfs.UnwatchDirectory.enter');
    InitWatchTable;

    if (WatchID = 0) or (WatchID > MAX_VFS_WATCHES) then exit;
    idx := WatchID - 1;

    if WatchTable[idx].Active then begin
        WatchTable[idx].Active := false;
        if WatchTable[idx].Path <> nil then begin
            kfree(void(WatchTable[idx].Path));
            WatchTable[idx].Path := nil;
        end;
        WatchTable[idx].Callback := nil;
        WatchTable[idx].UserData := nil;
    end;

    debug.tracer.push_trace('driver.storage.vfs.UnwatchDirectory.exit');
end;

{ Terminal Commands }

procedure VFS_COMMAND_PUSHD(params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    Output : pchar;
    WD     : pchar;

begin
    WD:= GetWorkingDirectory;
    if WD = nil then exit;
    STRLL_Add(PushPopDirectory, WD);
    Output:= StringConcat(WD, ' saved to stack.');
    io.stdio.bufWriteStrLn(stdout_buf, Output);
    kfree(void(Output));
end;

procedure VFS_COMMAND_POPD(params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    Output : pchar;
    WD     : pchar;

begin
    if STRLL_Size(PushPopDirectory) > 0 then begin
        WD:= STRLL_Get(PushPopDirectory, STRLL_Size(PushPopDirectory)-1);
        if ChangeDirectory(WD) = pvDirectory then begin
            Output:= StringConcat(WD, ' popped from the stack.');
            io.stdio.bufWriteStrLn(stdout_buf, Output);
            kfree(void(Output));
        end else begin
            Output:= StringConcat(WD, ' popped, but was invalid!');
            io.stdio.bufWriteStrLn(stdout_buf, Output);
            kfree(void(Output));
        end;
        STRLL_Delete(PushPopDirectory, STRLL_Size(PushPopDirectory)-1);
    end else begin
        io.stdio.bufWriteStrLn(stdout_buf, 'No working directory in the stack!');
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
    obj      : PVFSObject;
    i        : uint32;
    wd       : pchar;
    sizeStr  : pchar;
    line     : pchar;
    tmp      : pchar;

begin
    debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_LS.enter');
    wd := GetWorkingDirectory;
    Map := GetDirectoryListing(wd);
    kfree(void(wd));
    if Map <> nil then begin
        for i:=0 to Map^.Size-1 do begin
            Item:= Map^.Table[i];
            while Item <> nil do begin
                obj:= PVFSObject(Item^.Data);
                case obj^.ObjectType of
                    otVDIRECTORY,
                    otDIRECTORY,
                    otMOUNT,
                    otDRIVE: begin
                        line := stringConcat(' <DIR>   ', Item^.Key);
                        io.stdio.bufWriteStrLn(stdout_buf, line);
                        kfree(void(line));
                    end;
                    otDEVICE: begin
                        line := stringConcat(' <DEV>   ', Item^.Key);
                        io.stdio.bufWriteStrLn(stdout_buf, line);
                        kfree(void(line));
                    end;
                    otVFILE: begin
                        line := stringConcat(' <VFL>   ', Item^.Key);
                        io.stdio.bufWriteStrLn(stdout_buf, line);
                        kfree(void(line));
                    end;
                    otSYMLINK: begin
                        tmp := stringConcat(' <LNK>   ', Item^.Key);
                        line := stringConcat(tmp, ' -> ');
                        kfree(void(tmp));
                        if obj^.Reference <> nil then begin
                            tmp := stringConcat(line, pchar(obj^.Reference));
                            kfree(void(line));
                            line := tmp;
                        end;
                        io.stdio.bufWriteStrLn(stdout_buf, line);
                        kfree(void(line));
                    end;
                else begin
                        sizeStr := intToString(obj^.FileSize);
                        tmp := stringConcat(' ', sizeStr);
                        kfree(void(sizeStr));
                        line := stringConcat(tmp, '  ');
                        kfree(void(tmp));
                        tmp := stringConcat(line, Item^.Key);
                        kfree(void(line));
                        io.stdio.bufWriteStrLn(stdout_buf, tmp);
                        kfree(void(tmp));
                    end;
                end;
                Item:= Item^.Next;
            end;
        end;
        { All maps returned by GetDirectoryListing are now caller-owned snapshots }
        FreeDirectoryListing(Map);
    end else begin
        io.stdio.bufWriteStrLn(stdout_buf, 'An internal error occured!');
    end;
    debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_LS.exit');
end;

procedure VFS_COMMAND_CD(params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    Path : pchar;
    Temp1, Temp2 : pchar;
    Result : TIsPathValid;
    i : uint32;

begin
    debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_CD.enter');
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
        Result:= ChangeDirectory(Path);
        case Result of
            pvInvalid:begin
                io.stdio.bufWriteStr(stdout_buf, '"');
                io.stdio.bufWriteStr(stdout_buf, Path);
                io.stdio.bufWriteStrLn(stdout_buf, '" is not a valid path.');
            end;
            pvFile:begin
                io.stdio.bufWriteStr(stdout_buf, '"');
                io.stdio.bufWriteStr(stdout_buf, Path);
                io.stdio.bufWriteStrLn(stdout_buf, '" is not a directory.');
            end;
        end;
        kfree(void(Path));
    end;
    debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_CD.exit');
end;

{ MKDIR command: delegates to CreateDirectory public API }
procedure VFS_COMMAND_MKDIR(params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    Path    : pchar;
    errCode : TError;
begin
    debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_MKDIR.enter');
    if ParamCount(params) < 1 then begin
        io.stdio.bufWriteStrLn(stdout_buf, 'Usage: MKDIR <path>');
        debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_MKDIR.exit');
        exit;
    end;

    Path := StringCopy(GetParam(0, params));
    errCode := CreateDirectory(Path, nil);

    case errCode of
        eNone:
            io.stdio.bufWriteStrLn(stdout_buf, 'Directory created.');
        eInvalidPath: begin
            io.stdio.bufWriteStr(stdout_buf, 'Invalid path: ');
            io.stdio.bufWriteStrLn(stdout_buf, Path);
        end;
        eNotSupported:
            io.stdio.bufWriteStrLn(stdout_buf, 'Filesystem does not support creating directories.');
        eDirectoryDoesNotExist:
            io.stdio.bufWriteStrLn(stdout_buf, 'Parent directory does not exist.');
        eDirectoryAlreadyExists:
            io.stdio.bufWriteStrLn(stdout_buf, 'Directory already exists.');
        eInvalidFileName:
            io.stdio.bufWriteStrLn(stdout_buf, 'Invalid directory name.');
        eDiskFull:
            io.stdio.bufWriteStrLn(stdout_buf, 'Disk is full.');
        eDirectoryFull:
            io.stdio.bufWriteStrLn(stdout_buf, 'Parent directory is full.');
    else
        io.stdio.bufWriteStrLn(stdout_buf, 'Failed to create directory.');
    end;

    kfree(void(Path));
    debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_MKDIR.exit');
end;

{ RM command: delegates to DeleteFile public API }
procedure VFS_COMMAND_RM(params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    Path    : pchar;
    errCode : TError;
begin
    debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_RM.enter');
    if ParamCount(params) < 1 then begin
        io.stdio.bufWriteStrLn(stdout_buf, 'Usage: RM <file_path>');
        debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_RM.exit');
        exit;
    end;

    Path := StringCopy(GetParam(0, params));
    errCode := DeleteFile(Path, nil);

    case errCode of
        eNone: begin
            io.stdio.bufWriteStr(stdout_buf, 'Deleted: ');
            io.stdio.bufWriteStrLn(stdout_buf, Path);
        end;
        eInvalidPath: begin
            io.stdio.bufWriteStr(stdout_buf, 'Invalid path: ');
            io.stdio.bufWriteStrLn(stdout_buf, Path);
        end;
        eNotSupported:
            io.stdio.bufWriteStrLn(stdout_buf, 'Filesystem does not support file deletion.');
        eFileDoesNotExist:
            io.stdio.bufWriteStrLn(stdout_buf, 'File not found.');
        ePermissionDenied:
            io.stdio.bufWriteStrLn(stdout_buf, 'Permission denied.');
        eNotADirectory:
            io.stdio.bufWriteStrLn(stdout_buf, 'Is a directory. Use RMDIR instead.');
    else
        io.stdio.bufWriteStrLn(stdout_buf, 'Failed to delete file.');
    end;

    kfree(void(Path));
    debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_RM.exit');
end;

{ RMDIR command: delegates to DeleteDirectory public API }
procedure VFS_COMMAND_RMDIR(params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    Path    : pchar;
    errCode : TError;
begin
    debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_RMDIR.enter');
    if ParamCount(params) < 1 then begin
        io.stdio.bufWriteStrLn(stdout_buf, 'Usage: RMDIR <path>');
        debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_RMDIR.exit');
        exit;
    end;

    Path := StringCopy(GetParam(0, params));
    errCode := DeleteDirectory(Path, nil);

    case errCode of
        eNone: begin
            io.stdio.bufWriteStr(stdout_buf, 'Removed directory: ');
            io.stdio.bufWriteStrLn(stdout_buf, Path);
        end;
        eInvalidPath: begin
            io.stdio.bufWriteStr(stdout_buf, 'Invalid path: ');
            io.stdio.bufWriteStrLn(stdout_buf, Path);
        end;
        eNotSupported:
            io.stdio.bufWriteStrLn(stdout_buf, 'Filesystem does not support directory deletion.');
        eDirectoryDoesNotExist:
            io.stdio.bufWriteStrLn(stdout_buf, 'Directory not found.');
        eNotADirectory:
            io.stdio.bufWriteStrLn(stdout_buf, 'Not a directory.');
        eDirectoryNotEmpty:
            io.stdio.bufWriteStrLn(stdout_buf, 'Directory is not empty.');
        ePermissionDenied:
            io.stdio.bufWriteStrLn(stdout_buf, 'Permission denied.');
    else
        io.stdio.bufWriteStrLn(stdout_buf, 'Failed to remove directory.');
    end;

    kfree(void(Path));
    debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_RMDIR.exit');
end;

{ MOUNT command: MOUNT <vol_index> <path> [p] }
procedure VFS_COMMAND_MOUNT(params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    volIdx    : uint32;
    volIdxStr : pchar;
    vol       : PStorage_Volume;
    path      : pchar;
    res       : TRegError;

begin
    debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_MOUNT.enter');
    if ParamCount(params) < 2 then begin
        io.stdio.bufWriteStrLn(stdout_buf, 'Usage: MOUNT <vol_index> <path>');
        io.stdio.bufWriteStrLn(stdout_buf, '  vol_index  Volume number (see VOL LIST)');
        io.stdio.bufWriteStrLn(stdout_buf, '  path       VFS mount point, e.g. /mnt/data');
        debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_MOUNT.exit');
        exit;
    end;

    volIdx := stringToInt(GetParam(0, params));
    if volIdx >= driver.storage.vol.mgr.get_volume_count() then begin
        io.stdio.bufWriteStrLn(stdout_buf, 'Invalid volume index.');
        debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_MOUNT.exit');
        exit;
    end;

    vol := driver.storage.vol.mgr.get_volume(volIdx);
    if vol = nil then begin
        io.stdio.bufWriteStrLn(stdout_buf, 'Volume not found.');
        debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_MOUNT.exit');
        exit;
    end;

    if vol^.filesystem = nil then begin
        { Try probing as a last resort }
        driver.storage.fs.mgr.probe_volume(vol);
    end;

    if vol^.filesystem = nil then begin
        io.stdio.bufWriteStrLn(stdout_buf, 'Volume has no detected filesystem. Format it first.');
        debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_MOUNT.exit');
        exit;
    end;

    path := StringCopy(GetParam(1, params));

    res := mountVolume(path, vol);
    case res of
        pvRegistered: begin
            io.stdio.bufWriteStr(stdout_buf, 'Mounted volume ');
            volIdxStr := intToString(volIdx);
            io.stdio.bufWriteStr(stdout_buf, volIdxStr);
            kfree(void(volIdxStr));
            io.stdio.bufWriteStr(stdout_buf, ' (');
            io.stdio.bufWriteStr(stdout_buf, vol^.filesystem^.sName);
            io.stdio.bufWriteStr(stdout_buf, ') at ');
            io.stdio.bufWriteStrLn(stdout_buf, path);
        end;
    else
        io.stdio.bufWriteStrLn(stdout_buf, 'Failed to mount volume.');
    end;

    kfree(void(path));
    debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_MOUNT.exit');
end;

{ UMOUNT command: UMOUNT <path> }
procedure VFS_COMMAND_UMOUNT(params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    path    : pchar;
    obj     : PVFSObject;
    parentObj : PVFSObject;
    ht      : PHashMap;

begin
    debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_UMOUNT.enter');
    if ParamCount(params) < 1 then begin
        io.stdio.bufWriteStrLn(stdout_buf, 'Usage: UMOUNT <path>');
        debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_UMOUNT.exit');
        exit;
    end;

    path := StringCopy(GetParam(0, params));

    obj := GetObjectFromPath(path);
    if obj = nil then begin
        io.stdio.bufWriteStr(stdout_buf, 'Path not found: ');
        io.stdio.bufWriteStrLn(stdout_buf, path);
        kfree(void(path));
        debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_UMOUNT.exit');
        exit;
    end;

    if obj^.ObjectType <> otDRIVE then begin
        io.stdio.bufWriteStrLn(stdout_buf, 'Path is not a mount point.');
        kfree(void(path));
        debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_UMOUNT.exit');
        exit;
    end;

    { Remove from parent core.ds.hashmap (freeItem=false so we control freeing) }
    parentObj := obj^.Parent;
    if parentObj <> nil then begin
        ht := PHashMap(parentObj^.Reference);
        core.ds.hashmap.delete(ht, obj^.ObjectName, false);
    end;

    { Free the object }
    kfree(void(obj^.ObjectName));
    kfree(void(obj));

    io.stdio.bufWriteStr(stdout_buf, 'Unmounted ');
    io.stdio.bufWriteStrLn(stdout_buf, path);

    kfree(void(path));
    debug.tracer.push_trace('driver.storage.vfs.VFS_COMMAND_UMOUNT.exit');
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
    { mount.asr parsing vars }
    lineStart : uint32;
    lineEnd   : uint32;
    lineLen   : uint32;
    lineBuf   : pchar;
    expanded  : pchar;
    argStart  : uint32;
    spacePos  : uint32;
    srcPath   : pchar;
    tgtPath   : pchar;
begin
    debug.tracer.push_trace('driver.storage.vfs.auto_mount_volumes.enter');

    volCount := driver.storage.vol.mgr.get_volume_count();
    if volCount = 0 then begin
        debug.tracer.push_trace('driver.storage.vfs.auto_mount_volumes.exit');
        exit;
    end;

    if volCount > 256 then volCount := 256; { sanity cap }

    for i := 0 to volCount - 1 do begin
        vol := driver.storage.vol.mgr.get_volume(i);
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

        io.syslog.writestring('VFS: Mounted ');
        io.syslog.writestring(vol^.filesystem^.sName);
        io.syslog.writestring(' volume at ');
        io.syslog.writestringln(mountPath);

        { Auto-mount the boot drive at /boot }
        if vol^.isBootDrive then begin
            mountVolume('/boot', vol);
            io.syslog.writestringln('VFS: Mounted boot volume at /boot');
        end;

        kfree(void(volName));
        kfree(void(prefix));
        kfree(void(mountPath));
    end;

    { Process mount.asr from the boot volume.
      Each line has the form:  mnt {device}<source> <target>
      {device} is replaced with the boot volume's /disk/volN path.
      A symlink is created: target -> expanded_source. }
    for i := 0 to volCount - 1 do begin
        vol := driver.storage.vol.mgr.get_volume(i);
        if vol = nil then continue;
        if vol^.filesystem = nil then continue;
        if not vol^.isBootDrive then continue;
        if vol^.filesystem^.readCallback = nil then continue;

        { Build the boot device path: /disk/vol<i> }
        volNumStr := intToString(i);
        volName := stringConcat('/disk/vol', volNumStr);
        kfree(void(volNumStr));

        dataBuf  := puint32(kalloc(4));
        dataBuf^ := 0;
        dataSize := puint32(kalloc(4));
        dataSize^ := 0;

        readErr := vol^.filesystem^.readCallback(vol, '', 'MOUNT.ASR', dataBuf, dataSize);

        if (readErr = 0) and (dataSize^ > 0) and (dataBuf^ <> 0) then begin
            { Parse the file line by line }
            mntLen := dataSize^;
            mntPath := pchar(kalloc(mntLen + 1));
            core.util.memcpy(dataBuf^, uint32(mntPath), mntLen);
            mntPath[mntLen] := char(0);

            lineStart := 0;
            while lineStart < mntLen do begin
                { Find end of line }
                lineEnd := lineStart;
                while (lineEnd < mntLen) and (mntPath[lineEnd] <> char(10)) and (mntPath[lineEnd] <> char(13)) do
                    lineEnd := lineEnd + 1;

                lineLen := lineEnd - lineStart;
                if lineLen > 0 then begin
                    lineBuf := pchar(kalloc(lineLen + 1));
                    core.util.memcpy(uint32(mntPath) + lineStart, uint32(lineBuf), lineLen);
                    lineBuf[lineLen] := char(0);

                    { Check for 'mnt ' prefix }
                    if (lineLen > 4) and
                       (lineBuf[0] = 'm') and (lineBuf[1] = 'n') and
                       (lineBuf[2] = 't') and (lineBuf[3] = ' ') then begin
                        { Replace {device} with actual boot volume path }
                        expanded := stringReplace(lineBuf, '{device}', volName);

                        { Find the two space-separated arguments after 'mnt ' }
                        argStart := 4;
                        { Skip leading spaces }
                        while (argStart < stringSize(expanded)) and (expanded[argStart] = ' ') do
                            argStart := argStart + 1;
                        { Find the space between source and target }
                        spacePos := argStart;
                        while (spacePos < stringSize(expanded)) and (expanded[spacePos] <> ' ') do
                            spacePos := spacePos + 1;

                        if spacePos < stringSize(expanded) then begin
                            srcPath := stringSub(expanded, argStart, spacePos - argStart);
                            { Skip spaces before target }
                            argStart := spacePos + 1;
                            while (argStart < stringSize(expanded)) and (expanded[argStart] = ' ') do
                                argStart := argStart + 1;
                            { Target runs to end of line (strip trailing spaces) }
                            spacePos := stringSize(expanded);
                            while (spacePos > argStart) and (expanded[spacePos - 1] = ' ') do
                                spacePos := spacePos - 1;

                            if spacePos > argStart then begin
                                tgtPath := stringSub(expanded, argStart, spacePos - argStart);

                                CreateSymlink(tgtPath, srcPath);

                                io.syslog.writestring('VFS: mount.asr symlink ');
                                io.syslog.writestring(tgtPath);
                                io.syslog.writestring(' -> ');
                                io.syslog.writestringln(srcPath);

                                kfree(void(tgtPath));
                            end;
                            kfree(void(srcPath));
                        end;
                        kfree(void(expanded));
                    end;
                    kfree(void(lineBuf));
                end;

                { Advance past line ending (handle CR, LF, CRLF) }
                if (lineEnd < mntLen) and (mntPath[lineEnd] = char(13)) then
                    lineEnd := lineEnd + 1;
                if (lineEnd < mntLen) and (mntPath[lineEnd] = char(10)) then
                    lineEnd := lineEnd + 1;
                lineStart := lineEnd;
            end;

            kfree(void(mntPath));
            kfree(puint32(dataBuf^));
        end;

        kfree(puint32(dataBuf));
        kfree(puint32(dataSize));
        kfree(void(volName));
        break; { only one boot volume }
    end;

    debug.tracer.push_trace('driver.storage.vfs.auto_mount_volumes.exit');
end;

{ Init }

procedure init();
var
    ht : PHashMap;
    obj : PVFSObject;
    nullOps : TVFSDeviceOps;
    zeroOps : TVFSDeviceOps;

begin
    debug.tracer.push_trace('driver.storage.vfs.init.enter');

    { Init watch table }
    WatchInited := false;
    InitWatchTable;

    { Init directory cache }
    DirCacheReady := false;
    DirCache_Init;

    { VFS Root Creation }
    Root:= createVirtualDirectory();
    Root^.Parent:= nil;
    Root^.ObjectName:= stringNew(1);
    Root^.ObjectName[0]:= '/';

    { Init Push/Pop Stack for PUSHD & POPD }
    PushPopDirectory:= STRLL_New;

    { Per-process Cwd is initialised to '/' by proc.mgr.create }

    { Create the Default VFS Directories }
    newVirtualDirectory('/dev');
    newVirtualDirectory('/disk');
    newVirtualDirectory('/mnt');

    { Register built-in device nodes }
    nullOps.Read  := @DevNull_Read;
    nullOps.Write := @DevNull_Write;
    nullOps.Size  := @DevNull_Size;
    RegisterDevice('/dev/null', @nullOps, nil);

    zeroOps.Read  := @DevZero_Read;
    zeroOps.Write := @DevZero_Write;
    zeroOps.Size  := @DevZero_Size;
    RegisterDevice('/dev/zero', @zeroOps, nil);

    { Register Terminal Commands }
    io.stdio.registerCommand('LS',      @VFS_COMMAND_LS,    'List directory contents.');
    io.stdio.registerCommand('CD',      @VFS_COMMAND_CD,    'Set working directory.');
    io.stdio.registerCommand('PUSHD',   @VFS_COMMAND_PUSHD, 'Push the working directory.');
    io.stdio.registerCommand('POPD',    @VFS_COMMAND_POPD,  'Pop the working directory.');
    io.stdio.registerCommand('MKDIR',   @VFS_COMMAND_MKDIR, 'Create a directory.');
    io.stdio.registerCommand('RM',      @VFS_COMMAND_RM,    'Delete a file.');
    io.stdio.registerCommand('RMDIR',   @VFS_COMMAND_RMDIR, 'Delete a directory.');
    io.stdio.registerCommand('MOUNT',   @VFS_COMMAND_MOUNT, 'Mount a volume at a path.');
    io.stdio.registerCommand('UMOUNT',  @VFS_COMMAND_UMOUNT,'Unmount a mounted path.');

    debug.tracer.push_trace('driver.storage.vfs.init.exit');
end;

{ ---- VFS Unit Tests ---- }

{ Watch test callback — increments the uint32 pointed to by userdata }
procedure UTestWatchCb(event : TVFSWatchEvent; path : pchar; userdata : pointer);
begin
    if userdata <> nil then
        inc(puint32(userdata)^);
end;

procedure UnitTest;
var
    passed, failed : uint32;
    result         : TIsPathValid;
    errCode        : TError;
    absPath        : pchar;
    map            : PHashMap;
    map2           : PHashMap;
    obj            : PVFSObject;
    watchId        : uint32;
    watchFired     : uint32;
    watchEvt       : TVFSWatchEvent;
    i              : uint32;
    tmpKey         : pchar;
    devHandle      : TFileHandle;
    devErr         : TError;
    devBuf         : puint8;
    devRead        : uint32;
    devBytesRead   : uint32;
    devCallbackOk  : boolean;
    devOps         : TVFSDeviceOps;

    procedure Assert(condition : boolean; testName : pchar);
    var
        msg : pchar;
    begin
        if condition then
            inc(passed)
        else begin
            inc(failed);
            msg := stringConcat('FAIL: ', testName);
            io.syslog.logln('VFS', msg);
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
        io.syslog.logln('VFS', msg);
        kfree(void(msg));
        kfree(void(pStr));
        kfree(void(fStr));
    end;

begin
    passed := 0;
    failed := 0;
    watchFired := 0;
    io.syslog.logln('VFS', 'Unit tests starting...');

    { ======================================================================= }
    { Phase 1 — PathValid: virtual directories created at init                }
    { ======================================================================= }
    Assert(PathValid('/')      = pvDirectory, 'PathValid(/) = dir');
    Assert(PathValid('/dev')   = pvDirectory, 'PathValid(/dev) = dir');
    Assert(PathValid('/disk')  = pvDirectory, 'PathValid(/disk) = dir');
    Assert(PathValid('/mnt')   = pvDirectory, 'PathValid(/mnt) = dir');

    { PathValid: non-existent paths }
    Assert(PathValid('/doesnotexist999') = pvInvalid, 'PathValid(nonexistent) = invalid');
    Assert(PathValid('/dev/fakefile')    = pvInvalid, 'PathValid(dev/fake) = invalid');

    { ======================================================================= }
    { Phase 1 — MakeAbsolutePath                                             }
    { ======================================================================= }
    absPath := MakeAbsolutePath('/already/abs');
    Assert(stringEquals(absPath, '/already/abs'), 'MakeAbsolutePath absolute passthrough');
    kfree(void(absPath));

    absPath := MakeAbsolutePath('/');
    Assert(stringEquals(absPath, '/'), 'MakeAbsolutePath root');
    kfree(void(absPath));

    absPath := MakeAbsolutePath('');
    Assert(absPath <> nil, 'MakeAbsolutePath empty not nil');
    Assert(absPath[0] = '/', 'MakeAbsolutePath empty returns /');
    kfree(void(absPath));

    { ======================================================================= }
    { Phase 1 — newVirtualDirectory + duplicate detection                     }
    { ======================================================================= }
    errCode := newVirtualDirectory('/utest_vfs');
    Assert(errCode = eNone, 'newVirtualDirectory /utest_vfs = eNone');
    Assert(PathValid('/utest_vfs') = pvDirectory, 'PathValid /utest_vfs after create');

    errCode := newVirtualDirectory('/utest_vfs/sub');
    Assert(errCode = eNone, 'newVirtualDirectory /utest_vfs/sub = eNone');
    Assert(PathValid('/utest_vfs/sub') = pvDirectory, 'PathValid /utest_vfs/sub');

    errCode := newVirtualDirectory('/utest_vfs');
    Assert(errCode <> eNone, 'newVirtualDirectory duplicate fails');

    { ======================================================================= }
    { Phase 1 — GetDirectoryListingFrom: root + subdir                        }
    { ======================================================================= }
    map := GetDirectoryListingFrom('/', '/');
    Assert(map <> nil, 'GetDirListingFrom(/) not nil');
    FreeDirectoryListing(map);

    map := GetDirectoryListingFrom('/utest_vfs', '/');
    Assert(map <> nil, 'GetDirListingFrom(/utest_vfs) not nil');
    { Verify snapshot contains 'sub' entry }
    obj := PVFSObject(core.ds.hashmap.get(map, 'sub'));
    Assert(obj <> nil, 'listing /utest_vfs has sub entry');
    if obj <> nil then
        Assert(obj^.ObjectType = otVDIRECTORY, 'sub entry is otVDIRECTORY');
    FreeDirectoryListing(map);

    { Snapshot independence: two listings don't alias }
    map  := GetDirectoryListingFrom('/utest_vfs', '/');
    map2 := GetDirectoryListingFrom('/utest_vfs', '/');
    Assert(map <> map2, 'two snapshots are distinct pointers');
    FreeDirectoryListing(map);
    FreeDirectoryListing(map2);

    { ======================================================================= }
    { Phase 4 — CreateSymlink                                                 }
    { ======================================================================= }
    { Nil args }
    Assert(CreateSymlink(nil, '/dev') = eInvalidArgument, 'Symlink nil link = eInvalidArgument');
    Assert(CreateSymlink('/utest_vfs/sl', nil) = eInvalidArgument, 'Symlink nil target = eInvalidArgument');

    { Create symlink pointing to /dev }
    errCode := CreateSymlink('/utest_vfs/devlink', '/dev');
    Assert(errCode = eNone, 'CreateSymlink /utest_vfs/devlink = eNone');

    { Symlink resolves: PathValid through symlink to /dev which is a directory }
    Assert(PathValid('/utest_vfs/devlink') = pvDirectory, 'PathValid through symlink = dir');

    { Duplicate symlink name }
    Assert(CreateSymlink('/utest_vfs/devlink', '/mnt') = eAlreadyExists, 'Symlink duplicate = eAlreadyExists');

    { Symlink in non-existent parent }
    Assert(CreateSymlink('/utest_vfs/nosuchdir/link', '/dev') = eInvalidPath, 'Symlink bad parent = eInvalidPath');

    { Verify symlink appears in listing }
    map := GetDirectoryListingFrom('/utest_vfs', '/');
    Assert(map <> nil, 'listing after symlink not nil');
    obj := PVFSObject(core.ds.hashmap.get(map, 'devlink'));
    Assert(obj <> nil, 'listing has devlink entry');
    if obj <> nil then
        Assert(obj^.ObjectType = otSYMLINK, 'devlink entry is otSYMLINK');
    FreeDirectoryListing(map);

    { ======================================================================= }
    { Phase 4b — Symlink path traversal (subdirectory after symlink)          }
    { ======================================================================= }
    { Setup: create /utest_vfs/deep/child so we can symlink to /utest_vfs/deep
      and verify traversal into child works through the symlink. }
    errCode := newVirtualDirectory('/utest_vfs/deep');
    Assert(errCode = eNone, 'newVDir /utest_vfs/deep = eNone');
    errCode := newVirtualDirectory('/utest_vfs/deep/child');
    Assert(errCode = eNone, 'newVDir /utest_vfs/deep/child = eNone');
    errCode := newVirtualDirectory('/utest_vfs/deep/child/leaf');
    Assert(errCode = eNone, 'newVDir /utest_vfs/deep/child/leaf = eNone');

    { Symlink /utest_vfs/sdeep -> /utest_vfs/deep }
    errCode := CreateSymlink('/utest_vfs/sdeep', '/utest_vfs/deep');
    Assert(errCode = eNone, 'CreateSymlink sdeep -> deep = eNone');

    { PathValid: symlink target is a directory }
    Assert(PathValid('/utest_vfs/sdeep') = pvDirectory, 'PathValid symlink sdeep = dir');

    { PathValid: traverse INTO symlink target's children }
    Assert(PathValid('/utest_vfs/sdeep/child') = pvDirectory, 'PathValid sdeep/child = dir');
    Assert(PathValid('/utest_vfs/sdeep/child/leaf') = pvDirectory, 'PathValid sdeep/child/leaf = dir');

    { PathValid: non-existent child after symlink }
    Assert(PathValid('/utest_vfs/sdeep/nope') = pvInvalid, 'PathValid sdeep/nope = invalid');

    { GetDirectoryListing through symlink shows children }
    map := GetDirectoryListing('/utest_vfs/sdeep');
    Assert(map <> nil, 'GetDirListing through symlink not nil');
    if map <> nil then begin
        obj := PVFSObject(core.ds.hashmap.get(map, 'child'));
        Assert(obj <> nil, 'symlink listing has child entry');
        if obj <> nil then
            Assert(obj^.ObjectType = otVDIRECTORY, 'child entry through symlink is vdir');
        FreeDirectoryListing(map);
    end;

    { GetDirectoryListing deeper through symlink }
    map := GetDirectoryListing('/utest_vfs/sdeep/child');
    Assert(map <> nil, 'GetDirListing sdeep/child not nil');
    if map <> nil then begin
        obj := PVFSObject(core.ds.hashmap.get(map, 'leaf'));
        Assert(obj <> nil, 'sdeep/child listing has leaf entry');
        FreeDirectoryListing(map);
    end;

    { ======================================================================= }
    { Phase 4c — Chained symlinks (symlink -> symlink -> vdir)                }
    { ======================================================================= }
    { /utest_vfs/chain1 -> /utest_vfs/sdeep (which -> /utest_vfs/deep) }
    errCode := CreateSymlink('/utest_vfs/chain1', '/utest_vfs/sdeep');
    Assert(errCode = eNone, 'CreateSymlink chain1 -> sdeep = eNone');

    { Double-hop: chain1 -> sdeep -> deep, should resolve to /utest_vfs/deep }
    Assert(PathValid('/utest_vfs/chain1') = pvDirectory, 'PathValid chain1 = dir');
    Assert(PathValid('/utest_vfs/chain1/child') = pvDirectory, 'PathValid chain1/child = dir');

    { GetDirectoryListing through chained symlink }
    map := GetDirectoryListing('/utest_vfs/chain1');
    Assert(map <> nil, 'GetDirListing chain1 not nil');
    if map <> nil then begin
        obj := PVFSObject(core.ds.hashmap.get(map, 'child'));
        Assert(obj <> nil, 'chain1 listing has child');
        FreeDirectoryListing(map);
    end;

    { ======================================================================= }
    { Phase 4d — Symlink cycle detection (max depth guard)                    }
    { ======================================================================= }
    { Create a cycle: /utest_vfs/cyc_a -> /utest_vfs/cyc_b
                      /utest_vfs/cyc_b -> /utest_vfs/cyc_a }
    errCode := CreateSymlink('/utest_vfs/cyc_a', '/utest_vfs/cyc_b');
    Assert(errCode = eNone, 'CreateSymlink cyc_a -> cyc_b = eNone');
    errCode := CreateSymlink('/utest_vfs/cyc_b', '/utest_vfs/cyc_a');
    Assert(errCode = eNone, 'CreateSymlink cyc_b -> cyc_a = eNone');

    { PathValid on a cycle should return pvInvalid (not hang or crash) }
    Assert(PathValid('/utest_vfs/cyc_a') = pvInvalid, 'PathValid symlink cycle = invalid');

    { GetDirectoryListing on a cycle returns nil }
    map := GetDirectoryListing('/utest_vfs/cyc_a');
    Assert(map = nil, 'GetDirListing symlink cycle = nil');

    { ======================================================================= }
    { Phase 4e — Symlink to root (/) }
    { ======================================================================= }
    errCode := CreateSymlink('/utest_vfs/rootlink', '/');
    Assert(errCode = eNone, 'CreateSymlink rootlink -> / = eNone');
    Assert(PathValid('/utest_vfs/rootlink') = pvDirectory, 'PathValid rootlink = dir');
    Assert(PathValid('/utest_vfs/rootlink/dev') = pvDirectory, 'PathValid rootlink/dev = dir');
    Assert(PathValid('/utest_vfs/rootlink/dev/null') = pvFile, 'PathValid rootlink/dev/null = file');

    map := GetDirectoryListing('/utest_vfs/rootlink');
    Assert(map <> nil, 'GetDirListing rootlink not nil');
    if map <> nil then begin
        obj := PVFSObject(core.ds.hashmap.get(map, 'dev'));
        Assert(obj <> nil, 'rootlink listing has dev');
        FreeDirectoryListing(map);
    end;

    { ======================================================================= }
    { Phase 4 — WatchDirectory / UnwatchDirectory                             }
    { ======================================================================= }
    { Nil/invalid args return 0 }
    Assert(WatchDirectory(nil, @UTestWatchCb, nil) = 0, 'WatchDir nil path = 0');
    Assert(WatchDirectory('/dev', nil, nil) = 0, 'WatchDir nil callback = 0');

    { Register a watch on /utest_vfs }
    watchFired := 0;
    watchId := WatchDirectory('/utest_vfs', @UTestWatchCb, @watchFired);
    Assert(watchId <> 0, 'WatchDir /utest_vfs returns nonzero ID');

    { Trigger mutation: create a symlink in watched dir }
    errCode := CreateSymlink('/utest_vfs/watchtest', '/cfg');
    Assert(errCode = eNone, 'CreateSymlink for watch test = eNone');

    { Verify callback was called }
    Assert(watchFired = 1, 'Watch callback fired once');

    { Unwatch and trigger another mutation — should NOT fire }
    UnwatchDirectory(watchId);
    errCode := CreateSymlink('/utest_vfs/watchtest2', '/cfg');
    Assert(errCode = eNone, 'CreateSymlink after unwatch = eNone');
    Assert(watchFired = 1, 'Watch callback not fired after unwatch');

    { Unwatch with invalid IDs — no crash }
    UnwatchDirectory(0);
    UnwatchDirectory(9999);

    { ======================================================================= }
    { Phase 5 — Directory Cache (DirCache)                                    }
    { ======================================================================= }
    { Build a small test map to exercise the cache }
    map := core.ds.hashmap.new();
    obj := PVFSObject(kalloc(sizeof(TVFSObject)));
    obj^.ObjectType := otVDIRECTORY;
    obj^.ObjectName := stringCopy('ctest');
    obj^.Parent := nil;
    obj^.Reference := nil;
    obj^.FileSize := 0;
    core.ds.hashmap.add(map, stringCopy('ctest'), void(obj));

    { Store into cache with nil volume }
    DirCache_Store(nil, '/cachetest', map);

    { Lookup should return a valid deep copy }
    map2 := DirCache_Lookup(nil, '/cachetest');
    Assert(map2 <> nil, 'DirCache_Lookup hit after store');
    if map2 <> nil then begin
        obj := PVFSObject(core.ds.hashmap.get(map2, 'ctest'));
        Assert(obj <> nil, 'Cache clone has ctest entry');
        if obj <> nil then
            Assert(obj^.ObjectType = otVDIRECTORY, 'Cache ctest is otVDIRECTORY');
        FreeDirectoryListing(map2);
    end;

    { Clone is independent — freeing it doesn't break a second lookup }
    map2 := DirCache_Lookup(nil, '/cachetest');
    Assert(map2 <> nil, 'DirCache_Lookup second hit still valid');
    if map2 <> nil then
        FreeDirectoryListing(map2);

    { Invalidate and verify miss }
    DirCache_Invalidate(nil, '/cachetest');
    map2 := DirCache_Lookup(nil, '/cachetest');
    Assert(map2 = nil, 'DirCache_Lookup miss after invalidate');

    { LRU eviction: fill all 16 slots + 1 to force eviction }
    for i := 0 to DIR_CACHE_SLOTS do begin
        tmpKey := intToString(i);
        DirCache_Store(nil, tmpKey, map);
        kfree(void(tmpKey));
    end;
    { First entry (key '0') should have been evicted since it had lowest tick }
    map2 := DirCache_Lookup(nil, '0');
    Assert(map2 = nil, 'DirCache LRU evicted oldest slot');
    { Last entry should still be cached }
    tmpKey := intToString(DIR_CACHE_SLOTS);
    map2 := DirCache_Lookup(nil, tmpKey);
    Assert(map2 <> nil, 'DirCache LRU newest slot still cached');
    if map2 <> nil then
        FreeDirectoryListing(map2);
    kfree(void(tmpKey));

    { Clean up: invalidate all test entries }
    DirCache_Invalidate(nil, nil);
    { Free the test source map }
    FreeDirectoryListing(map);

    { ======================================================================= }
    { Phase 6 — Device Nodes (/dev/null, /dev/zero, RegisterDevice)           }
    { ======================================================================= }

    { PathValid: device nodes are files }
    Assert(PathValid('/dev/null') = pvFile, 'PathValid /dev/null = pvFile');
    Assert(PathValid('/dev/zero') = pvFile, 'PathValid /dev/zero = pvFile');

    { RegisterDevice: duplicate detection }
    devOps.Read  := @DevNull_Read;
    devOps.Write := @DevNull_Write;
    devOps.Size  := @DevNull_Size;
    Assert(RegisterDevice('/dev/null', @devOps, nil) = eAlreadyExists, 'RegisterDevice dup = eAlreadyExists');

    { RegisterDevice: nil args }
    Assert(RegisterDevice(nil, @devOps, nil) = eInvalidArgument, 'RegisterDevice nil path');
    Assert(RegisterDevice('/dev/test', nil, nil) = eInvalidArgument, 'RegisterDevice nil ops');

    { RegisterDevice: bad parent }
    Assert(RegisterDevice('/nosuchdir/dev', @devOps, nil) = eDirectoryDoesNotExist, 'RegisterDevice bad parent');

    { /dev/null — open + read returns 0 bytes (EOF) }
    devHandle := OpenFile('/dev/null', omRead, @devErr);
    Assert((devHandle <> 0) and (devErr = eNone), 'OpenFile /dev/null ok');
    devBuf := puint8(kalloc(64));
    core.util.memset(uint32(devBuf), $FF, 64);
    devRead := ReadFile(devHandle, 0, devBuf, 64);
    Assert(devRead = 0, '/dev/null read returns 0');
    Assert(FileSizeFromHandle(devHandle) = 0, '/dev/null size = 0');
    CloseFile(devHandle);

    { /dev/null — open write mode, write is accepted }
    devHandle := OpenFile('/dev/null', omWrite, @devErr);
    Assert((devHandle <> 0) and (devErr = eNone), 'OpenFile /dev/null write ok');
    devRead := WriteFile(devHandle, 0, devBuf, 32);
    Assert(devRead = 32, '/dev/null write returns length');
    CloseFile(devHandle);

    { /dev/zero — open + read fills buffer with zeroes }
    core.util.memset(uint32(devBuf), $FF, 64);
    devHandle := OpenFile('/dev/zero', omRead, @devErr);
    Assert((devHandle <> 0) and (devErr = eNone), 'OpenFile /dev/zero ok');
    devRead := ReadFile(devHandle, 0, devBuf, 64);
    Assert(devRead = 64, '/dev/zero read returns length');
    Assert(devBuf[0] = 0, '/dev/zero byte 0 = 0');
    Assert(devBuf[63] = 0, '/dev/zero byte 63 = 0');
    CloseFile(devHandle);

    { /dev/zero — stream mode: two sequential reads advance offset }
    devHandle := OpenFile('/dev/zero', omStream, @devErr);
    Assert((devHandle <> 0) and (devErr = eNone), 'OpenFile /dev/zero stream ok');
    core.util.memset(uint32(devBuf), $FF, 64);
    devRead := ReadFile(devHandle, 0, devBuf, 16);
    Assert(devRead = 16, '/dev/zero stream read1 = 16');
    Assert(devBuf[0] = 0, '/dev/zero stream read1 byte 0 = 0');
    devRead := ReadFile(devHandle, 0, devBuf, 16);
    Assert(devRead = 16, '/dev/zero stream read2 = 16');
    CloseFile(devHandle);

    { /dev/zero — ReadFileAsync device dispatch }
    devHandle := OpenFile('/dev/zero', omRead, @devErr);
    Assert((devHandle <> 0) and (devErr = eNone), 'OpenFile /dev/zero for async ok');
    core.util.memset(uint32(devBuf), $FF, 64);
    devBytesRead := 0;
    devCallbackOk := false;
    ReadFileAsync(devHandle, 0, devBuf, 32, @devBytesRead, nil, nil);
    Assert(devBytesRead = 32, '/dev/zero ReadFileAsync bytesRead = 32');
    Assert(devBuf[0] = 0, '/dev/zero ReadFileAsync byte 0 = 0');
    CloseFile(devHandle);

    { /dev/null appears in /dev listing }
    map := GetDirectoryListingFrom('/dev', '/');
    Assert(map <> nil, 'listing /dev not nil');
    if map <> nil then begin
        obj := PVFSObject(core.ds.hashmap.get(map, 'null'));
        Assert(obj <> nil, 'listing /dev has null entry');
        if obj <> nil then
            Assert(obj^.ObjectType = otDEVICE, '/dev/null entry is otDEVICE');
        obj := PVFSObject(core.ds.hashmap.get(map, 'zero'));
        Assert(obj <> nil, 'listing /dev has zero entry');
        if obj <> nil then
            Assert(obj^.ObjectType = otDEVICE, '/dev/zero entry is otDEVICE');
        FreeDirectoryListing(map);
    end;

    { /dev/null — stream write: accepted, advances offset }
    devHandle := OpenFile('/dev/null', omStream, @devErr);
    Assert((devHandle <> 0) and (devErr = eNone), 'OpenFile /dev/null stream ok');
    core.util.memset(uint32(devBuf), $AA, 64);
    devRead := WriteFile(devHandle, 0, devBuf, 20);
    Assert(devRead = 20, '/dev/null stream write1 = 20');
    devRead := WriteFile(devHandle, 0, devBuf, 12);
    Assert(devRead = 12, '/dev/null stream write2 = 12');
    CloseFile(devHandle);

    { /dev/null — stream write via WriteFileAsync }
    devHandle := OpenFile('/dev/null', omStream, @devErr);
    Assert((devHandle <> 0) and (devErr = eNone), 'OpenFile /dev/null stream async ok');
    WriteFileAsync(devHandle, 0, devBuf, 16, nil, nil);
    CloseFile(devHandle);

    { /dev/zero — stream write: accepted (discards data) }
    devHandle := OpenFile('/dev/zero', omStream, @devErr);
    Assert((devHandle <> 0) and (devErr = eNone), 'OpenFile /dev/zero stream write ok');
    core.util.memset(uint32(devBuf), $BB, 64);
    devRead := WriteFile(devHandle, 0, devBuf, 24);
    Assert(devRead = 24, '/dev/zero stream write = 24');
    CloseFile(devHandle);

    kfree(puint32(devBuf));

    { --- Cleanup: remove all test objects from VFS tree --- }
    RemoveVirtualTree('/utest_vfs');

    PrintSummary;
end;

end.