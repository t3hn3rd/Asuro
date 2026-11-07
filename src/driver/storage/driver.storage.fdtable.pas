//  Copyright 2021 Aaron Hance
//  Copyright 2026 Aaron Hance
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
    Driver->Storage->FDTable - Per-process file descriptor table.

    Each process owns a TFDTable (allocated on process create, freed on reap).
    File handles are 1-based indices into the table (0 = invalid).
    The VFS layer calls fd_alloc / fd_get / fd_close instead of touching
    a global OpenFiles array.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit driver.storage.fdtable;

interface

uses
    memory.heap,
    driver.storage.types,
    memory.raw, arch.common.interrupts;

const
    MAX_FDS = 64;

type
    TFDIdleHook = procedure;
    PFileDescriptor = ^TFileDescriptor;
    TFileDescriptor = record
        InUse       : boolean;
        Closing     : boolean;
        WaitClose   : boolean;
        AsyncRefs   : uint32;      { in-flight async ops using this descriptor }
        Volume      : PStorage_Volume;
        Directory   : pchar;       { directory path within the volume }
        FileName    : pchar;       { filename within that directory }
        VFSDir      : pchar;       { full VFS parent directory path, e.g. '/sys' }
        OpenMode    : uint8;       { TOpenMode ordinal — avoids VFS type dependency }
        DataSize    : uint32;      { cached file size in bytes (from fileSizeCallback) }
        DeviceOps   : pointer;     { PVFSDeviceOps — non-nil for device FDs }
        DeviceData  : pointer;     { opaque data passed to device callbacks }
        FSPrivate   : pointer;     { opaque FS-level per-file metadata (from openFileCallback) }
        FSCloseHook : pointer;     { procedure(pointer) — frees FSPrivate on close }
    end;

    PFDTable = ^TFDTable;
    TFDTable = record
        Entries : array[0..MAX_FDS-1] of TFileDescriptor;
        Closing, Freeing: boolean;
    end;

{ Allocate and zero-initialise a new FD table on the heap.
  Called once per process at creation time.
  Returns nil on out-of-memory. }
function  fd_table_new : PFDTable;

{ Free all open descriptors in the table, then free the table itself.
  Called when a process is reaped. Safe to pass nil. If begin_close fails,
  ownership remains with the caller until async users release their references. }
procedure fd_table_free(table : PFDTable);
{ Atomically prevent new references before detaching an owner. False means busy. }
function fd_table_begin_close(table: PFDTable): boolean;

{ Find the first free slot in the table.
  Returns 1-based handle (1..MAX_FDS) on success, 0 if table is full. }
function  fd_alloc(table : PFDTable) : uint32;

{ Get a pointer to the descriptor for a 1-based handle.
  Returns nil if handle is out of range or the slot is not in use. }
function  fd_get(table : PFDTable; handle : uint32) : PFileDescriptor;
function  fd_begin_async(entry : PFileDescriptor) : boolean;
procedure fd_end_async(entry : PFileDescriptor);
function  fd_has_async(entry : PFileDescriptor) : boolean;

{ Close a single file descriptor: free its buffers and core.strings,
  mark the slot as not-in-use.
  Returns true if the handle was valid and open, false otherwise. }
function  fd_close(table : PFDTable; handle : uint32) : boolean;

{ Close ALL open file descriptors in the table.
  Used during process cleanup. }
procedure fd_close_all(table : PFDTable);

{ Close all file descriptors in the table that reference a specific volume.
  Called when a volume is removed to prevent dangling pointers. }
procedure fd_close_for_volume(table : PFDTable; vol : PStorage_Volume);

procedure UnitTest;
{ Hook only wakes a worker; called with IRQs excluded, never performs cleanup. }
procedure fd_set_idle_hook(hook: TFDIdleHook);

implementation
uses debug.early;
var idleHook: TFDIdleHook;
procedure fd_set_idle_hook(hook: TFDIdleHook);
var flags: PtrUInt;
begin
    flags := arch.common.interrupts.lock;
    idleHook := hook;
    arch.common.interrupts.unlock(flags);
end;

function fd_table_new : PFDTable;
var
    tbl : PFDTable;
begin
    tbl := PFDTable(kalloc(SizeOf(TFDTable)));
    if tbl <> nil then
        memory.raw.fill(pointer(tbl), 0, SizeOf(TFDTable));
    fd_table_new := tbl;
end;

type
    TFSPrivateClose = procedure(data : pointer);

