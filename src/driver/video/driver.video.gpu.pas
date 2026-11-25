{
    GPU - GPU Driver Abstraction Layer.

    Provides a unified interface for display mode switching across different
    GPU backends (BGA, VBE/VESA, future: VMware SVGA, VirtIO GPU, Intel i915).

    The framework maintains a priority-ordered list of GPU drivers. When
    setMode is called, it tries each registered driver in priority order
    until one succeeds. Drivers self-register during init.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.video.gpu;

interface

uses
    boot.mgr,
    core.util,
    arch.x86.util,
    io.syslog,
    debug.tracer,
    core.strings;

const
    GPU_MAX_DRIVERS    = 8;
    GPU_MAX_CALLBACKS  = 8;

type
    { Mode info returned by a GPU driver }
    TGPUModeInfo = record
        Width       : uint32;
        Height      : uint32;
        BPP         : uint8;
        Framebuffer : uint32; { physical address of linear framebuffer }
        Pitch       : uint32; { bytes per scanline }
    end;
    PGPUModeInfo = ^TGPUModeInfo;

    { Function signature for GPU driver mode setting }
    TGPUSetMode     = function(width, height : uint32; bpp : uint8; var info : TGPUModeInfo) : boolean;

    TGPUVisitMode = procedure(width, height : uint32; bpp : uint8);
    TGPUEnumerateModes = procedure(visit : TGPUVisitMode);

    { Callback invoked after a successful mode change }
    TGPUModeChangeCallback = procedure(const info : TGPUModeInfo);

    { A registered GPU driver }
    TGPUDriver = record
        Name      : pchar;    { Human-readable name, e.g. 'BGA', 'VBE' }
        Priority  : uint8;    { Lower = tried first. BGA=10, VBE=50 }
        SetMode   : TGPUSetMode;
        EnumerateModes : TGPUEnumerateModes;
        Available : boolean;  { Has this driver been loaded/detected? }
    end;
    PGPUDriver = ^TGPUDriver;

{ Register a GPU driver. Called by individual driver units during their init. }
procedure registerDriver(name : pchar; priority : uint8; setModeFn : TGPUSetMode;
                         enumerateFn : TGPUEnumerateModes);

{ Mark a registered driver as available. Called by drivers when they are
  successfully loaded (e.g. via driver.mgr driver.bus.pci match, or self-detect). }
procedure markAvailable(name : pchar);

{ Try to set a display mode using the best available driver.
  Returns true on success; info is filled with framebuffer details. }
function setMode(width, height : uint32; bpp : uint8; var info : TGPUModeInfo) : boolean;

{ Apply the configured mode using the normal driver priority order. }
procedure ApplyRegistryMode;
function IsDesktopMode(width, height : uint32; bpp : uint8) : Boolean;

{ Register a callback to be notified after any successful mode change.
  Callbacks fire in registration order, after the mode has been set. }
procedure registerModeChangeCallback(cb : TGPUModeChangeCallback);

{ Get the name of the currently active GPU driver (last successful setMode). }
function activeDriverName : pchar;

{ Initialize the GPU framework. }
procedure init;

implementation

uses
    driver.storage.vfs,
    driver.storage.types,
    memory.heap;

type
    PDisplayMode = ^TDisplayMode;
    TDisplayMode = record
        Next : PDisplayMode;
        Width, Height : uint32;
        BPP : uint8;
    end;

var
    modeList : PDisplayMode;
    modeCount, modeFileSize : uint32;
    modeFile : PChar;
    Drivers       : array[0..GPU_MAX_DRIVERS - 1] of TGPUDriver;
    DriverCount   : uint8;
    ActiveName    : pchar;
    Callbacks     : array[0..GPU_MAX_CALLBACKS - 1] of TGPUModeChangeCallback;
    CallbackCount : uint8;

procedure init;
var
    i : uint8;
begin
    push_trace('driver.video.gpu.init');
    io.syslog.logln('GPU', 'INIT BEGIN.');
    DriverCount := 0;
    CallbackCount := 0;
    ActiveName := nil;
    for i := 0 to GPU_MAX_CALLBACKS - 1 do
        Callbacks[i] := nil;
    for i := 0 to GPU_MAX_DRIVERS - 1 do begin
        Drivers[i].Name := nil;
        Drivers[i].Priority := 255;
        Drivers[i].SetMode := nil;
        Drivers[i].EnumerateModes := nil;
        Drivers[i].Available := false;
    end;
    io.syslog.logln('GPU', 'INIT END.');
    pop_trace;
end;

procedure registerDriver(name : pchar; priority : uint8; setModeFn : TGPUSetMode;
                         enumerateFn : TGPUEnumerateModes);
var
    i, j : uint8;
begin
    push_trace('driver.video.gpu.registerDriver');
    if DriverCount >= GPU_MAX_DRIVERS then begin
        io.syslog.logln('GPU', 'ERROR: Max GPU drivers reached.');
        pop_trace;
        exit;
    end;

    { Insert sorted by priority (lower = higher priority) }
    i := DriverCount;
    while (i > 0) and (Drivers[i - 1].Priority > priority) do begin
        Drivers[i] := Drivers[i - 1];
        i := i - 1;
    end;

    Drivers[i].Name := name;
    Drivers[i].Priority := priority;
    Drivers[i].SetMode := setModeFn;
    Drivers[i].EnumerateModes := enumerateFn;
    Drivers[i].Available := false;
    DriverCount := DriverCount + 1;

    io.syslog.log('GPU', 'Registered driver: ');
    io.syslog.writestring(name);
    io.syslog.writestring(' (priority ');
    io.syslog.writeint(priority);
    io.syslog.writestringln(')');
    pop_trace;
end;

procedure markAvailable(name : pchar);
var
    i : uint8;
begin
    push_trace('driver.video.gpu.markAvailable');
    for i := 0 to DriverCount - 1 do begin
        if core.strings.stringEquals(Drivers[i].Name, name) then begin
            Drivers[i].Available := true;
            { If no driver is active yet, default to this one }
            if ActiveName = nil then
                ActiveName := name;
            io.syslog.log('GPU', 'Driver now available: ');
            io.syslog.writestringln(name);
            pop_trace;
            exit;
        end;
    end;
    io.syslog.log('GPU', 'WARNING: markAvailable called for unknown driver: ');
    io.syslog.writestringln(name);
    pop_trace;
end;

procedure registerModeChangeCallback(cb : TGPUModeChangeCallback);
begin
    push_trace('driver.video.gpu.registerModeChangeCallback');
    if CallbackCount >= GPU_MAX_CALLBACKS then begin
        io.syslog.logln('GPU', 'ERROR: Max mode-change callbacks reached.');
        pop_trace;
        exit;
    end;
    Callbacks[CallbackCount] := cb;
    CallbackCount := CallbackCount + 1;
    io.syslog.log('GPU', 'Mode-change callback registered (');
    io.syslog.writeint(CallbackCount);
    io.syslog.writestringln(' total).');
    pop_trace;
end;

procedure fireModeChangeCallbacks(const info : TGPUModeInfo);
var
    i : uint8;
begin
    for i := 0 to CallbackCount - 1 do begin
        if Callbacks[i] <> nil then
            Callbacks[i](info);
    end;
end;

function setMode(
    width, height : uint32;
    bpp : uint8;
    var info : TGPUModeInfo
) : boolean;
var
    i : uint8;
begin
    push_trace('driver.video.gpu.setMode');
    setMode := false;

    i := 0;
    while i < DriverCount do begin
        if Drivers[i].Available and (Drivers[i].SetMode <> nil) then begin
            io.syslog.log('GPU', 'Trying ');
            io.syslog.writestring(Drivers[i].Name);
            io.syslog.writestring(' for ');
            io.syslog.writeint(width);
            io.syslog.writestring('x');
            io.syslog.writeint(height);
            io.syslog.writestring('x');
            io.syslog.writeintln(bpp);

            if Drivers[i].SetMode(width, height, bpp, info) then begin
                ActiveName := Drivers[i].Name;
                io.syslog.log('GPU', 'Mode set successfully via ');
                io.syslog.writestringln(Drivers[i].Name);
                setMode := true;
                fireModeChangeCallbacks(info);
                pop_trace;
                exit;
            end else begin
                io.syslog.log('GPU', 'Failed via ');
                io.syslog.writestringln(Drivers[i].Name);
            end;
        end;
        Inc(i);
    end;

    io.syslog.logln('GPU', 'No driver could set the requested mode.');
    pop_trace;
end;

function ReadModeValue(
    base, key, legacyKey : PChar;
    expectedSize : uint32;
    var value : uint32
) : boolean;
var
    path : PChar;
    handle : TFileHandle;
    error : TError;
    bytes : array[0..3] of uint8;
    size : uint32;
begin
    ReadModeValue := false;
    path := stringConcat(base, key);
    handle := OpenFile(path, omRead, @error);
    kfree(void(path));
    if handle = 0 then begin
        path := stringConcat(base, legacyKey);
        handle := OpenFile(path, omRead, @error);
        kfree(void(path));
        expectedSize := SizeOf(bytes);
    end;
    if handle = 0 then exit;

    size := FileSizeFromHandle(handle);
    if size = expectedSize then begin
        bytes[1] := 0;
        bytes[2] := 0;
        bytes[3] := 0;
        if ReadFile(handle, 0, @bytes[0], size) = size then begin
            value := uint32(bytes[0]) or (uint32(bytes[1]) shl 8) or
                     (uint32(bytes[2]) shl 16) or (uint32(bytes[3]) shl 24);
            ReadModeValue := true;
        end;
    end;
    CloseFile(handle);
end;

function IsDesktopMode(width, height : uint32; bpp : uint8) : Boolean;
begin
    IsDesktopMode := (width <> 0) and (height <> 0) and
                     (width <= $FFFF) and (height <= $FFFF) and
                     ((bpp = 16) or (bpp = 32));
end;

procedure AddDisplayMode(width, height : uint32; bpp : uint8);
var
    slot : ^PDisplayMode;
    current, entry : PDisplayMode;
begin
    if not IsDesktopMode(width, height, bpp) then exit;
    slot := @modeList;
    current := slot^;
    while current <> nil do begin
        if (width = current^.Width) and (height = current^.Height)
            and (bpp = current^.BPP) then exit;
        if (width < current^.Width) or
           ((width = current^.Width) and (height < current^.Height)) or
           ((width = current^.Width) and (height = current^.Height)
            and (bpp < current^.BPP)) then break;
        slot := @current^.Next;
        current := slot^;
    end;
    entry := PDisplayMode(kalloc(SizeOf(TDisplayMode)));
    entry^.Width := width;
    entry^.Height := height;
    entry^.BPP := bpp;
    entry^.Next := current;
    slot^ := entry;
    Inc(modeCount);
end;

procedure AppendModeField(value : uint32; separator : Char);
var
    digits : PChar;
    length : uint32;
begin
    digits := intToString(value);
    length := stringSize(digits);
    memcpy(uint32(digits), uint32(@modeFile[modeFileSize]), length);
    kfree(void(digits));
    Inc(modeFileSize, length);
    modeFile[modeFileSize] := separator;
    Inc(modeFileSize);
end;

function ReadDisplayModes(data : Pointer; offset : uint32; buffer : PUInt8;
                          length : uint32) : uint32;
begin
    ReadDisplayModes := 0;
    if offset >= modeFileSize then exit;
    if length > modeFileSize - offset then length := modeFileSize - offset;
    memcpy(uint32(@modeFile[offset]), uint32(buffer), length);
    ReadDisplayModes := length;
end;

function DisplayModesSize(data : Pointer) : uint32;
begin
    DisplayModesSize := modeFileSize;
end;

procedure PublishDisplayModes;
var
    i : uint8;
    mode : PDisplayMode;
    ops : TVFSDeviceOps;
begin
    if PathValid('/dev/video') <> pvDirectory then
        if newVirtualDirectory('/dev/video') <> eNone then exit;
    if PathValid('/dev/video/gpu') <> pvDirectory then
        if newVirtualDirectory('/dev/video/gpu') <> eNone then exit;

    i := 0;
    while i < DriverCount do begin
        if Drivers[i].Available and (Drivers[i].EnumerateModes <> nil) then
            Drivers[i].EnumerateModes(@AddDisplayMode);
        Inc(i);
    end;

    { Two 16-bit dimensions, one two-digit depth, and three separators. }
    if modeCount <> 0 then modeFile := PChar(kalloc(modeCount * 15));
    while modeList <> nil do begin
        mode := modeList;
        modeList := mode^.Next;
        AppendModeField(mode^.Width, ' ');
        AppendModeField(mode^.Height, ' ');
        AppendModeField(mode^.BPP, #10);
        kfree(void(mode));
    end;

    ops.Read := @ReadDisplayModes;
    ops.Write := nil;
    ops.Size := @DisplayModesSize;
    if RegisterDevice('/dev/video/gpu/modes', @ops, nil) <> eNone then
        io.syslog.logln('GPU', 'Could not publish display modes.');
end;

procedure ApplyRegistryMode;
const
    MODE_PATH = '/cfg/asuro/driver/video/gpu';
var
    width, height, bpp : uint32;
    complete : boolean;
    info : TGPUModeInfo;
begin
    if PathValid(MODE_PATH) <> pvDirectory then exit;
    complete := ReadModeValue(MODE_PATH, '/resolution/width.u32',
                              '/resolution/width', 4, width) and
                ReadModeValue(MODE_PATH, '/resolution/height.u32',
                              '/resolution/height', 4, height) and
                ReadModeValue(MODE_PATH, '/bpp.u8', '/bpp', 1, bpp);

    if not complete then begin
        io.syslog.logln('GPU', 'Registry display mode is missing or incomplete.');
        exit;
    end;
    if (bpp > High(uint8)) or not IsDesktopMode(width, height, uint8(bpp)) then begin
        io.syslog.logln('GPU', 'Registry display mode is invalid for the desktop.');
        exit;
    end;

    if not setMode(width, height, uint8(bpp), info) then
        io.syslog.logln('GPU', 'Could not apply the registry display mode.');
end;

function activeDriverName : pchar;
begin
    if ActiveName <> nil then
        activeDriverName := ActiveName
    else
        activeDriverName := 'none';
end;

initialization
    boot.mgr.registerBoot('driver.video.gpu', @init, 'GPU Driver Framework Initialization', 'driver.mgr');
    boot.mgr.registerBoot('gpu.modes', @PublishDisplayModes,
                          'Publish Display Modes', 'driver.bus.pci');

end.
