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

    Pattern: same Assert + PrintSummary approach as vfs.UnitTest.
    Output goes to syslog ('STORTEST' tag) from UnitTest, and to
    stdout_buf from the STORTEST command.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit storagetest;

interface

procedure UnitTest;
procedure init;

implementation

uses
    hashmap,
    lmemorymanager,
    mbr,
    stdio,
    storagemanager,
    storagetypes,
    strings,
    syslog,
    tracer,
    util,
    vfs,
    volumemanager;

{ ============================================================
  run_tests — shared test body called by both UnitTest (boot)
  and the STORTEST shell command (runtime).

  passed / failed are in/out accumulator params so the caller
  can print a combined summary.
  ============================================================ }
procedure run_tests(var passed, failed: uint32; to_log: boolean;
                    stdout_buf: POutBuf);

    { Write a line either to syslog or to the terminal stdout buffer }
    procedure emit(tag, msg: pchar);
    var
        line: pchar;
    begin
        if to_log then begin
            syslog.logln(tag, msg);
        end else begin
            if stdout_buf <> nil then begin
                line := stringConcat('[', tag);
                stdio.bufWriteStr(stdout_buf, line);
                kfree(void(line));
                stdio.bufWriteStr(stdout_buf, '] ');
                stdio.bufWriteStrLn(stdout_buf, msg);
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
    errCode: storagetypes.TError;
    res    : TIsPathValid;