procedure releaseEntry(entry: PFileDescriptor);
var data: pointer; hook: TFSPrivateClose; flags: PtrUInt; wake: boolean;
begin
    { Entry is already claimed under IRQ exclusion. Never publish it for reuse
      while its close callback can still re-enter the descriptor API. }
    data := entry^.FSPrivate; hook := TFSPrivateClose(entry^.FSCloseHook);
    entry^.FSPrivate := nil; entry^.FSCloseHook := nil;
    if (data <> nil) and assigned(hook) then hook(data);
    if entry^.Directory <> nil then kfree(void(entry^.Directory));
    if entry^.FileName <> nil then kfree(void(entry^.FileName));
    if entry^.VFSDir <> nil then kfree(void(entry^.VFSDir));
    flags := arch.common.interrupts.lock;
    wake := entry^.WaitClose;
    memory.raw.fill(pointer(entry), 0, sizeof(TFileDescriptor));
    if wake and assigned(idleHook) then idleHook;
    arch.common.interrupts.unlock(flags);
end;
function fd_free_entry(entry: PFileDescriptor): boolean;
var flags: PtrUInt;
begin
    fd_free_entry := false;
    if entry = nil then exit;
    flags := arch.common.interrupts.lock;
    if (not entry^.InUse) or entry^.Closing or (entry^.AsyncRefs <> 0) then begin
        arch.common.interrupts.unlock(flags); exit;
    end;
    entry^.Closing := true;
    arch.common.interrupts.unlock(flags);
    releaseEntry(entry);
    fd_free_entry := true;
end;
function fd_table_begin_close(table: PFDTable): boolean;
var flags: PtrUInt; i: uint32;
begin
    fd_table_begin_close := true;
    if table = nil then exit;
    flags := arch.common.interrupts.lock;
    if not table^.Closing then begin
        for i := 0 to MAX_FDS - 1 do
            if table^.Entries[i].Closing or (table^.Entries[i].AsyncRefs <> 0) then begin
                table^.Entries[i].WaitClose := true;
                fd_table_begin_close := false;
            end;
        if not fd_table_begin_close then begin arch.common.interrupts.unlock(flags); exit; end;
        table^.Closing := true;
        for i := 0 to MAX_FDS - 1 do table^.Entries[i].Closing := true;
    end;
    arch.common.interrupts.unlock(flags);
end;
procedure fd_table_free(table: PFDTable);
var flags: PtrUInt; i: uint32;
begin
    if table = nil then exit;
    flags := arch.common.interrupts.lock;
    if table^.Freeing or not fd_table_begin_close(table) then begin
        arch.common.interrupts.unlock(flags); exit;
    end;
    table^.Freeing := true;
    arch.common.interrupts.unlock(flags);
    for i := 0 to MAX_FDS - 1 do
        if table^.Entries[i].InUse then releaseEntry(@table^.Entries[i]);
    kfree(void(table));
end;

function fd_alloc(table : PFDTable) : uint32;
var
    i : uint32;
begin
    fd_alloc := 0;
    if table = nil then exit;
    if table^.Closing then exit;
    for i := 0 to MAX_FDS - 1 do begin
        if (not table^.Entries[i].InUse) and (not table^.Entries[i].Closing) then begin
            fd_alloc := i + 1;  { 1-based }
            exit;
        end;
    end;
end;

function fd_get(table : PFDTable; handle : uint32) : PFileDescriptor;
begin
    fd_get := nil;
    if table = nil then exit;
    if (handle = 0) or (handle > MAX_FDS) then exit;
    if table^.Closing or table^.Entries[handle - 1].Closing then exit;
    if not table^.Entries[handle - 1].InUse then exit;
    fd_get := @table^.Entries[handle - 1];
end;

function fd_begin_async(entry : PFileDescriptor) : boolean;
var flags: PtrUInt;
begin
    fd_begin_async := false;
    if entry = nil then exit;
    flags := arch.common.interrupts.lock;
    if entry^.InUse and not entry^.Closing and (entry^.AsyncRefs < High(uint32)) then begin
        entry^.AsyncRefs := entry^.AsyncRefs + 1;
        fd_begin_async := true;
    end;
    arch.common.interrupts.unlock(flags);
end;

procedure fd_end_async(entry : PFileDescriptor);
var flags: PtrUInt;
begin
    if entry = nil then exit;
    flags := arch.common.interrupts.lock;
    if entry^.AsyncRefs > 0 then begin
        dec(entry^.AsyncRefs);
        if (entry^.AsyncRefs = 0) and entry^.WaitClose and assigned(idleHook) then idleHook;
    end;
    arch.common.interrupts.unlock(flags);
