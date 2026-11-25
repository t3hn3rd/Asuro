unit driver.storage.fs.registry;

interface

type
    PRegistryFileChange = ^TRegistryFileChange;
    TRegistryFileChange = record
        Next : PRegistryFileChange;
        Path : PChar;
        Bytes : PUInt8;
        Length : uint32;
    end;

function Mount : Boolean;
function ApplyFileChanges(changes : PRegistryFileChange) : Boolean;

implementation

uses
    core.ds.lists,
    core.strings,
    core.util,
    driver.storage.types,
    driver.storage.vfs,
    memory.heap,
    svc.registry;

type
    POpenKey = ^TOpenKey;
    TOpenKey = record
        Path : PChar;
        Kind : uint8;
        Pending : Boolean;
    end;

var
    registryVolume : TStorage_Volume;
    filesystem : TFilesystem;

function RelativeDirectory(directory : PChar) : PChar;
begin
    if directory = nil then exit('');
    while directory^ = '/' do Inc(directory);
    RelativeDirectory := directory;
end;

function JoinKey(directory, name : PChar) : PChar;
var
    prefix : PChar;
begin
    directory := RelativeDirectory(directory);
    if directory^ = #0 then exit(stringCopy(name));
    prefix := stringConcat(directory, '/');
    JoinKey := stringConcat(prefix, name);
    kfree(void(prefix));
end;

function DecodeKey(directory, filename : PChar; var kind : uint8) : PChar;
var
    candidate : uint8;
    suffix, path : PChar;
begin
    path := JoinKey(directory, filename);
    kind := REGISTRY_BYTES;
    for candidate := REGISTRY_UINT32 to REGISTRY_BOOLEAN do begin
        suffix := svc.registry.TypeSuffix(candidate);
        if stringEndsWith(filename, suffix) then begin
            path[stringSize(path) - stringSize(suffix)] := #0;
            kind := candidate;
            break;
        end;
    end;
    DecodeKey := path;
end;

procedure AddEntry(name : PChar; isDirectory : Boolean; kind : uint8;
                   length : uint32; context : Pointer);
var
    entry : PDirectory_Entry;
begin
    entry := PDirectory_Entry(LL_Add(PLinkedListBase(context)));
    memset(uint32(entry), 0, SizeOf(TDirectory_Entry));
    if isDirectory then begin
        entry^.entryType := directoryEntry;
        entry^.fileName := stringCopy(name);
    end else begin
        entry^.entryType := fileEntry;
        entry^.fileName := stringConcat(name, svc.registry.TypeSuffix(kind));
        entry^.fileSize := length;
    end;
end;

function ReadDirectory(volume : PStorage_Volume; directory : PChar;
                       status : PUInt32) : PLinkedListBase;
var
    entries : PLinkedListBase;
    error : TError;
begin
    entries := LL_New(SizeOf(TDirectory_Entry));
    error := svc.registry.ListKeys(RelativeDirectory(directory), @AddEntry, entries);
    if status <> nil then status^ := Ord(error);
    if error <> eNone then begin
        LL_Free(entries);
        exit(nil);
    end;
    ReadDirectory := entries;
end;

procedure MakeDirectory(volume : PStorage_Volume; directory, name : PChar;
                        attributes : uint32; status : PUInt32);
var
    path : PChar;
    error : TError;
begin
    path := JoinKey(directory, name);
    error := svc.registry.CreateRegistryDirectory(path);
    kfree(void(path));
    if status <> nil then status^ := Ord(error);
end;

function OpenKey(volume : PStorage_Volume; directory, filename : PChar;
                 allowCreate : Boolean; var fileSize : uint32) : Pointer;
var
    path : PChar;
    kind : uint8;
    exists : Boolean;
    handle : POpenKey;
begin
    path := DecodeKey(directory, filename, kind);
    exists := svc.registry.LookupKey(path, kind, fileSize);
    if not exists and (not allowCreate or not svc.registry.CanCreateKey(path)) then begin
        kfree(void(path));
        exit(nil);
    end;
    handle := POpenKey(kalloc(SizeOf(TOpenKey)));
    handle^.Path := path;
    handle^.Kind := kind;
    handle^.Pending := not exists;
    OpenKey := handle;
end;

procedure CloseKey(context : Pointer);
var
    handle : POpenKey;
begin
    handle := POpenKey(context);
    kfree(void(handle^.Path));
    kfree(void(handle));
end;

function KeySize(volume : PStorage_Volume; directory, filename : PChar) : uint32;
var
    path : PChar;
    kind : uint8;
    length : uint32;
begin
    path := DecodeKey(directory, filename, kind);
    svc.registry.LookupKey(path, kind, length);
    kfree(void(path));
    KeySize := length;
end;

function ReadKey(volume : PStorage_Volume; directory, filename : PChar;
                 offset : uint32; buffer : PUInt32; length : uint32;
                 context : Pointer) : uint32;
var
    handle : POpenKey;
    path : PChar;
    kind : uint8;
begin
    handle := POpenKey(context);
    if handle <> nil then begin
        if handle^.Pending then exit(0);
        exit(svc.registry.ReadKey(handle^.Path, handle^.Kind, offset, PUInt8(buffer), length));
    end;
    path := DecodeKey(directory, filename, kind);
    ReadKey := svc.registry.ReadKey(path, kind, offset, PUInt8(buffer), length);
    kfree(void(path));
end;

function WriteKey(volume : PStorage_Volume; directory, filename : PChar;
                  offset : uint32; buffer : PUInt32; length : uint32;
                  context : Pointer) : uint32;
var
    handle : POpenKey;
begin
    WriteKey := 0;
    handle := POpenKey(context);
    if (handle = nil) or (offset <> 0) then exit;
    if handle^.Pending then begin
        if svc.registry.CreateKey(handle^.Path, handle^.Kind, PUInt8(buffer), length) then begin
            handle^.Pending := false;
            WriteKey := length;
        end;
    end else
        WriteKey := svc.registry.ReplaceKey(handle^.Path, handle^.Kind, PUInt8(buffer), length);
end;

function ApplyFileChanges(changes : PRegistryFileChange) : Boolean;
var
    keys, key : PRegistryChange;
begin
    keys := nil;
    while (changes <> nil) and stringStartsWith(changes^.Path, '/cfg/') do begin
        key := PRegistryChange(kalloc(SizeOf(TRegistryChange)));
        key^.Path := DecodeKey(nil, @changes^.Path[5], key^.Kind);
        key^.Bytes := changes^.Bytes;
        key^.Length := changes^.Length;
        key^.Next := keys;
        keys := key;
        changes := changes^.Next;
    end;
    ApplyFileChanges := (changes = nil) and svc.registry.ApplyChanges(keys);
    while keys <> nil do begin
        key := keys;
        keys := keys^.Next;
        kfree(void(key^.Path));
        kfree(void(key));
    end;
end;

function Mount : Boolean;
begin
    filesystem.sName := 'registry';
    filesystem.readDirCallback := @ReadDirectory;
    filesystem.createDirCallback := @MakeDirectory;
    filesystem.openFileModeCallback := @OpenKey;
    filesystem.closeFileCallback := @CloseKey;
    filesystem.fileSizeCallback := @KeySize;
    filesystem.readOffsetCallback := @ReadKey;
    filesystem.writeOffsetCallback := @WriteKey;
    registryVolume.filesystem := @filesystem;
    registryVolume.lifecycleFlags := STORAGE_VOLUME_FLAG_DEVICELESS;
    Mount := mountVolume('/cfg', @registryVolume) = pvRegistered;
end;

end.