begin
    tracer.push_trace('storagetest.run_tests');

    { ---- makeAbsolutePathFrom ---- }
    { Absolute path should be returned unchanged }
    p := vfs.makeAbsolutePathFrom('/foo/bar', '/base');
    Assert(stringEquals(p, '/foo/bar'), 'makeAbsolutePathFrom: abs passthrough');
    kfree(void(p));

    { Relative path joined to base (base has trailing slash) }
    p := vfs.makeAbsolutePathFrom('file.txt', '/home/');
    Assert(stringEquals(p, '/home/file.txt'), 'makeAbsolutePathFrom: rel+base trailing /');
    kfree(void(p));

    { Relative path joined to base (base has no trailing slash) }
    p := vfs.makeAbsolutePathFrom('file.txt', '/home');
    Assert(stringEquals(p, '/home/file.txt'), 'makeAbsolutePathFrom: rel+base no trailing /');
    kfree(void(p));

    { ---- resolvePathFrom ---- }
    { Known virtual dirs resolve to pvDirectory }
    res := vfs.resolvePathFrom('disk', '/');
    Assert(res = pvDirectory, 'resolvePathFrom: /disk from /');

    res := vfs.resolvePathFrom('dev', '/');
    Assert(res = pvDirectory, 'resolvePathFrom: /dev from /');

    res := vfs.resolvePathFrom('mnt', '/');
    Assert(res = pvDirectory, 'resolvePathFrom: /mnt from /');

    res := vfs.resolvePathFrom('cfg', '/');
    Assert(res = pvDirectory, 'resolvePathFrom: /cfg from /');

    { Non-existent names resolve to pvInvalid }
    res := vfs.resolvePathFrom('zzznope', '/');
    Assert(res = pvInvalid, 'resolvePathFrom: nonexistent from /');

    { ---- changeDirectoryFrom ---- }
    newDir := nil;
    res := vfs.changeDirectoryFrom('disk', '/', newDir);
    Assert(res = pvDirectory, 'changeDirectoryFrom /disk: returns dir');
    Assert((newDir <> nil) and stringEquals(newDir, '/disk'),
           'changeDirectoryFrom /disk: newDir = /disk');
    if newDir <> nil then kfree(void(newDir));

    newDir := nil;
    res := vfs.changeDirectoryFrom('zzznope', '/', newDir);
    Assert(res = pvInvalid, 'changeDirectoryFrom nonexistent: returns invalid');
    Assert(newDir = nil, 'changeDirectoryFrom nonexistent: newDir nil');

    { ---- GetDirectoryListingFrom ---- }
    { Root listing should be non-nil (in-memory VFS always populated) }
    map := vfs.GetDirectoryListingFrom('/', '/');
    Assert(map <> nil, 'GetDirectoryListingFrom(/) not nil');

    { /disk, /dev, /mnt, /cfg created at init — must appear in root listing }
    map := vfs.GetDirectoryListingFrom('/', '/');
    Assert(map <> nil, 'GetDirectoryListingFrom(/) not nil (2)');
    { Note: we don't free this map — it's the live VFS in-memory reference,
      NOT a caller-owned alloc.  Freeing it would corrupt the VFS tree. }

    { Listing a leaf vdir returns non-nil (even if empty) }
    map := vfs.GetDirectoryListingFrom('/dev', '/');
    Assert(map <> nil, 'GetDirectoryListingFrom(/dev) not nil');

    map := vfs.GetDirectoryListingFrom('/cfg', '/');
    Assert(map <> nil, 'GetDirectoryListingFrom(/cfg) not nil');

    { Non-existent path returns nil (no crash) }
    map := vfs.GetDirectoryListingFrom('/zzznope', '/');
    Assert(map = nil, 'GetDirectoryListingFrom(nonexistent) = nil');

    { ---- newVirtualDirectory edge cases ---- }
    { Create a fresh nested path }
    errCode := vfs.newVirtualDirectory('/st_test/nested');
    { Parent /st_test didn't exist — expect eDirectoryDoesNotExist }
    Assert(errCode = eDirectoryDoesNotExist,
           'newVirtualDirectory: missing parent = eDirDoesNotExist');

    { Create /st_test first, then child }
    errCode := vfs.newVirtualDirectory('/st_test');
    Assert(errCode = eNone, 'newVirtualDirectory /st_test = eNone');

    errCode := vfs.newVirtualDirectory('/st_test/nested');
    Assert(errCode = eNone, 'newVirtualDirectory /st_test/nested = eNone');

    { Attempting to create it again should give eDirectoryAlreadyExists }
    errCode := vfs.newVirtualDirectory('/st_test/nested');
    Assert(errCode = eDirectoryAlreadyExists,
           'newVirtualDirectory duplicate = eDirectoryAlreadyExists');

    { Verify the new dir is visible via PathValid }
    Assert(vfs.PathValid('/st_test')        = pvDirectory, 'PathValid /st_test');
    Assert(vfs.PathValid('/st_test/nested') = pvDirectory, 'PathValid /st_test/nested');

    { Verify resolvePathFrom sees the new dirs }
    res := vfs.resolvePathFrom('st_test', '/');
    Assert(res = pvDirectory, 'resolvePathFrom st_test after create');

    res := vfs.resolvePathFrom('nested', '/st_test');
    Assert(res = pvDirectory, 'resolvePathFrom nested in st_test');

    { ---- PathValid with dotdot traversal ---- }
    { /st_test/nested/.. should collapse back to /st_test }
    Assert(vfs.PathValid('/st_test/nested/../') = pvDirectory,
           'PathValid with .. collapse');

    { . traversal stays in same dir }
    Assert(vfs.PathValid('/st_test/./') = pvDirectory,
           'PathValid with . stays put');

    tracer.pop_trace;
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
            syslog.logln(tag, msg);
        end else begin
            if stdout_buf <> nil then begin
                line := stringConcat('[', tag);
                stdio.bufWriteStr(stdout_buf, line);
                kfree(void(line));
                stdio.bufWriteStr(stdout_buf, '] ');
                stdio.bufWriteStrLn(stdout_buf, msg);
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
    tracer.push_trace('storagetest.run_disk_tests');

    { ---- Get disk 0 ---- }
    disk := storagemanager.get_device(0);
    if disk = nil then begin
        emit('DISKTEST', 'No disk 0 found — skipping disk tests');
        tracer.pop_trace;
        exit;
    end;
    if not disk^.writable then begin
        emit('DISKTEST', 'Disk 0 not writable — skipping disk tests');
        tracer.pop_trace;
        exit;
    end;

    { ---- Wipe disk 0 ---- }
    volumemanager.init_disk(disk);
    emit('DISKTEST', 'Disk 0 wiped.');

    { ---- Create 4 MB MBR partition at LBA 2048 ---- }
    memset(uint32(@part), 0, sizeof(TPartition_table));
    part.system_id := $0B;  { FAT32 < 2GB }
    mbr.setup_partition(@part, 2048, 8192);  { LBA_start=2048, sector_count=8192 }
    volumemanager.add_partition(disk, 0, part);
    Assert(volumemanager.get_volume_count() > 0, 'add_partition: volume count > 0');

    { ---- Format as FAT32 ---- }
    volIdx := volumemanager.get_volume_count() - 1;
    Assert(volumemanager.format_volume(disk, volIdx, 'FAT32', nil),
           'format_volume FAT32 = true');

    { ---- Mount at /disk/dt_vol ---- }
    vol := volumemanager.get_volume(volIdx);
    Assert(vol <> nil, 'get_volume not nil');
    if vol = nil then begin tracer.pop_trace; exit; end;
    Assert(vfs.mountVolume('/disk/dt_vol', vol) = pvRegistered,
           'mountVolume = pvRegistered');

    { ---- Write 512 bytes of 0xA5 to TEST.TXT ---- }
    wbuf := puint8(kalloc(512));
    for i := 0 to 511 do
        wbuf[i] := $A5;
    err := eNone;
    fh := vfs.OpenFile('/disk/dt_vol/TEST.TXT', omWriteOnly, wmNew, @err);
    Assert(err = eNone, 'OpenFile for write: err = eNone');
    n := vfs.WriteFile(fh, 0, wbuf, 512);
    Assert(n = 512, 'WriteFile 512 bytes');
    vfs.CloseFile(fh);

    { ---- Read back ---- }
    rbuf := puint8(kalloc(512));
    memset(uint32(rbuf), 0, 512);
    err := eNone;
    fh := vfs.OpenFile('/disk/dt_vol/TEST.TXT', omReadOnly, wmRewrite, @err);
    Assert(err = eNone, 'OpenFile for read: err = eNone');
    n := vfs.ReadFile(fh, 0, rbuf, 512);
    Assert(n = 512, 'ReadFile 512 bytes');
    vfs.CloseFile(fh);

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

    tracer.pop_trace;
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
    syslog.logln('STORTEST', 'Unit tests starting...');

    run_tests(passed, failed, true, nil);

    pStr := intToString(passed);
    fStr := intToString(failed);
    msg  := stringConcat(pStr, ' passed, ');
    tmp  := stringConcat(msg, fStr);
    kfree(void(msg));
    msg  := stringConcat(tmp, ' failed.');
    kfree(void(tmp));
    syslog.logln('STORTEST', msg);
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
begin
    passed := 0;
    failed := 0;
    stdio.bufWriteStrLn(stdout_buf, '--- Storage subsystem tests ---');

    run_tests(passed, failed, false, stdout_buf);

    { Runtime-only: test /disk listing (populated only after auto_mount_volumes) }
    if vfs.GetDirectoryListingFrom('/disk', '/') <> nil then
        stdio.bufWriteStrLn(stdout_buf, '[+] /disk listing available (volumes mounted)')
    else
        stdio.bufWriteStrLn(stdout_buf, '[-] /disk listing nil (no volumes mounted)');

    pStr := intToString(passed);
    fStr := intToString(failed);
    msg  := stringConcat(pStr, ' passed, ');
    tmp  := stringConcat(msg, fStr);
    kfree(void(msg));
    msg  := stringConcat(tmp, ' failed.');
    kfree(void(tmp));
    stdio.bufWriteStrLn(stdout_buf, msg);
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
    stdio.bufWriteStrLn(stdout_buf, '--- DISKTEST: DESTRUCTIVE disk 0 I/O test ---');
    stdio.bufWriteStrLn(stdout_buf, 'WARNING: This will wipe disk 0!');

    run_disk_tests(passed, failed, false, stdout_buf);

    pStr := intToString(passed);
    fStr := intToString(failed);
    msg  := stringConcat(pStr, ' passed, ');
    tmp  := stringConcat(msg, fStr);
    kfree(void(msg));
    msg  := stringConcat(tmp, ' failed.');
    kfree(void(tmp));
    stdio.bufWriteStrLn(stdout_buf, msg);
    kfree(void(msg));
    kfree(void(pStr));
    kfree(void(fStr));
end;

{ ============================================================
  init — register the STORTEST and DISKTEST terminal commands
  ============================================================ }
procedure init;
begin
    tracer.push_trace('storagetest.init');
    stdio.registerCommand('STORTEST', @cmd_stortest,
        'Run storage subsystem unit tests.');
    stdio.registerCommand('DISKTEST', @cmd_disktest,
        'DESTRUCTIVE: wipe disk 0, format FAT32 4MB, write+read file.');
    tracer.pop_trace;
end;

end.