end;

function fd_has_async(entry : PFileDescriptor) : boolean;
begin
    fd_has_async := false;
    if entry = nil then exit;
    fd_has_async := PUInt32(@entry^.AsyncRefs)^ > 0;
end;

function fd_close(table : PFDTable; handle : uint32) : boolean;
begin
    fd_close := false;
    if table = nil then exit;
    if (handle = 0) or (handle > MAX_FDS) then exit;
    if table^.Closing or table^.Entries[handle - 1].Closing then exit;
    if not table^.Entries[handle - 1].InUse then exit;
    fd_close := fd_free_entry(@table^.Entries[handle - 1]);
end;

procedure fd_close_all(table : PFDTable);
var
    i : uint32;
begin
    if table = nil then exit;
    for i := 0 to MAX_FDS - 1 do begin
        if table^.Entries[i].InUse then
            fd_free_entry(@table^.Entries[i]);
    end;
end;

procedure fd_close_for_volume(table : PFDTable; vol : PStorage_Volume);
var
    i : uint32;
begin
    if table = nil then exit;
    if vol = nil then exit;
    for i := 0 to MAX_FDS - 1 do begin
        if table^.Entries[i].InUse and (table^.Entries[i].Volume = vol) then
            fd_free_entry(@table^.Entries[i]);
    end;
end;

var
    testTable: PFDTable;
    testHandle, testClosed: uint32;
    testReentry: boolean;
procedure testClose(data: pointer);
begin
    inc(testClosed);
    testReentry := not fd_close(testTable, testHandle);
    kfree(void(data));
end;
procedure UnitTest;
var
    table: PFDTable;
    entry: PFileDescriptor;
    i, passed, failed: uint32;
    beforeFree: SizeUInt;
    slotsValid: boolean;
    procedure Assert(condition: boolean; name: pchar);
    begin
        if condition then begin inc(passed); puts('PASS: '); end
        else begin inc(failed); puts('FAIL: '); end;
        puts(name); puts(#13#10);
    end;
begin
    passed := 0; failed := 0; beforeFree := lmm_total_free;
    table := fd_table_new;
    testTable := table; testHandle := 1; testClosed := 0; testReentry := false;
    Assert((fd_get(table, 0) = nil) and (fd_get(table, MAX_FDS + 1) = nil), 'FD handle boundaries');
    slotsValid := true;
    for i := 0 to MAX_FDS - 1 do begin
        if fd_alloc(table) <> i + 1 then slotsValid := false;
        table^.Entries[i].InUse := true;
    end;
    Assert(slotsValid, 'FD bounded slot allocation');
    Assert(fd_alloc(table) = 0, 'FD full table rejects allocation');
    entry := fd_get(table, 1);
    entry^.Directory := pchar(kalloc(3)); entry^.FileName := pchar(kalloc(5));
    entry^.VFSDir := pchar(kalloc(7)); entry^.FSPrivate := pointer(kalloc(9));
    entry^.FSCloseHook := @testClose;
    Assert(fd_begin_async(entry), 'FD acquires async reference');
    Assert(not fd_close(table, 1), 'FD close retains active async storage');
    Assert(not fd_table_begin_close(table), 'FD table teardown waits for async references');
    fd_end_async(entry);
    Assert(not fd_has_async(entry), 'FD completion releases async reference');
    Assert(fd_close(table, 1), 'FD closes after async completion');
    Assert((testClosed = 1) and testReentry, 'FD callback reentry cannot close twice');
    Assert(fd_get(table, 1) = nil, 'FD closed handle unavailable');
    Assert(fd_alloc(table) = 1, 'FD closed slot reusable');
    entry := @table^.Entries[0]; entry^.InUse := true;
    entry^.AsyncRefs := High(uint32);
    Assert(not fd_begin_async(entry), 'FD async reference overflow rejected');
    entry^.AsyncRefs := 0;
    Assert(fd_table_begin_close(table), 'FD table teardown reserves all slots');
    Assert((fd_alloc(table) = 0) and not fd_begin_async(entry), 'FD closing table rejects new users');
    fd_table_free(table);
    Assert(lmm_total_free = beforeFree, 'FD table strings and metadata released');
    field('FD_TESTS_PASSED', passed); field('FD_TESTS_FAILED', failed);
end;

end.
