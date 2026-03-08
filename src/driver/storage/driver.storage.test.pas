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
    Driver->Storage->StorageTest - Unit tests for the storage subsystem.

    Tests the VFS path operations, directory management, and mount logic
    that are safe to run at boot time (no actual disk I/O required).
    Also registers a STORTEST shell command so tests can be re-run at
    runtime after volumes are mounted (exercises disk-backed paths).

    Pattern: same Assert + PrintSummary approach as driver.storage.vfs.UnitTest.
    Output goes to io.syslog ('STORTEST' tag) from UnitTest, and to
    stdout_buf from the STORTEST command.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit driver.storage.test;

interface

procedure UnitTest;
procedure init;

implementation

uses
    core.ds.hashmap,
    memory.heap,
    driver.storage.vol.mbr,
    io.stdio,
    driver.storage.mgr,
    driver.storage.types,
    core.strings,
    io.syslog,
    debug.tracer,
    core.util, arch.x86.util,
    driver.storage.vfs,
    driver.storage.vol.mgr;

{ ============================================================
  run_tests — shared test body called by both UnitTest (boot)
  and the STORTEST shell command (runtime).

  passed / failed are in/out accumulator params so the caller
  can print a combined summary.
  ============================================================ }
procedure run_tests(var passed, failed: uint32; to_log: boolean;
                    stdout_buf: POutBuf);

    { Write a line either to io.syslog or to the terminal stdout buffer }
    procedure emit(tag, msg: pchar);
    var
        line: pchar;
    begin
        if to_log then begin
            io.syslog.logln(tag, msg);
        end else begin
            if stdout_buf <> nil then begin
                line := stringConcat('[', tag);
                io.stdio.bufWriteStr(stdout_buf, line);
                kfree(void(line));
                io.stdio.bufWriteStr(stdout_buf, '] ');
                io.stdio.bufWriteStrLn(stdout_buf, msg);
            end;
        end;
    end;

    procedure Assert(condition: boolean; testName: pchar);
    var
        msg: pchar;
    begin
        if condition then begin
            inc(passed);
        end else begin
            inc(failed);
            msg := stringConcat('FAIL: ', testName);
            emit('STORTEST', msg);
            kfree(void(msg));
        end;
    end;

var
    p      : pchar;
    p2     : pchar;
    newDir : pchar;
    map    : PHashMap;
    errCode: driver.storage.types.TError;
    res    : TIsPathValid;

