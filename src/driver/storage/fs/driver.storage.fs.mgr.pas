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
    arch.platform.diagnostics,
    arch.platform.cpu,
    core.util;

var
    filesystems : PLinkedListBase;

procedure UnitTest;
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
    if filesystems = nil then
        filesystems := LL_New(sizeof(TFilesystem));
end;

procedure register_filesystem(filesystem : PFilesystem);
var
    entry: void;
begin
    if (filesystems = nil) or (filesystem = nil) then exit;
    entry := LL_Add(filesystems);
    if entry <> nil then
        memcpy(PtrUInt(filesystem), PtrUInt(entry), sizeof(TFilesystem));
end;

function get_filesystem_count() : uint32;
begin
    get_filesystem_count := 0;
    if filesystems <> nil then
        get_filesystem_count := LL_Size(filesystems);
end;

function get_filesystem(index : uint32) : PFilesystem;
begin
    get_filesystem := nil;
    if filesystems <> nil then
        get_filesystem := PFilesystem(LL_Get(filesystems, index));
end;

function find_filesystem_by_name(name : pchar) : PFilesystem;
var
    node: PLinkedList;
    fs: PFilesystem;
begin
    find_filesystem_by_name := nil;
    if (filesystems = nil) or (name = nil) then exit;
    node := filesystems^.Head;
    while node <> nil do begin
        fs := PFilesystem(node^.Data);
        if stringEquals(fs^.sName, name) then begin
            find_filesystem_by_name := fs;
            exit;
        end;
        node := node^.Next;
    end;
end;

function find_filesystem_by_id(system_id : uint8) : PFilesystem;
var
    node: PLinkedList;
    fs: PFilesystem;
begin
    find_filesystem_by_id := nil;
    if filesystems = nil then exit;
    node := filesystems^.Head;
    while node <> nil do begin
        fs := PFilesystem(node^.Data);
        if fs^.system_id = system_id then begin
            find_filesystem_by_id := fs;
            exit;
        end;
        node := node^.Next;
    end;
end;

procedure probe_volume(volume : PStorage_Volume);
var
    node: PLinkedList;
    fs: PFilesystem;
begin
    if (filesystems = nil) or (volume = nil) then exit;
    node := filesystems^.Head;
    while node <> nil do begin
        fs := PFilesystem(node^.Data);
        if fs^.identifyCallback <> nil then begin
            if fs^.identifyCallback(volume) then begin
                volume^.filesystem := fs;
                exit;
            end;
        end;
        node := node^.Next;
    end;
end;

function testIdentify(volume: PStorage_Volume): boolean;
begin
    testIdentify := volume^.sectorCount = 123;
end;

procedure UnitTest;
var
    saved: PLinkedListBase;
    fs: PFilesystem;
    volume: PStorage_Volume;
    flags: PtrUInt;
    beforeFree: SizeUInt;
    passed, failed: uint32;

    procedure Assert(condition: boolean);
    begin
        if condition then
            inc(passed)
        else
            inc(failed);
    end;
begin
    passed := 0;
    failed := 0;
    flags := arch.platform.cpu.lock;
    beforeFree := lmm_total_free;
    saved := filesystems;
    filesystems := nil;
    Assert(get_filesystem_count = 0);
    Assert(find_filesystem_by_name('test') = nil);
    init;
    Assert(find_filesystem_by_id(123) = nil);
    fs := PFilesystem(kalloc(sizeof(TFilesystem)));
    volume := PStorage_Volume(kalloc(sizeof(TStorage_Volume)));
    if (fs <> nil) and (volume <> nil) then begin
        fs^.sName := 'test';
        fs^.system_id := 123;
        fs^.identifyCallback := @testIdentify;
        register_filesystem(fs);
        init;
        Assert(get_filesystem_count = 1);
        Assert((find_filesystem_by_name('test') = get_filesystem(0)) and
            (find_filesystem_by_id(123) = get_filesystem(0)));
        Assert(get_filesystem(1) = nil);
        probe_volume(volume);
        Assert(volume^.filesystem = nil);
        volume^.sectorCount := 123;
        probe_volume(volume);
        Assert((volume^.filesystem <> nil) and (volume^.filesystem <> fs) and
            (volume^.filesystem^.identifyCallback = @testIdentify));
    end else
        inc(failed);
    kfree(void(fs));
    kfree(void(volume));
    if filesystems <> nil then LL_Free(filesystems);
    filesystems := saved;
    Assert(lmm_total_free = beforeFree);
    arch.platform.cpu.unlock(flags);
    testSummary('FSMGR', 'FSMGR_TESTS_PASSED', 'FSMGR_TESTS_FAILED', passed, failed);
end;

end.
