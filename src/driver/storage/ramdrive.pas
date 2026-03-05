{
    Driver->Storage->RAMDrive - In-memory VFS drive for testing.

    Provides a simple RAM-backed drive registered at /disk/ram.
    Files are stored as (name, pointer, size) tuples in a flat table.
    Use storeFile() to pre-load bytecode or other data that can then
    be read via the standard VFS path interface.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit ramdrive;

interface

uses
    vfs, tracer, syslog;

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

{ Initialise the RAM drive and register it with VFS as /disk/ram }
procedure init;

implementation

uses
    strings, lmemorymanager, hashmap, util;

const
    MAX_RAM_FILES  = 32;
    MAX_OPEN_SLOTS = 8;

type
    TRAMFile = record
        Name : pchar;     { kalloc'd copy of the filename }
        Data : puint8;    { pointer to file data }
        Size : uint32;    { file size in bytes }
        Used : boolean;   { slot in use? }
    end;

    TOpenSlot = record
        FileIdx : uint32;   { index into Files[] }
        InUse   : boolean;
    end;

var
    Files     : array[0..MAX_RAM_FILES-1] of TRAMFile;
    OpenSlots : array[0..MAX_OPEN_SLOTS-1] of TOpenSlot;
    FileCount : uint32;

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

{ Strip a leading '/' from a relative path. ramdrive callbacks receive
  paths like '/hello.wasm'; we need just 'hello.wasm' for lookup. }
function stripLeadingSlash(path : pchar) : pchar;
begin
    if (path <> nil) and (path[0] = '/') then
        stripLeadingSlash := pchar(uint32(path) + 1)
    else
        stripLeadingSlash := path;
end;

{ ---- VFS drive callbacks ---- }

function rd_PathValid(Handle : uint32; Path : pchar) : TIsPathValid;
var
    clean : pchar;
    idx   : sint32;
begin
    rd_PathValid := pvInvalid;
    clean := stripLeadingSlash(Path);
    if (clean = nil) or (clean[0] = #0) then begin
        { Root of drive = directory }
        rd_PathValid := pvDirectory;
        exit;
    end;
    idx := findFileByName(clean);
    if idx >= 0 then
        rd_PathValid := pvFile
    else
        rd_PathValid := pvInvalid;
end;

function rd_FileSize(Handle : uint32; Filename : pchar; error : puint8) : uint32;
var
    clean : pchar;
    idx   : sint32;
begin
    rd_FileSize := 0;
    clean := stripLeadingSlash(Filename);
    if clean = nil then exit;
    idx := findFileByName(clean);
    if idx >= 0 then begin
        rd_FileSize := Files[idx].Size;
        if error <> nil then error^ := 0;
    end else begin
        if error <> nil then error^ := 1;
    end;
end;

function rd_OpenFile(Handle : uint32; Filename : pchar; OpenMode : TOpenMode;
                     WriteMode : TWriteMode; Lock : Boolean;
                     Error : PError) : TFileHandle;
var
    clean : pchar;
    fidx  : sint32;
    i     : uint32;
begin
    rd_OpenFile := 0;
    clean := stripLeadingSlash(Filename);
    if clean = nil then begin
        if Error <> nil then Error^ := eFileDoesNotExist;
        exit;
    end;
    fidx := findFileByName(clean);
    if fidx < 0 then begin
        if Error <> nil then Error^ := eFileDoesNotExist;
        exit;
    end;
    { Find a free open slot }
    for i := 0 to MAX_OPEN_SLOTS - 1 do begin
        if not OpenSlots[i].InUse then begin
            OpenSlots[i].InUse := true;
            OpenSlots[i].FileIdx := uint32(fidx);
            rd_OpenFile := i + 1; { handles are 1-based }
            if Error <> nil then Error^ := eNone;
            exit;
        end;
    end;
    { No free slots }
    if Error <> nil then Error^ := eUnknown;
end;

function rd_ReadFile(Handle : uint32; FileHandle : TFileHandle;
                     Position : uint32; Buffer : puint8;
                     Length : uint32) : uint32;
var
    slot : uint32;
    fidx : uint32;
    avail : uint32;
    copyLen : uint32;
begin
    rd_ReadFile := 0;
    if (FileHandle = 0) or (FileHandle > MAX_OPEN_SLOTS) then exit;
    slot := FileHandle - 1;
    if not OpenSlots[slot].InUse then exit;
    fidx := OpenSlots[slot].FileIdx;
    if not Files[fidx].Used then exit;
    if Position >= Files[fidx].Size then exit;
    avail := Files[fidx].Size - Position;
    if Length < avail then copyLen := Length else copyLen := avail;
    memcpy(uint32(Files[fidx].Data) + Position,
           uint32(Buffer), copyLen);
    rd_ReadFile := copyLen;
end;

function rd_CloseFile(Handle : uint32; FileHandle : TFileHandle) : boolean;
var
    slot : uint32;
begin
    rd_CloseFile := false;
    if (FileHandle = 0) or (FileHandle > MAX_OPEN_SLOTS) then exit;
    slot := FileHandle - 1;
    if OpenSlots[slot].InUse then begin
        OpenSlots[slot].InUse := false;
        rd_CloseFile := true;
    end;
end;

function rd_GetDirectories(Handle : uint32; Path : pchar) : PHashMap;
var
    ht : PHashMap;
    i  : uint32;
begin
    ht := hashmap.new();
    for i := 0 to MAX_RAM_FILES - 1 do begin
        if Files[i].Used then
            hashmap.add(ht, stringCopy(Files[i].Name), nil);
    end;
    rd_GetDirectories := ht;
end;

function rd_MakeDirectory(Handle : uint32; Path : pchar) : TError;
begin
    rd_MakeDirectory := eUnknown; { not supported }
end;

function rd_WriteFile(Handle : uint32; FileHandle : TFileHandle;
                      Position : uint32; Buffer : puint8;
                      Length : uint32) : uint32;
begin
    rd_WriteFile := 0; { read-only for now }
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
    tracer.push_trace('ramdrive.init');
    syslog.logln('RAMDRIVE', 'INIT BEGIN.');

    { Zero all slots }
    for i := 0 to MAX_RAM_FILES - 1 do begin
        Files[i].Used := false;
        Files[i].Name := nil;
        Files[i].Data := nil;
        Files[i].Size := 0;
    end;
    for i := 0 to MAX_OPEN_SLOTS - 1 do begin
        OpenSlots[i].InUse := false;
    end;
    FileCount := 0;

    { Register with VFS as /disk/ram }
    vfs.registerDrive(
        0,
        'ram',
        @rd_MakeDirectory,
        @rd_GetDirectories,
        @rd_OpenFile,
        @rd_CloseFile,
        @rd_ReadFile,
        @rd_WriteFile,
        @rd_FileSize,
        @rd_PathValid
    );

    { Pre-load built-in WASM programs }
    loadBuiltins;

    syslog.logln('RAMDRIVE', 'INIT END.');
end;

end.