begin
    debug.tracer.push_trace('driver.storage.test.run_tests');

    { ---- makeAbsolutePathFrom ---- }
    { Absolute path should be returned unchanged }
    p := driver.storage.vfs.MakeAbsolutePathFrom('/foo/bar', '/base');
    Assert(stringEquals(p, '/foo/bar'), 'MakeAbsolutePathFrom: abs passthrough');
    kfree(void(p));

    { Relative path joined to base (base has trailing slash) }
    p := driver.storage.vfs.MakeAbsolutePathFrom('file.txt', '/home/');
    Assert(stringEquals(p, '/home/file.txt'), 'MakeAbsolutePathFrom: rel+base trailing /');
    kfree(void(p));

    { Relative path joined to base (base has no trailing slash) }
    p := driver.storage.vfs.MakeAbsolutePathFrom('file.txt', '/home');
    Assert(stringEquals(p, '/home/file.txt'), 'MakeAbsolutePathFrom: rel+base no trailing /');
    kfree(void(p));

    { ---- resolvePathFrom ---- }
    { Known virtual dirs resolve to pvDirectory }
    res := driver.storage.vfs.ResolvePathFrom('disk', '/');
    Assert(res = pvDirectory, 'ResolvePathFrom: /disk from /');

    res := driver.storage.vfs.ResolvePathFrom('dev', '/');
    Assert(res = pvDirectory, 'ResolvePathFrom: /dev from /');

    res := driver.storage.vfs.ResolvePathFrom('mnt', '/');
    Assert(res = pvDirectory, 'ResolvePathFrom: /mnt from /');

    { Non-existent names resolve to pvInvalid }
    res := driver.storage.vfs.ResolvePathFrom('zzznope', '/');
    Assert(res = pvInvalid, 'ResolvePathFrom: nonexistent from /');

    { ---- changeDirectoryFrom ---- }
    newDir := nil;
    res := driver.storage.vfs.ChangeDirectoryFrom('disk', '/', newDir);
    Assert(res = pvDirectory, 'ChangeDirectoryFrom /disk: returns dir');
    Assert((newDir <> nil) and stringEquals(newDir, '/disk'),
           'ChangeDirectoryFrom /disk: newDir = /disk');
    if newDir <> nil then kfree(void(newDir));

    newDir := nil;
    res := driver.storage.vfs.ChangeDirectoryFrom('zzznope', '/', newDir);
    Assert(res = pvInvalid, 'ChangeDirectoryFrom nonexistent: returns invalid');
    Assert(newDir = nil, 'ChangeDirectoryFrom nonexistent: newDir nil');

    { ---- GetDirectoryListingFrom ---- }
    { Root listing should be non-nil (in-memory VFS always populated) }
    map := driver.storage.vfs.GetDirectoryListingFrom('/', '/');
    Assert(map <> nil, 'GetDirectoryListingFrom(/) not nil');
    driver.storage.vfs.FreeDirectoryListing(map);

    { /disk, /dev, /mnt created at init — must appear in root listing }
    map := driver.storage.vfs.GetDirectoryListingFrom('/', '/');
    Assert(map <> nil, 'GetDirectoryListingFrom(/) not nil (2)');
    { All maps are now caller-owned snapshots — always safe to free }
    driver.storage.vfs.FreeDirectoryListing(map);

    { Listing a leaf vdir returns non-nil (even if empty) }
    map := driver.storage.vfs.GetDirectoryListingFrom('/dev', '/');
    Assert(map <> nil, 'GetDirectoryListingFrom(/dev) not nil');
    driver.storage.vfs.FreeDirectoryListing(map);

    { Non-existent path returns nil (no crash) }
    map := driver.storage.vfs.GetDirectoryListingFrom('/zzznope', '/');
    Assert(map = nil, 'GetDirectoryListingFrom(nonexistent) = nil');

    { ---- newVirtualDirectory edge cases ---- }
    { Create a fresh nested path }
    errCode := driver.storage.vfs.newVirtualDirectory('/st_test/nested');
    { Parent /st_test didn't exist — expect eDirectoryDoesNotExist }
    Assert(errCode = eDirectoryDoesNotExist,
           'newVirtualDirectory: missing parent = eDirDoesNotExist');

    { Create /st_test first, then child }
    errCode := driver.storage.vfs.newVirtualDirectory('/st_test');
    Assert(errCode = eNone, 'newVirtualDirectory /st_test = eNone');

    errCode := driver.storage.vfs.newVirtualDirectory('/st_test/nested');
    Assert(errCode = eNone, 'newVirtualDirectory /st_test/nested = eNone');

    { Attempting to create it again should give eDirectoryAlreadyExists }
    errCode := driver.storage.vfs.newVirtualDirectory('/st_test/nested');
    Assert(errCode = eDirectoryAlreadyExists,
           'newVirtualDirectory duplicate = eDirectoryAlreadyExists');

    { Verify the new dir is visible via PathValid }
    Assert(driver.storage.vfs.PathValid('/st_test')        = pvDirectory, 'PathValid /st_test');
    Assert(driver.storage.vfs.PathValid('/st_test/nested') = pvDirectory, 'PathValid /st_test/nested');

    { Verify resolvePathFrom sees the new dirs }
    res := driver.storage.vfs.resolvePathFrom('st_test', '/');
    Assert(res = pvDirectory, 'resolvePathFrom st_test after create');

    res := driver.storage.vfs.resolvePathFrom('nested', '/st_test');
    Assert(res = pvDirectory, 'resolvePathFrom nested in st_test');

    { ---- PathValid with dotdot traversal ---- }
    { /st_test/nested/.. should collapse back to /st_test }
    Assert(driver.storage.vfs.PathValid('/st_test/nested/../') = pvDirectory,
           'PathValid with .. collapse');

    { . traversal stays in same dir }
    Assert(driver.storage.vfs.PathValid('/st_test/./') = pvDirectory,
           'PathValid with . stays put');

    { ---- Symlink traversal through resolvePathFrom / ChangeDirectoryFrom ---- }
    { Create /st_test/inner, then symlink /st_test/slink -> /st_test/inner }
    errCode := driver.storage.vfs.newVirtualDirectory('/st_test/inner');
    Assert(errCode = eNone, 'newVDir /st_test/inner = eNone');

    errCode := driver.storage.vfs.newVirtualDirectory('/st_test/inner/deep');
    Assert(errCode = eNone, 'newVDir /st_test/inner/deep = eNone');

    errCode := driver.storage.vfs.CreateSymlink('/st_test/slink', '/st_test/inner');
    Assert(errCode = eNone, 'CreateSymlink slink -> inner = eNone');

    { resolvePathFrom through symlink }
    res := driver.storage.vfs.ResolvePathFrom('slink', '/st_test');
    Assert(res = pvDirectory, 'ResolvePathFrom: slink from /st_test = dir');

    { resolvePathFrom through symlink + subdir }
    res := driver.storage.vfs.ResolvePathFrom('/st_test/slink/deep', '/');
    Assert(res = pvDirectory, 'ResolvePathFrom: slink/deep = dir');

    { ChangeDirectoryFrom through symlink }
    newDir := nil;
    res := driver.storage.vfs.ChangeDirectoryFrom('slink', '/st_test', newDir);
    Assert(res = pvDirectory, 'ChangeDirFrom slink: returns dir');
    if newDir <> nil then kfree(void(newDir));

    { GetDirectoryListingFrom through symlink }
    map := driver.storage.vfs.GetDirectoryListingFrom('/st_test/slink', '/');
    Assert(map <> nil, 'GetDirListingFrom through slink not nil');
    if map <> nil then
        driver.storage.vfs.FreeDirectoryListing(map);

    { GetDirectoryListingFrom deeper through symlink }
    map := driver.storage.vfs.GetDirectoryListingFrom('/st_test/slink/deep', '/');
    Assert(map <> nil, 'GetDirListingFrom slink/deep not nil');
    if map <> nil then
        driver.storage.vfs.FreeDirectoryListing(map);

    { Nonexistent child after symlink }
    res := driver.storage.vfs.ResolvePathFrom('/st_test/slink/nope', '/');
    Assert(res = pvInvalid, 'ResolvePathFrom slink/nope = invalid');

    { --- Cleanup: remove all test objects from VFS tree --- }
    driver.storage.vfs.RemoveVirtualTree('/st_test');

    debug.tracer.pop_trace;
end;

{ ============================================================
  run_disk_tests — destructive, requires a writable disk 0.
  Wipes disk 0, creates a 4 MB FAT32 partition, writes a file,
  reads it back and verifies the data matches.
  Only called from cmd_disktest (never from UnitTest at boot).
  ============================================================ }
procedure run_disk_tests(var passed, failed : uint32; to_log : boolean;
                         stdout_buf : POutBuf);

    procedure emit(tag, msg : pchar);
    var
        line : pchar;
    begin
        if to_log then begin
            io.syslog.logln(tag, msg);
        end else begin
            if stdout_buf <> nil then begin
                line := stringConcat('[', tag);
                io.stdio.bufWriteStr(stdout_buf, line);
                kfree(void(line));
                io.stdio.bufWriteStr(stdout_buf, '] ');
                io.stdio.bufWriteStrLn(stdout_buf, msg);
            end;
        end;
    end;

    procedure Assert(condition : boolean; testName : pchar);
    var
        msg : pchar;
    begin
        if condition then begin
            inc(passed);
        end else begin
            inc(failed);
            msg := stringConcat('FAIL: ', testName);
            emit('DISKTEST', msg);
            kfree(void(msg));
        end;
    end;

var
    disk   : PStorage_Device;
    part   : TPartition_table;
    volIdx : uint32;
    vol    : PStorage_Volume;
    wbuf   : puint8;
    rbuf   : puint8;
    fh     : TFileHandle;
    err    : TError;
    n      : uint32;
    i      : uint32;
    ok     : boolean;
begin
    debug.tracer.push_trace('driver.storage.test.run_disk_tests');

    { ---- Get disk 0 ---- }
    disk := driver.storage.mgr.get_device(0);
    if disk = nil then begin
        emit('DISKTEST', 'No disk 0 found — skipping disk tests');
        debug.tracer.pop_trace;
        exit;
    end;
    if not disk^.writable then begin
        emit('DISKTEST', 'Disk 0 not writable — skipping disk tests');
        debug.tracer.pop_trace;
        exit;
    end;

    { ---- Wipe disk 0 ---- }
    driver.storage.vol.mgr.init_disk(disk);
    emit('DISKTEST', 'Disk 0 wiped.');

    { ---- Create 4 MB mbr partition at LBA 2048 ---- }
    memset(uint32(@part), 0, sizeof(TPartition_table));
    part.system_id := $0B;  { FAT32 < 2GB }
    driver.storage.vol.mbr.setup_partition(@part, 2048, 8192);  { LBA_start=2048, sector_count=8192 }
    driver.storage.vol.mgr.add_partition(disk, 0, part);
    Assert(driver.storage.vol.mgr.get_volume_count() > 0, 'add_partition: volume count > 0');

    { ---- Format as FAT32 ---- }
    volIdx := driver.storage.vol.mgr.get_volume_count() - 1;
    Assert(driver.storage.vol.mgr.format_volume(disk, volIdx, 'FAT32', nil),
           'format_volume FAT32 = true');

    { ---- Mount at /disk/dt_vol ---- }
    vol := driver.storage.vol.mgr.get_volume(volIdx);
    Assert(vol <> nil, 'get_volume not nil');
    if vol = nil then begin debug.tracer.pop_trace; exit; end;
    Assert(driver.storage.vfs.mountVolume('/disk/dt_vol', vol) = pvRegistered,
           'mountVolume = pvRegistered');

    { ---- Write 512 bytes of 0xA5 to TEST.TXT ---- }
    wbuf := puint8(kalloc(512));
    for i := 0 to 511 do
        wbuf[i] := $A5;
    err := eNone;
    fh := driver.storage.vfs.OpenFile('/disk/dt_vol/TEST.TXT', omCreate, @err);
    Assert(err = eNone, 'OpenFile for write: err = eNone');
    n := driver.storage.vfs.WriteFile(fh, 0, wbuf, 512);
    Assert(n = 512, 'WriteFile 512 bytes');
    driver.storage.vfs.CloseFile(fh);

    { ---- Read back ---- }
    rbuf := puint8(kalloc(512));
    memset(uint32(rbuf), 0, 512);
    err := eNone;
    fh := driver.storage.vfs.OpenFile('/disk/dt_vol/TEST.TXT', omRead, @err);
    Assert(err = eNone, 'OpenFile for read: err = eNone');
    n := driver.storage.vfs.ReadFile(fh, 0, rbuf, 512);
    Assert(n = 512, 'ReadFile 512 bytes');
    driver.storage.vfs.CloseFile(fh);

    { ---- Verify data ---- }
    ok := true;
    for i := 0 to 511 do
        if rbuf[i] <> wbuf[i] then begin
            ok := false;
            break;
        end;
    Assert(ok, 'read-back data matches written data');

    kfree(void(wbuf));
    kfree(void(rbuf));

    debug.tracer.pop_trace;
end;

{ ============================================================
  UnitTest — called by kernel.pas at boot (no disk available)
  ============================================================ }
procedure UnitTest;
var
    passed, failed : uint32;
    pStr, fStr, msg, tmp : pchar;
begin
    passed := 0;
    failed := 0;
    io.syslog.logln('STORTEST', 'Unit tests starting...');

    run_tests(passed, failed, true, nil);

    pStr := intToString(passed);
    fStr := intToString(failed);
    msg  := stringConcat(pStr, ' passed, ');
    tmp  := stringConcat(msg, fStr);
    kfree(void(msg));
    msg  := stringConcat(tmp, ' failed.');
    kfree(void(tmp));
    io.syslog.logln('STORTEST', msg);
    kfree(void(msg));
    kfree(void(pStr));
    kfree(void(fStr));
end;

{ ============================================================
  STORTEST command — re-run all tests from the shell.
  When volumes are mounted this also exercises disk-backed
  directory listings (e.g. /disk/vol0).
  ============================================================ }
procedure cmd_stortest(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    passed, failed : uint32;
    pStr, fStr, msg, tmp : pchar;
    map : PHashMap;
begin
    passed := 0;
    failed := 0;
    io.stdio.bufWriteStrLn(stdout_buf, '--- Storage subsystem tests ---');

    run_tests(passed, failed, false, stdout_buf);

    { Runtime-only: test /disk listing (populated only after auto_mount_volumes) }
    map := driver.storage.vfs.GetDirectoryListingFrom('/disk', '/');
    if map <> nil then begin
        io.stdio.bufWriteStrLn(stdout_buf, '[+] /disk listing available (volumes mounted)');
        driver.storage.vfs.FreeDirectoryListing(map);
    end else
        io.stdio.bufWriteStrLn(stdout_buf, '[-] /disk listing nil (no volumes mounted)');

    pStr := intToString(passed);
    fStr := intToString(failed);
    msg  := stringConcat(pStr, ' passed, ');
    tmp  := stringConcat(msg, fStr);
    kfree(void(msg));
    msg  := stringConcat(tmp, ' failed.');
    kfree(void(tmp));
    io.stdio.bufWriteStrLn(stdout_buf, msg);
    kfree(void(msg));
    kfree(void(pStr));
    kfree(void(fStr));
end;

{ ============================================================
  cmd_disktest — DESTRUCTIVE: wipes disk 0, creates a 4 MB FAT32
  partition, writes TEST.TXT, reads back and verifies.
  ============================================================ }
procedure cmd_disktest(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    passed, failed : uint32;
    pStr, fStr, msg, tmp : pchar;
begin
    passed := 0;
    failed := 0;
    io.stdio.bufWriteStrLn(stdout_buf, '--- DISKTEST: DESTRUCTIVE disk 0 I/O test ---');
    io.stdio.bufWriteStrLn(stdout_buf, 'WARNING: This will wipe disk 0!');

    run_disk_tests(passed, failed, false, stdout_buf);

    pStr := intToString(passed);
    fStr := intToString(failed);
    msg  := stringConcat(pStr, ' passed, ');
    tmp  := stringConcat(msg, fStr);
    kfree(void(msg));
    msg  := stringConcat(tmp, ' failed.');
    kfree(void(tmp));
    io.stdio.bufWriteStrLn(stdout_buf, msg);
    kfree(void(msg));
    kfree(void(pStr));
    kfree(void(fStr));
end;

{ ============================================================
  init — register the STORTEST and DISKTEST terminal commands
  ============================================================ }
procedure init;
begin
    debug.tracer.push_trace('driver.storage.test.init');
    io.stdio.registerCommand('STORTEST', @cmd_stortest,
        'Run storage subsystem unit tests.');
    io.stdio.registerCommand('DISKTEST', @cmd_disktest,
        'DESTRUCTIVE: wipe disk 0, format FAT32 4MB, write+read file.');
    debug.tracer.pop_trace;
end;

end.
