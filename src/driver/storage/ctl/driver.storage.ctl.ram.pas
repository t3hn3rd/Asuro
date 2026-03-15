{
    Driver->Storage->RAMDrive - In-memory VFS drive for testing.

    Provides a simple RAM-backed volume mounted at /disk/ram.
    Files are stored as (name, pointer, size) tuples in a flat table.
    Use storeFile() to pre-load bytecode or other data that can then
    be read via the standard VFS path interface.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.storage.ctl.ram;

interface

uses
    driver.storage.vfs, debug.tracer, io.syslog, driver.storage.types;

{ Store a file in the RAM drive.  data is NOT copied — the pointer
  is kept as-is, so the caller must ensure it remains valid.
  name should be a simple filename (no slashes), e.g. 'hello.wasm'.
  Returns true on success, false if the table is full. }
function storeFile(name : pchar; data : puint8; size : uint32) : boolean;

{ Store a file in the RAM drive, copying the data into a new kalloc'd
  buffer.  Safe when the original buffer will be freed later.
  Returns true on success. }
function storeFileCopy(name : pchar; data : puint8; size : uint32) : boolean;

{ Remove a file from the RAM drive by name.
  If freeBuf is true, kfree the data buffer. }
procedure removeFile(name : pchar; freeBuf : boolean);

{ Initialise the RAM drive and mount it in VFS at /disk/ram }
procedure init;

implementation

uses
    core.strings, memory.heap, core.ds.lists, core.util, arch.x86.util;

const
    MAX_RAM_FILES = 32;

type
    TRAMFile = record
        Name : pchar;     { kalloc'd copy of the filename }
        Data : puint8;    { pointer to file data }
        Size : uint32;    { file size in bytes }
        Used : boolean;   { slot in use? }
    end;

var
    Files      : array[0..MAX_RAM_FILES-1] of TRAMFile;
    FileCount  : uint32;
    RAMVolume  : TStorage_Volume;
    RAMFS      : TFilesystem;

{ ---- Internal helpers ---- }

function findFileByName(name : pchar) : sint32;
var
    i : uint32;
begin
    findFileByName := -1;
    for i := 0 to MAX_RAM_FILES - 1 do begin
        if Files[i].Used and stringEquals(Files[i].Name, name) then begin
            findFileByName := sint32(i);
            exit;
        end;
    end;
end;

{ Strip a leading '/' from a relative path. VFS passes paths like
  '/hello.wasm'; we need just 'hello.wasm' for internal lookup. }
function stripLeadingSlash(path : pchar) : pchar;
begin
    if (path <> nil) and (path[0] = '/') then
        stripLeadingSlash := pchar(uint32(path) + 1)
    else
        stripLeadingSlash := path;
end;

{ ---- Filesystem hook callbacks ---- }

{ PPReadOffsetHook — read byteCount bytes at offset into caller buffer.
  Returns actual bytes copied. }
function rd_ReadOffset(volume : PStorage_Volume; directory : pchar;
                       fileName : pchar; offset : uint32;
                       buffer : puint32; byteCount : uint32) : uint32;
var
    clean   : pchar;
    idx     : sint32;
    avail   : uint32;
    copyLen : uint32;
begin
    rd_ReadOffset := 0;
    clean := stripLeadingSlash(fileName);
    if clean = nil then exit;
    idx := findFileByName(clean);
    if idx < 0 then exit;
    if offset >= Files[idx].Size then exit;

    avail := Files[idx].Size - offset;
    if byteCount < avail then copyLen := byteCount else copyLen := avail;
    memcpy(uint32(Files[idx].Data) + offset, uint32(buffer), copyLen);
    rd_ReadOffset := copyLen;
end;

function rd_FileSize(volume : PStorage_Volume; directory : pchar;
                     fileName : pchar) : uint32;
var
    clean : pchar;
    idx   : sint32;
begin
    rd_FileSize := 0;
    clean := stripLeadingSlash(fileName);
    if clean = nil then exit;
    idx := findFileByName(clean);
    if idx < 0 then exit;
    rd_FileSize := Files[idx].Size;
end;

{ PPReadDirHook — return a linked list of TDirectory_Entry for all files.
  VFS owns the returned list and frees each entry^.fileName. }
function rd_ReadDir(volume : PStorage_Volume; directory : pchar;
                    status : puint32) : PLinkedListBase;
var
    dirList : PLinkedListBase;
    entry   : PDirectory_Entry;
    i       : uint32;
begin
    dirList := LL_New(sizeof(TDirectory_Entry));
    for i := 0 to MAX_RAM_FILES - 1 do begin
        if Files[i].Used then begin
            entry := PDirectory_Entry(LL_Add(dirList));
            entry^.fileName := stringCopy(Files[i].Name);
            entry^.entryType := fileEntry;
            entry^.fileSize := Files[i].Size;
            entry^.modifiedDate := 0;
            entry^.modifiedTime := 0;
            entry^.attributes := 0;
        end;
    end;
    if status <> nil then status^ := 0;
    rd_ReadDir := dirList;
end;

{ PPIdentifyHook — always claim ownership }
function rd_Identify(volume : PStorage_Volume) : boolean;
begin
    rd_Identify := true;
end;

{ ---- Public API ---- }

function storeFile(name : pchar; data : puint8; size : uint32) : boolean;
var
    i : uint32;
begin
    storeFile := false;
    if (name = nil) or (data = nil) or (size = 0) then exit;

    { Overwrite if name already exists }
    for i := 0 to MAX_RAM_FILES - 1 do begin
        if Files[i].Used and stringEquals(Files[i].Name, name) then begin
            Files[i].Data := data;
            Files[i].Size := size;
            storeFile := true;
            exit;
        end;
    end;

    { Find a free slot }
    for i := 0 to MAX_RAM_FILES - 1 do begin
        if not Files[i].Used then begin
            Files[i].Name := stringCopy(name);
            Files[i].Data := data;
            Files[i].Size := size;
            Files[i].Used := true;
            inc(FileCount);
            storeFile := true;
            exit;
        end;
    end;
end;

function storeFileCopy(name : pchar; data : puint8; size : uint32) : boolean;
var
    buf : puint8;
begin
    storeFileCopy := false;
    if (data = nil) or (size = 0) then exit;
    buf := puint8(kalloc(size));
    if buf = nil then exit;
    memcpy(uint32(data), uint32(buf), size);
    storeFileCopy := storeFile(name, buf, size);
end;

procedure removeFile(name : pchar; freeBuf : boolean);
var
    idx : sint32;
begin
    idx := findFileByName(name);
    if idx < 0 then exit;
    if freeBuf and (Files[idx].Data <> nil) then
        kfree(void(Files[idx].Data));
    if Files[idx].Name <> nil then
        kfree(void(Files[idx].Name));
    Files[idx].Used := false;
    Files[idx].Data := nil;
    Files[idx].Name := nil;
    Files[idx].Size := 0;
    dec(FileCount);
end;

{ ---- Built-in programs ---- }

procedure loadBuiltins;
const
    { Hello World WASM binary — prints "Hello, World!\n" via fd_write then exits }
    HELLO_SIZE = 185;
    HELLO_DATA : array[0..HELLO_SIZE-1] of uint8 = (
        $00,$61,$73,$6D,$01,$00,$00,$00,$01,$10,$03,$60,$04,$7F,$7F,$7F,
        $7F,$01,$7F,$60,$01,$7F,$00,$60,$00,$00,$02,$46,$02,$16,$77,$61,
        $73,$69,$5F,$73,$6E,$61,$70,$73,$68,$6F,$74,$5F,$70,$72,$65,$76,
        $69,$65,$77,$31,$08,$66,$64,$5F,$77,$72,$69,$74,$65,$00,$00,$16,
        $77,$61,$73,$69,$5F,$73,$6E,$61,$70,$73,$68,$6F,$74,$5F,$70,$72,
        $65,$76,$69,$65,$77,$31,$09,$70,$72,$6F,$63,$5F,$65,$78,$69,$74,
        $00,$01,$03,$02,$01,$02,$05,$03,$01,$00,$01,$07,$13,$02,$06,$6D,
        $65,$6D,$6F,$72,$79,$02,$00,$06,$5F,$73,$74,$61,$72,$74,$00,$02,
        $0A,$14,$01,$12,$00,$41,$01,$41,$00,$41,$01,$41,$E4,$00,$10,$00,
        $1A,$41,$00,$10,$01,$0B,$0B,$21,$02,$00,$41,$08,$0B,$0E,$48,$65,
        $6C,$6C,$6F,$2C,$20,$57,$6F,$72,$6C,$64,$21,$0A,$00,$41,$00,$0B,
        $08,$08,$00,$00,$00,$0E,$00,$00,$00
    );
begin
    storeFileCopy('hello', @HELLO_DATA[0], HELLO_SIZE);
end;

procedure init;
var
    i : uint32;
begin
    debug.tracer.push_trace('driver.storage.ctl.ram.init');
    io.syslog.logln('RAMDRIVE', 'INIT BEGIN.');

    { Zero all file slots }
    for i := 0 to MAX_RAM_FILES - 1 do begin
        Files[i].Used := false;
        Files[i].Name := nil;
        Files[i].Data := nil;
        Files[i].Size := 0;
    end;
    FileCount := 0;

    { Set up a minimal filesystem descriptor with our callbacks }
    memset(uint32(@RAMFS), 0, sizeof(TFilesystem));
    RAMFS.sName := 'ramfs';
    RAMFS.readDirCallback := @rd_ReadDir;
    RAMFS.readOffsetCallback := @rd_ReadOffset;
    RAMFS.fileSizeCallback := @rd_FileSize;
    RAMFS.identifyCallback := @rd_Identify;

    { Set up a virtual volume backed by our filesystem }
    memset(uint32(@RAMVolume), 0, sizeof(TStorage_Volume));
    RAMVolume.filesystem := @RAMFS;

    { Mount into VFS at /disk/ram }
    driver.storage.vfs.mountVolume('/disk/ram', @RAMVolume);

    { Pre-load built-in WASM programs }
    loadBuiltins;

    io.syslog.logln('RAMDRIVE', 'INIT END.');
end;

end.
