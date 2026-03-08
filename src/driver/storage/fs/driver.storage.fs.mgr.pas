{
    Driver->Storage->FilesystemManager - Filesystem driver registry and routing.

    Filesystem drivers (FAT32, FlatFS, etc.) register themselves here.
    When VolumeManager discovers a volume, FilesystemManager probes it
    against all registered filesystem drivers to detect the filesystem type.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit driver.storage.fs.mgr;

interface

uses
    core.ds.lists,
    memory.heap,
    driver.storage.types,
    core.strings,
    debug.tracer,
    core.util, arch.x86.util;

var
    filesystems : PLinkedListBase;

procedure init();
procedure register_filesystem(filesystem : PFilesystem);
function get_filesystem_count() : uint32;
function get_filesystem(index : uint32) : PFilesystem;
function find_filesystem_by_name(name : pchar) : PFilesystem;
function find_filesystem_by_id(system_id : uint8) : PFilesystem;
procedure probe_volume(volume : PStorage_Volume);

implementation

procedure init();
begin
    push_trace('driver.storage.fs.mgr.init');
    filesystems := LL_New(sizeof(TFilesystem));
end;

procedure register_filesystem(filesystem : PFilesystem);
var
    elm : void;
begin
    push_trace('driver.storage.fs.mgr.register_filesystem');

    elm := LL_Add(filesystems);
    memcpy(uint32(filesystem), uint32(elm), sizeof(TFilesystem));
end;

function get_filesystem_count() : uint32;
begin
    get_filesystem_count := LL_Size(filesystems);
end;

function get_filesystem(index : uint32) : PFilesystem;
begin
    if index < LL_Size(filesystems) then
        get_filesystem := PFilesystem(LL_Get(filesystems, index))
    else
        get_filesystem := nil;
end;

function find_filesystem_by_name(name : pchar) : PFilesystem;
var
    i  : uint32;
    fs : PFilesystem;
begin
    push_trace('driver.storage.fs.mgr.find_filesystem_by_name');
    find_filesystem_by_name := nil;

    for i := 0 to LL_Size(filesystems) - 1 do begin
        fs := PFilesystem(LL_Get(filesystems, i));
        if stringEquals(fs^.sName, name) then begin
            find_filesystem_by_name := fs;
            exit;
        end;
    end;
end;

function find_filesystem_by_id(system_id : uint8) : PFilesystem;
var
    i  : uint32;
    fs : PFilesystem;
begin
    push_trace('driver.storage.fs.mgr.find_filesystem_by_id');
    find_filesystem_by_id := nil;

    for i := 0 to LL_Size(filesystems) - 1 do begin
        fs := PFilesystem(LL_Get(filesystems, i));
        if fs^.system_id = system_id then begin
            find_filesystem_by_id := fs;
            exit;
        end;
    end;
end;

procedure probe_volume(volume : PStorage_Volume);
var
    i  : uint32;
    fs : PFilesystem;
begin
    push_trace('driver.storage.fs.mgr.probe_volume.enter');

    { Try each registered filesystem's identify callback against this volume }
    for i := 0 to LL_Size(filesystems) - 1 do begin
        fs := PFilesystem(LL_Get(filesystems, i));
        if fs^.identifyCallback <> nil then begin
            push_trace('driver.storage.fs.mgr.probe_volume.tryFS');
            if fs^.identifyCallback(volume) then begin
                volume^.filesystem := fs;
                push_trace('driver.storage.fs.mgr.probe_volume.found');
                exit;
            end;
        end;
    end;
    push_trace('driver.storage.fs.mgr.probe_volume.exit');
end;

end.
