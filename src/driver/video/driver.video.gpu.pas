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
    core.util, arch.x86.util, io.syslog, debug.tracer, core.strings;

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

    { Callback invoked after a successful mode change }
    TGPUModeChangeCallback = procedure(const info : TGPUModeInfo);

    { A registered GPU driver }
    TGPUDriver = record
        Name      : pchar;    { Human-readable name, e.g. 'BGA', 'VBE' }
        Priority  : uint8;    { Lower = tried first. BGA=10, VBE=50 }
        SetMode   : TGPUSetMode;
        Available : boolean;  { Has this driver been loaded/detected? }
    end;
    PGPUDriver = ^TGPUDriver;

{ Register a GPU driver. Called by individual driver units during their init. }
procedure registerDriver(name : pchar; priority : uint8; setModeFn : TGPUSetMode);

{ Mark a registered driver as available. Called by drivers when they are
  successfully loaded (e.g. via driver.mgr driver.bus.pci match, or self-detect). }
procedure markAvailable(name : pchar);

{ Try to set a display mode using the best available driver.
  Returns true on success; info is filled with framebuffer details. }
function setMode(width, height : uint32; bpp : uint8; var info : TGPUModeInfo) : boolean;

{ Register a callback to be notified after any successful mode change.
  Callbacks fire in registration order, after the mode has been set. }
procedure registerModeChangeCallback(cb : TGPUModeChangeCallback);

{ Get the name of the currently active GPU driver (last successful setMode). }
function activeDriverName : pchar;

{ Initialize the GPU framework. }
procedure init;

implementation

var
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
        Drivers[i].Available := false;
    end;
    io.syslog.logln('GPU', 'INIT END.');
    pop_trace;
end;

procedure registerDriver(name : pchar; priority : uint8; setModeFn : TGPUSetMode);
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

function setMode(width, height : uint32; bpp : uint8; var info : TGPUModeInfo) : boolean;
var
    i : uint8;
begin
    push_trace('driver.video.gpu.setMode');
    setMode := false;

    for i := 0 to DriverCount - 1 do begin
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
    end;

    io.syslog.logln('GPU', 'No driver could set the requested mode.');
    pop_trace;
end;

function activeDriverName : pchar;
begin
    if ActiveName <> nil then
        activeDriverName := ActiveName
    else
        activeDriverName := 'none';
end;

end.
