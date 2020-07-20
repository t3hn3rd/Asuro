unit vfs;

interface

uses
    hashmap, strings, lmemorymanager, lists, tracer, console;

type
    TOpenMode       = (omReadOnly, omWriteOnly, omReadWrite);
    TWriteMode      = (wmRewrite, wmAppend, wmNew);
    TError          = (eNone, eUnknown, eFileInUse, eWriteOnly, eReadOnly, eFileDoesNotExist, eDirectoryDoesNotExist, eDirectoryAlreadyExists, eNotADirectory);
    PError          = ^TError;
    TIsPathValid    = (pvInvalid, pvFile, pvDirectory);

    TFileHandle = uint32;

    { Callbacks }
    TOpenFile       = function(Handle : uint32; Filename : pchar; OpenMode : TOpenMode; WriteMode : TWriteMode; Lock : Boolean; Error : PError) : TFileHandle;
    TWriteFile      = function(Handle : uint32; FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
    TReadFile       = function(Handle : uint32; FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
    TFileSize       = function(Handle : uint32; Filename : pchar; error : puint8) : uint32;
    TCloseFile      = function(Handle : uint32; Filehandle : TFileHandle) : boolean;
    TMakeDirectory  = function(Handle : uint32; Path : pchar) : TError;
    TGetDirectories = function(Handle : uint32; Path : pchar) : PHashMap;
    TPathValid      = function(Handle : uint32; Path : pchar) : TIsPathValid;

    TObjectType = (otVDIRECTORY, otDRIVE, otDEVICE, otVFILE, otMOUNT, otDIRECTORY, otFILE);
    TVFSDrive = record
        DriveHandle     : uint32;
        MakeDirectory   : TMakeDirectory;
        GetDirectories  : TGetDirectories;
        OpenFile        : TOpenFile;
        CloseFile       : TCloseFile;
        ReadFile        : TReadFile;
        WriteFile       : TWriteFile;
        FileSize        : TFileSize;
        PathValid       : TPathValid;
    end;
    PVFSDrive = ^TVFSDrive;
    TVFSDevice = record
        DeviceHandle    : uint32;
        MakeDirectory   : TMakeDirectory;
        GetDirectories  : TGetDirectories;
        OpenFile        : TOpenFile;
        CloseFile       : TCloseFile;
        ReadFile        : TReadFile;
        WriteFile       : TWriteFile;
        FileSize        : TFileSize;
        PathValid       : TPathValid;
    end;
    PVFSDevice = ^TVFSDevice;
    TVFSFile = record
        ReadFile        : TReadFile;
        WriteFile       : TWriteFile;
    end;
    PVFSFile = ^TVFSFile;
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

procedure init();
Function OpenFile(Filename : pchar; OpenMode : TOpenMode; WriteMode : TWriteMode; Lock : Boolean; Error : PError) : TFileHandle;
function WriteFile(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
function ReadFile(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
function CloseFile(Filehandle : TFileHandle) : boolean;
function FileSize(Filename : pchar; error : puint8) : uint32;
function CreateDirectory(Handle : uint32; Path : pchar) : TError;
function GetDirectories(Handle : uint32; Path : pchar) : PHashMap;
function PathValid(Handle : uint32; Path : pchar) : TPathValid;
function changeDirectory(Path : pchar) : TPathValid;
function getWorkingDirectory : pchar;

//VFS Functions
function newVirtualDirectory(Path : pchar) : TError;

implementation

uses
    terminal;

{ Internal Functions }

function makeRelative(Path : pchar; From : pchar) : pchar;
var
    Result : pchar;
    Tmp    : pchar;

begin
    tracer.push_trace('vfs.makeRelative.enter');
    Result:= nil;
    if StringEquals(Path, From) then begin
        Result:= stringCopy('/');
    end else begin
        if StringContains(Path, From) then begin
            if (Path[0] = From[0]) and (Path[StringSize(From)-1] = From[StringSize(From)-1]) then begin
                Tmp:= Path;
                inc(tmp, StringSize(From));
                Result:= stringCopy(tmp);
            end;
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
    createVirtualDirectory^.Reference:= void(hashmap.new());
    tracer.push_trace('vfs.createVirtualDirectory.exit');
end;

function CombineToAbsolutePath(List : PLinkedListBase; Count : uint32) : pchar;
var
    new, old : pchar;
    i : uint32;

begin
    tracer.push_trace('vfs.CombineToAbsolutePath.enter');
    CombineToAbsolutePath:= nil;
    if STRLL_Size(List) < (Count-1) then begin
        tracer.push_trace('vfs.CombineToAbsolutePath.shortexit');
        exit;
    end;
    new:= stringCopy('/');
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

function getAbsolutePath(Obj : PVFSObject) : pchar;
var
    buf, new, delim : pchar;
    iter : PVFSObject;

begin
    tracer.push_trace('vfs.getAbsolutePath.enter');

    delim:= stringCopy('/');
    buf:= nil;

    iter:= Obj;
    if iter <> nil then begin
        if iter^.Parent = nil then buf:= stringCopy(iter^.ObjectName);
        while iter^.Parent <> nil do begin
            new:= StringConcat('/', iter^.ObjectName);
            if buf = nil then
                buf:= stringCopy(new)
            else
                buf:= StringConcat(new, buf);
            kfree(void(new));
            iter:= iter^.Parent;
        end;
    end;
    
    kfree(void(delim));
    getAbsolutePath:= buf;

    tracer.push_trace('vfs.getAbsolutePath.exit');
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
            ht:= PHashMap(Obj^.Reference);
            item:= STRLL_Get(SplitPath, i);                                                         
            NewObj:= PVFSObject(hashmap.get(ht, item));                                            
            if NewObj = nil then begin                                                              
                GetObjectFromPath:= nil;
                tracer.push_trace('vfs.GetObjectFromPath.shortexit');
                exit;
            end;                                                                                    
            Case NewObj^.ObjectType of
                otVDIRECTORY,otMOUNT:begin                                                          
                    Obj:= NewObj;
                end;
                else begin                                                                         
                    Obj:= NewObj;
                    tracer.push_trace('vfs.GetObjectFromPath.shortexit');
                    Break;
                end;
            end;
        end;
    end;                                                                                           
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
                GetDirectoryListing:= PVFSDrive(Obj^.Reference)^.GetDirectories(PVFSDrive(Obj^.Reference)^.DriveHandle, RelPath); //Fix this to be relative path!!!
                kfree(void(ObjPath));
                kfree(void(RelPath));
            end; 
            otDEVICE:begin
                ObjPath:= getAbsolutePath(Obj);
                RelPath:= makeRelative(Path, ObjPath);
                GetDirectoryListing:= PVFSDevice(Obj^.Reference)^.GetDirectories(PVFSDevice(Obj^.Reference)^.DeviceHandle, RelPath); //Fix this to be the relative path
                kfree(void(ObjPath));
                kfree(void(RelPath));
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

{ Filesystem Functions }

Function OpenFile(Filename : pchar; OpenMode : TOpenMode; WriteMode : TWriteMode; Lock : Boolean; Error : PError) : TFileHandle;
begin

end;

function WriteFile(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
begin

end;

function ReadFile(FileHandle : TFileHandle; Position : uint32; Buffer : puint8; Length : uint32) : uint32;
begin

end;

function CloseFile(Filehandle : TFileHandle) : boolean;
begin

end;

function FileSize(Filename : pchar; error : puint8) : uint32;
begin

end;

function CreateDirectory(Handle : uint32; Path : pchar) : TError;
begin

end;

function GetDirectories(Handle : uint32; Path : pchar) : PHashMap;
begin

end;

function PathValid(Handle : uint32; Path : pchar) : TPathValid;
begin

end;

function changeDirectory(Path : pchar) : TPathValid;
begin

end;

{ VFS Functions }

function newVirtualDirectory(Path : pchar) : TError;
var
    AbsPath               : pchar;   
    SplitPath             : PLinkedListBase;
    SplitParentPath       : PLinkedListBase;
    ParentDirectoryPath   : pchar;
    ObjectName            : pchar;
    Obj                   : PVFSObject;
    Map                   : PHashMap;
    Entry                 : PVFSObject;
    Key                   : pchar;
    

begin
    tracer.push_trace('vfs.newVirtualDirectory.enter');
    newVirtualDirectory:= eUnknown;
    if Path[0] = '/' then AbsPath:= stringCopy(Path) else begin
        AbsPath:= StringConcat(CurrentDirectory, Path);
    end;
    SplitPath:= STRLL_FromString(AbsPath, '/');
    ObjectName:= STRLL_Get(SplitPath, STRLL_Size(SplitPath)-1);
    ParentDirectoryPath:= CombineToAbsolutePath(SplitPath, STRLL_Size(SplitPath)-1);
    SplitParentPath:= STRLL_FromString(ParentDirectoryPath, '/');
    Obj:= GetObjectFromPath(ParentDirectoryPath);
    if Obj = nil then begin
        newVirtualDirectory:= eDirectoryDoesNotExist;
    end else begin
        Case Obj^.ObjectType of
            otDRIVE, otDEVICE, otVFILE:begin
                newVirtualDirectory:= eNotADirectory;
                tracer.push_trace('vfs.newVirtualDirectory.shortexit');
                exit;
            end;
        end;
        Map:= PHashMap(Obj^.Reference);
        Key:= STRLL_Get(SplitPath, STRLL_Size(SplitPath)-1);
        Entry:= PVFSObject(hashmap.get(Map, Key));
        If Entry = nil then begin
            Entry:= createVirtualDirectory();
            Entry^.ObjectName:= stringCopy(ObjectName);
            Entry^.Parent:= Obj;
            hashmap.add(Map, Key, void(Entry));
        end else begin
            newVirtualDirectory:= eDirectoryAlreadyExists;
        end;
    end;
    tracer.push_trace('vfs.newVirtualDirectory.exit');
end;

function getWorkingDirectory : pchar;
begin
    getWorkingDirectory:= CurrentDirectory;
end;

{ Terminal Commands }

procedure VFS_COMMAND_LS(params : PParamList);
var
    Map  : PHashMap;
    Item : PHashItem;
    obj  : PVFSObject;
    i    : uint32;
    col  : uint32;

begin
    tracer.push_trace('vfs.VFS_COMMAND_LS.enter');
    Map:= GetDirectoryListing(CurrentDirectory);
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
    end else begin
        writestringlnWND('An internal error occured!', getTerminalHWND);
    end;
    tracer.push_trace('vfs.VFS_COMMAND_LS.exit');
end;

procedure VFS_COMMAND_CD(params : PParamList);
var
    obj : PVFSObject;

begin
    tracer.push_trace('vfs.VFS_COMMAND_CD.enter');
    obj:= GetObjectFromPath('/disk/test/myfolder');
    if obj <> nil then writestringlnWND(getAbsolutePath(obj),getTerminalHWND);
    tracer.push_trace('vfs.VFS_COMMAND_CD.exit');
end;

{ Init }

procedure init();
var
    ht : PHashMap;
    obj : PVFSObject;
    rel : pchar;

begin
    tracer.push_trace('vfs.init.enter');

    Root:= createVirtualDirectory();
    Root^.Parent:= nil;
    Root^.ObjectName:= stringCopy('/');

    ChangeCurrentDirectoryValue('/');

    newVirtualDirectory('/dev');
    newVirtualDirectory('/home');
    newVirtualDirectory('/disk');
    // newVirtualDirectory('/disk/test');
    // newVirtualDirectory('/disk/test/myfolder');

    // rel:= makeRelative('/disk/SDA/mydirectory/myfile', '/disk/SDA');
    // if rel <> nil then outputln('VFS', rel) else outputln('VFS', 'REL IS NULL!');

    // while true do begin end;

    terminal.registerCommand('LS', @VFS_COMMAND_LS, 'List directory contents.');
    terminal.registerCommand('CD', @VFS_COMMAND_CD, 'Set working directory');

    {ht:= PHashMap(Root^.Reference);
    hashmap.add(ht, 'VDirectory', void(newDummyObject(otVDIRECTORY)));
    hashmap.add(ht, 'Drive', void(newDummyObject(otDRIVE)));
    hashmap.add(ht, 'Device', void(newDummyObject(otDEVICE)));
    hashmap.add(ht, 'VFile', void(newDummyObject(otVFILE)));
    hashmap.add(ht, 'Mount', void(newDummyObject(otMOUNT)));
    hashmap.add(ht, 'Directory', void(newDummyObject(otDIRECTORY)));
    hashmap.add(ht, 'File', void(newDummyObject(otFILE)));}
    //otVDIRECTORY, otDRIVE, otDEVICE, otVFILE, otMOUNT, otDIRECTORY, otFILE)
    tracer.push_trace('vfs.init.exit');
end;

end.