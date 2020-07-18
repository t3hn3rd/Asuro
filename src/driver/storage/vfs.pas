unit vfs;

interface

uses
    hashmap, strings, lmemorymanager;

type
    TOpenMode       = (omReadOnly, omWriteOnly, omReadWrite);
    TWriteMode      = (wmRewrite, wmAppend, wmNew);
    TError          = (eNone, eUnknown, eFileInUse, eWriteOnly, eReadOnly, eFileDoesNotExist, eDirectoryDoesNotExist, eDirectoryAlreadyExists);
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

    TObjectType = (otVDIRECTORY, otDIRECTORY, otDEVICE, otFILE, otMOUNT);
    TVFSVDirectory = record
        Contents : PHashMap;    
    end;
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
    TVFSFile = record
        ReadFile        : TReadFile;
        WriteFile       : TWriteFile;
    end;
    TVFSMount = record
        Path : pchar;
        ObjectType : TObjectType;
        Reference  : void;
    end;
    TVFSObject = record
        ObjectType : TObjectType;
        Reference  : void;
    end;
    PVFSObject = ^TVFSObject;

var
    VirtualFileSystem : PHashMap;
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

Procedure ChangeCurrentDirectoryValue(new : pchar);
begin
    if CurrentDirectory <> nil then kfree(void(CurrentDirectory));
    CurrentDirectory:= nil;
    CurrentDirectory:= stringCopy(new);
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
begin
    
end;

function getWorkingDirectory : pchar;
begin
    getWorkingDirectory:= CurrentDirectory;
end;

{ Terminal Commands }

{ Init }

procedure init();
begin
    VirtualFileSystem:= hashmap.new;
    ChangeCurrentDirectoryValue('/');
end;

end.