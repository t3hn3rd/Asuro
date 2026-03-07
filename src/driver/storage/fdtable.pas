{
    Driver->Storage->FDTable - Per-process file descriptor table.

    Each process owns a TFDTable (allocated on process create, freed on reap).
    File handles are 1-based indices into the table (0 = invalid).
    The VFS layer calls fd_alloc / fd_get / fd_close instead of touching
    a global OpenFiles array.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit fdtable;

interface

uses
    lmemorymanager,
    storagetypes,
    util;

const
    MAX_FDS = 64;

type
    PFileDescriptor = ^TFileDescriptor;
    TFileDescriptor = record
        InUse       : boolean;
        Volume      : PStorage_Volume;
        Directory   : pchar;       { directory path within the volume }
        FileName    : pchar;       { filename within that directory }
        OpenMode    : uint8;       { TOpenMode ordinal — avoids VFS type dependency }
        WriteMode   : uint8;       { TWriteMode ordinal }
        DataBuffer  : puint32;     { pre-loaded data for small files, nil otherwise }
        DataSize    : uint32;      { size of pre-loaded data in bytes }
        Loaded      : boolean;     { true if pre-loaded into DataBuffer }
        StreamOff   : uint32;      { current byte offset for streaming / on-demand reads }
    end;

    PFDTable = ^TFDTable;
    TFDTable = record
        Entries : array[0..MAX_FDS-1] of TFileDescriptor;
    end;

{ Allocate and zero-initialise a new FD table on the heap.
  Called once per process at creation time.
  Returns nil on out-of-memory. }
function  fd_table_new : PFDTable;

{ Free all open descriptors in the table, then free the table itself.
  Called when a process is reaped. Safe to pass nil. }
procedure fd_table_free(table : PFDTable);

{ Find the first free slot in the table.
  Returns 1-based handle (1..MAX_FDS) on success, 0 if table is full. }
function  fd_alloc(table : PFDTable) : uint32;

{ Get a pointer to the descriptor for a 1-based handle.
  Returns nil if handle is out of range or the slot is not in use. }
function  fd_get(table : PFDTable; handle : uint32) : PFileDescriptor;

{ Close a single file descriptor: free its buffers and strings,
  mark the slot as not-in-use.
  Returns true if the handle was valid and open, false otherwise. }
function  fd_close(table : PFDTable; handle : uint32) : boolean;

{ Close ALL open file descriptors in the table.
  Used during process cleanup. }
procedure fd_close_all(table : PFDTable);

implementation

function fd_table_new : PFDTable;
var
    tbl : PFDTable;
begin
    tbl := PFDTable(kalloc(SizeOf(TFDTable)));
    if tbl <> nil then
        memset(uint32(tbl), 0, SizeOf(TFDTable));
    fd_table_new := tbl;
end;

procedure fd_free_entry(entry : PFileDescriptor);
begin
    if entry = nil then exit;
    if not entry^.InUse then exit;

    if entry^.DataBuffer <> nil then begin
        kfree(entry^.DataBuffer);
        entry^.DataBuffer := nil;
    end;
    if entry^.Directory <> nil then begin
        kfree(void(entry^.Directory));
        entry^.Directory := nil;
    end;
    if entry^.FileName <> nil then begin
        kfree(void(entry^.FileName));
        entry^.FileName := nil;
    end;

    entry^.InUse := false;
    entry^.Loaded := false;
    entry^.DataSize := 0;
    entry^.StreamOff := 0;
end;

procedure fd_table_free(table : PFDTable);
begin
    if table = nil then exit;
    fd_close_all(table);
    kfree(puint32(table));
end;

function fd_alloc(table : PFDTable) : uint32;
var
    i : uint32;
begin
    fd_alloc := 0;
    if table = nil then exit;
    for i := 0 to MAX_FDS - 1 do begin
        if not table^.Entries[i].InUse then begin
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
    if not table^.Entries[handle - 1].InUse then exit;
    fd_get := @table^.Entries[handle - 1];
end;

function fd_close(table : PFDTable; handle : uint32) : boolean;
begin
    fd_close := false;
    if table = nil then exit;
    if (handle = 0) or (handle > MAX_FDS) then exit;
    if not table^.Entries[handle - 1].InUse then exit;
    fd_free_entry(@table^.Entries[handle - 1]);
    fd_close := true;
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

end.
