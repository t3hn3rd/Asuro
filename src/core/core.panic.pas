{
    core.panic - Architecture-agnostic kernel panic (BSOD) engine.

    The BSOD screen and all its widgets are pre-created at init time
    so that NO LVGL allocation is needed when a panic fires.
    At panic time we only update label text (via lv_label_set_text),
    switch to the pre-built screen, and render.

    Layout:
      Top banner   — teapot TGA image + title/subtitle text
      Content area — two-column:
        Left column  : Fault Details, CPU Registers, System Info
        Right column : Call Stack (full height)

    All diagnostic sections (Fault Info, CPU Registers, Process Info,
    System Info, Call Stack) are mirrored to syslog (serial) for
    headless debugging.

    If the panic occurs inside the gfxd graphics-rendering process,
    LVGL state may be corrupt; the unit falls back to rendering the
    panic screen directly to the VESA framebuffer using the bitmap
    font from core.gfx.fonts.

    If called before LVGL has been initialized (early boot panics),
    we gracefully fall back to syslog-only output.

    Architecture-specific code should:
      1. Call registerHaltProc() at init to register a CPU halt routine.
      2. Build a TRegisterSnapshot from saved interrupt state.
      3. Call panic() with the snapshot.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit core.panic;

interface

const
    { Maximum number of register entries an architecture can supply. }
    MAX_REGISTER_ENTRIES = 32;

    { Size of the text buffer for formatting register/trace text. }
    PANIC_TEXT_BUF_SIZE = 2048;

type
    { A single name/value pair representing one CPU register. }
    TRegisterEntry = record
        Name  : pchar;    { Static string, e.g. 'EAX' — must be a literal or persistent pointer }
        Value : uint32;
    end;

    { A snapshot of CPU register state at the time of a fault. }
    PRegisterSnapshot = ^TRegisterSnapshot;
    TRegisterSnapshot = record
        Count   : uint32;
        Entries : array[0..MAX_REGISTER_ENTRIES-1] of TRegisterEntry;
    end;

    { Procedure type for the architecture-specific halt routine. }
    THaltProc = procedure;

{ Create the hidden BSOD LVGL screen. Call once after LVGL is initialized. }
procedure init;

{ Trigger a kernel panic. Outputs to syslog, displays the BSOD screen
  (if available), and halts the system.
  @param fault  Short identifier for the fault (e.g. 'arch.x86.fault.gpf')
  @param info   Human-readable description of the fault
  @param regs   Pointer to a register snapshot, or nil if unavailable }
procedure panic(fault : pchar; info : pchar; regs : PRegisterSnapshot);

{ Register the architecture-specific halt procedure.
  Must be called before any panic can occur. }
procedure registerHaltProc(proc : THaltProc);

implementation

uses    
    io.syslog,
    debug.tracer,
    driver.video,
    memory.heap,
    driver.video.lvgl,
    core.version,
    proc.mgr,
    proc.types,
    core.fmt.targa,
    core.gfx.texture,
    core.strings,
    core.gfx.color;

{ ====================================================================
  Hex formatting helpers — we cannot rely on runtime string formatting
  in a bare-metal panic context, so we roll our own into a static buf.
  ==================================================================== }

const
    HexDigits : array[0..15] of char = '0123456789ABCDEF';

{ Write a uint32 as 8 hex digits into buf at offset. Returns new offset. }
function writeHexToBuffer(buf : pchar; offset : uint32; value : uint32) : uint32;
var
    i : uint32;
begin
    for i := 0 to 7 do begin
        buf[offset + i] := HexDigits[(value SHR (28 - i * 4)) AND $F];
    end;
    writeHexToBuffer := offset + 8;
end;

{ Write a pchar string into buf at offset. Returns new offset. }
function writeStrToBuffer(buf : pchar; offset : uint32; str : pchar) : uint32;
var
    i : uint32;
begin
    i := 0;
    while str[i] <> #0 do begin
        buf[offset] := str[i];
        Inc(offset);
        Inc(i);
    end;
    writeStrToBuffer := offset;
end;

{ Write a single char into buf at offset. Returns new offset. }
function writeCharToBuffer(buf : pchar; offset : uint32; c : char) : uint32;
begin
    buf[offset] := c;
    writeCharToBuffer := offset + 1;
end;

{ Write an integer (for trace indices) into buf at offset. Returns new offset. }
function writeIntToBuffer(buf : pchar; offset : uint32; value : uint32) : uint32;
var
    digits : array[0..9] of char;
    count  : uint32;
    tmp    : uint32;
    i      : uint32;
begin
    if value = 0 then begin
        buf[offset] := '0';
        writeIntToBuffer := offset + 1;
        exit;
    end;
    count := 0;
    tmp := value;
    while tmp > 0 do begin
        digits[count] := char((tmp mod 10) + ord('0'));
        tmp := tmp div 10;
        Inc(count);
    end;
    { Write digits in reverse order }
    for i := 0 to count - 1 do begin
        buf[offset + i] := digits[count - 1 - i];
    end;
    writeIntToBuffer := offset + count;
end;

{ Null-terminate the buffer at offset. }
procedure terminateBuffer(buf : pchar; offset : uint32);
begin
    buf[offset] := #0;
end;

{ ====================================================================
  TGA image types — replicated from boot.splash so we stay
  self-contained (boot.splash does not export these).
  ==================================================================== }

const
    LV_IMAGE_HEADER_MAGIC = $19;
    LV_CF_ARGB8888        = $10;

type
    TLVImageHeader = packed record
        magic_cf_flags : uint32;  { magic:8 | cf:8 | flags:16 }
        w_h            : uint32;  { w:16 | h:16 }
        stride_res     : uint32;  { stride:16 | reserved:16 }
    end;

    TLVImageDsc = packed record
        header    : TLVImageHeader;
        data_size : uint32;
        data      : pointer;
        reserved  : pointer;
    end;
    PLVImageDsc = ^TLVImageDsc;

{ ====================================================================
  Embedded teapot TGA — linked from splash_tga.asm incbin stub.
  ==================================================================== }

var
    panic_tga_start : uint8;  external name '_panic_tga_start';
    panic_tga_size  : uint32; external name '_panic_tga_size';

{ ====================================================================
  Module state
  ==================================================================== }

var
    { Whether the BSOD screen has been built. Set by init(). }
    ScreenReady : boolean;

    { Re-entrancy guard — if panic faults during rendering, halt immediately. }
    PanicInProgress : boolean;

    { Architecture-specific halt procedure. }
    HaltProc : THaltProc;

    { Pre-allocated text buffers for fault, register, trace, and system content.
      These survive the entire kernel lifetime so it is safe to
      point LVGL labels at them via lv_label_set_text. }
    faultTextBuf   : pchar;
    regTextBuf     : pchar;
    traceTextBuf   : pchar;
    systemTextBuf  : pchar;
    processTextBuf : pchar;

    { Pre-created LVGL widgets — built once at init(), never freed. }
    bsodScreen   : Plv_obj;
    faultLabel   : Plv_obj;
    regLabel     : Plv_obj;
    traceLabel   : Plv_obj;
    systemLabel  : Plv_obj;
    processLabel : Plv_obj;

    { Decoded teapot texture and LVGL image descriptor. }
    panicTexture : PTexture;
    panicDsc     : PLVImageDsc;

{ ====================================================================
  Syslog output — mirrors the original serial BSOD format
  ==================================================================== }

procedure syslogDump(fault : pchar; info : pchar; regs : PRegisterSnapshot);
var
    trace    : pchar;
    i        : uint32;
    ctx      : PProcessContext;
    stateStr : pchar;
    heapFree : uint32;
    heapPages: uint32;
    procs    : uint32;
    ticks    : uint32;
begin
    io.syslog.writestringln('=== KERNEL PANIC ===');
    io.syslog.writestringln('ASURO DID A WHOOPSIE!  :(');
    io.syslog.writestringln(' ');
    io.syslog.writestringln('Asuro encountered an error and your computer is now a teapot.');
    io.syslog.writestringln('Your data is almost certainly safe.');
    io.syslog.writestringln(' ');
    io.syslog.writestringln('Details of the fault (for those boring enough to read) are as follows: ');
    io.syslog.writestringln(' ');
    io.syslog.writestring('Fault ID:   ');
    io.syslog.writestringln(fault);
    io.syslog.writestring('Fault Info: ');
    io.syslog.writestringln(info);
    io.syslog.writestringln(' ');

    { Register dump }
    if (regs <> nil) and (regs^.Count > 0) then begin
        io.syslog.writestringln('Processor Info: ');
        for i := 0 to regs^.Count - 1 do begin
            io.syslog.writestring('   ');
            io.syslog.writestring(regs^.Entries[i].Name);
            io.syslog.writestring(': ');
            io.syslog.writehex(regs^.Entries[i].Value);
            { Three registers per line }
            if (i mod 3) = 2 then
                io.syslog.writestringln('')
            else
                io.syslog.writestring('  ');
        end;
        { Finish the last line if it was not a multiple of 3 }
        if (regs^.Count mod 3) <> 0 then
            io.syslog.writestringln('');
        io.syslog.writestringln(' ');
    end;

    { Process info }
    ctx := proc.mgr.CurrentProcess;
    io.syslog.writestringln('Process Info: ');
    if ctx <> nil then begin
        io.syslog.writestring('   Name     : ');
        io.syslog.writestringln(@ctx^.Name[0]);
        io.syslog.writestring('   PID      : ');
        io.syslog.writeintln(ctx^.ProcessID);
        io.syslog.writestring('   Parent   : ');
        io.syslog.writeintln(ctx^.ParentID);
        case ctx^.State of
            psCreated:   stateStr := 'Created';
            psRunning:   stateStr := 'Running';
            psReady:     stateStr := 'Ready';
            psSuspended: stateStr := 'Suspended';
            psAwaiting:  stateStr := 'Awaiting';
            psFinished:  stateStr := 'Finished';
            psError:     stateStr := 'Error';
        else
            stateStr := 'Unknown';
        end;
        io.syslog.writestring('   State    : ');
        io.syslog.writestringln(stateStr);
        io.syslog.writestring('   Priority : ');
        io.syslog.writeintln(ctx^.Priority);
    end else begin
        io.syslog.writestringln('   None');
    end;
    io.syslog.writestringln(' ');

    { System info }
    io.syslog.writestringln('System Info: ');
    io.syslog.writestring('   Kernel    : Asuro ');
    io.syslog.writestringln(VERSION);
    io.syslog.writestring('   Built     : ');
    io.syslog.writestring(COMPILE_DATE);
    io.syslog.writestring(' ');
    io.syslog.writestringln(COMPILE_TIME);
    io.syslog.writestring('   Compiler  : FPC ');
    io.syslog.writestringln(FPC_VERSION);
    io.syslog.writestring('   Revision  : ');
    io.syslog.writestringln(REVISION);
    heapFree := lmm_total_free;
    heapPages := lmm_page_count;
    io.syslog.writestring('   Heap      : ');
    io.syslog.writeint(heapFree div 1024);
    io.syslog.writestring(' KiB free (');
    io.syslog.writeint(heapPages);
    io.syslog.writestringln(' pages)');
    procs := proc.mgr.processCount;
    io.syslog.writestring('   Processes : ');
    io.syslog.writeintln(procs);
    ticks := lvgl_get_ticks;
    io.syslog.writestring('   Uptime    : ');
    io.syslog.writeint(ticks div 1000);
    io.syslog.writestringln('s');
    io.syslog.writestringln(' ');

    { Call stack }
    debug.tracer.freeze;
    io.syslog.writestring('Call Stack:     ');
    trace := debug.tracer.get_last_trace;
    if trace <> nil then begin
        io.syslog.writestring('[-0] ');
        io.syslog.writestringln(trace);
        for i := 1 to debug.tracer.get_trace_count - 1 do begin
            trace := debug.tracer.get_trace_N(i);
            io.syslog.writestring('                [-');
            io.syslog.writeint(i);
            io.syslog.writestring('] ');
            if trace <> nil then
                io.syslog.writestringln(trace)
            else
                io.syslog.writestringln('?????????');
        end;
    end else begin
        io.syslog.writestringln('Unknown.');
    end;
    io.syslog.writestringln('=== END KERNEL PANIC ===');
end;

{ ====================================================================
  LVGL screen population
  ==================================================================== }

{ Write a string into buf, right-padded with spaces to exactly padTo chars.
  If the string is longer than padTo it is not truncated. }
function writeStrPaddedToBuffer(buf : pchar; offset : uint32;
                                 str : pchar; padTo : uint32) : uint32;
var
    i   : uint32;
    len : uint32;
begin
    len := 0;
    while str[len] <> #0 do Inc(len);
    offset := writeStrToBuffer(buf, offset, str);
    if len < padTo then begin
        for i := len to padTo - 1 do
            offset := writeCharToBuffer(buf, offset, ' ');
    end;
    writeStrPaddedToBuffer := offset;
end;

{ Format the register snapshot into regTextBuf for display.
  Each register name is padded to a fixed width so columns align. }
procedure formatRegisters(regs : PRegisterSnapshot);
var
    offset  : uint32;
    i       : uint32;
    maxLen  : uint32;
    nameLen : uint32;
begin
    offset := 0;
    if (regs = nil) or (regs^.Count = 0) then begin
        offset := writeStrToBuffer(regTextBuf, offset, 'No register data available.');
        terminateBuffer(regTextBuf, offset);
        exit;
    end;

    { Find the longest register name so we can pad them all equally }
    maxLen := 0;
    for i := 0 to regs^.Count - 1 do begin
        nameLen := 0;
        while regs^.Entries[i].Name[nameLen] <> #0 do Inc(nameLen);
        if nameLen > maxLen then maxLen := nameLen;
    end;

    for i := 0 to regs^.Count - 1 do begin
        { Newline before each new row (not before the first) }
        if (i > 0) and ((i mod 3) = 0) then
            offset := writeCharToBuffer(regTextBuf, offset, #10);

        { Register name, right-padded to the longest name width }
        offset := writeStrPaddedToBuffer(regTextBuf, offset,
                                         regs^.Entries[i].Name, maxLen);
        offset := writeStrToBuffer(regTextBuf, offset, ': ');
        offset := writeHexToBuffer(regTextBuf, offset, regs^.Entries[i].Value);

        { Spacing between registers on the same line }
        if ((i mod 3) <> 2) and (i < regs^.Count - 1) then
            offset := writeStrToBuffer(regTextBuf, offset, '   ');
    end;

    terminateBuffer(regTextBuf, offset);
end;

{ Format the tracer call stack into traceTextBuf for display. }
procedure formatTraceLog;
var
    offset : uint32;
    trace  : pchar;
    count  : uint32;
    i      : uint32;
begin
    offset := 0;
    count := debug.tracer.get_trace_count;

    trace := debug.tracer.get_last_trace;
    if trace = nil then begin
        offset := writeStrToBuffer(traceTextBuf, offset, 'No trace data available.');
        terminateBuffer(traceTextBuf, offset);
        exit;
    end;

    { Most recent trace first }
    offset := writeStrToBuffer(traceTextBuf, offset, '[-0] ');
    offset := writeStrToBuffer(traceTextBuf, offset, trace);

    for i := 1 to count - 1 do begin
        { Newline before each subsequent entry (not after the last) }
        offset := writeCharToBuffer(traceTextBuf, offset, #10);

        trace := debug.tracer.get_trace_N(i);
        offset := writeStrToBuffer(traceTextBuf, offset, '[-');
        offset := writeIntToBuffer(traceTextBuf, offset, i);
        offset := writeStrToBuffer(traceTextBuf, offset, '] ');
        if trace <> nil then
            offset := writeStrToBuffer(traceTextBuf, offset, trace)
        else
            offset := writeStrToBuffer(traceTextBuf, offset, '?????????');

        { Safety: do not overflow the buffer }
        if offset > (PANIC_TEXT_BUF_SIZE - 64) then break;
    end;

    terminateBuffer(traceTextBuf, offset);
end;

{ Format process information into processTextBuf.
  Shows the currently running process at the time of the panic,
  or 'None' if no process was active / proc.mgr not initialized. }
procedure formatProcessInfo;
var
    offset : uint32;
    ctx    : PProcessContext;
    stateStr : pchar;
begin
    offset := 0;
    ctx := proc.mgr.CurrentProcess;

    if ctx = nil then begin
        offset := writeStrToBuffer(processTextBuf, offset, 'None');
        terminateBuffer(processTextBuf, offset);
        exit;
    end;

    { Process name }
    offset := writeStrToBuffer(processTextBuf, offset, 'Name     : ');
    offset := writeStrToBuffer(processTextBuf, offset, @ctx^.Name[0]);
    offset := writeCharToBuffer(processTextBuf, offset, #10);

    { PID }
    offset := writeStrToBuffer(processTextBuf, offset, 'PID      : ');
    offset := writeIntToBuffer(processTextBuf, offset, ctx^.ProcessID);
    offset := writeCharToBuffer(processTextBuf, offset, #10);

    { Parent PID }
    offset := writeStrToBuffer(processTextBuf, offset, 'Parent   : ');
    offset := writeIntToBuffer(processTextBuf, offset, ctx^.ParentID);
    offset := writeCharToBuffer(processTextBuf, offset, #10);

    { State }
    case ctx^.State of
        psCreated:   stateStr := 'Created';
        psRunning:   stateStr := 'Running';
        psReady:     stateStr := 'Ready';
        psSuspended: stateStr := 'Suspended';
        psAwaiting:  stateStr := 'Awaiting';
        psFinished:  stateStr := 'Finished';
        psError:     stateStr := 'Error';
    else
        stateStr := 'Unknown';
    end;
    offset := writeStrToBuffer(processTextBuf, offset, 'State    : ');
    offset := writeStrToBuffer(processTextBuf, offset, stateStr);
    offset := writeCharToBuffer(processTextBuf, offset, #10);

    { Priority }
    offset := writeStrToBuffer(processTextBuf, offset, 'Priority : ');
    offset := writeIntToBuffer(processTextBuf, offset, ctx^.Priority);

    terminateBuffer(processTextBuf, offset);
end;

{ Format system diagnostic information into systemTextBuf. }
procedure formatSystemInfo;
var
    offset    : uint32;
    heapFree  : uint32;
    heapPages : uint32;
    procs     : uint32;
    ticks     : uint32;
begin
    offset := 0;

    { Kernel version }
    offset := writeStrToBuffer(systemTextBuf, offset, 'Kernel    : Asuro ');
    offset := writeStrToBuffer(systemTextBuf, offset, VERSION);
    offset := writeCharToBuffer(systemTextBuf, offset, #10);

    { Build info }
    offset := writeStrToBuffer(systemTextBuf, offset, 'Built     : ');
    offset := writeStrToBuffer(systemTextBuf, offset, COMPILE_DATE);
    offset := writeStrToBuffer(systemTextBuf, offset, ' ');
    offset := writeStrToBuffer(systemTextBuf, offset, COMPILE_TIME);
    offset := writeCharToBuffer(systemTextBuf, offset, #10);

    { Compiler }
    offset := writeStrToBuffer(systemTextBuf, offset, 'Compiler  : FPC ');
    offset := writeStrToBuffer(systemTextBuf, offset, FPC_VERSION);
    offset := writeCharToBuffer(systemTextBuf, offset, #10);

    { Revision }
    offset := writeStrToBuffer(systemTextBuf, offset, 'Revision  : ');
    offset := writeStrToBuffer(systemTextBuf, offset, REVISION);
    offset := writeCharToBuffer(systemTextBuf, offset, #10);

    { Heap memory }
    heapFree := lmm_total_free;
    heapPages := lmm_page_count;
    offset := writeStrToBuffer(systemTextBuf, offset, 'Heap      : ');
    offset := writeIntToBuffer(systemTextBuf, offset, heapFree div 1024);
    offset := writeStrToBuffer(systemTextBuf, offset, ' KiB free (');
    offset := writeIntToBuffer(systemTextBuf, offset, heapPages);
    offset := writeStrToBuffer(systemTextBuf, offset, ' pages)');
    offset := writeCharToBuffer(systemTextBuf, offset, #10);

    { Process count }
    procs := proc.mgr.processCount;
    offset := writeStrToBuffer(systemTextBuf, offset, 'Processes : ');
    offset := writeIntToBuffer(systemTextBuf, offset, procs);
    offset := writeCharToBuffer(systemTextBuf, offset, #10);

    { LVGL ticks (uptime proxy) }
    ticks := lvgl_get_ticks;
    offset := writeStrToBuffer(systemTextBuf, offset, 'Uptime    : ');
    offset := writeIntToBuffer(systemTextBuf, offset, ticks div 1000);
    offset := writeStrToBuffer(systemTextBuf, offset, 's');

    terminateBuffer(systemTextBuf, offset);
end;

{ ====================================================================
  VESA fallback — direct framebuffer rendering using driver.video
  text drawing.  Used when gfxd crashes and LVGL state may be corrupt.
  ==================================================================== }

{ Render the full panic screen directly to the VESA framebuffer,
  bypassing LVGL entirely.  Used when gfxd has crashed. }
procedure showVESAFallbackScreen(fault : pchar; info : pchar;
                                 regs : PRegisterSnapshot);
var
    bgColor, textColor, headerColor, dimColor : TRGB32;
    cy, cx       : uint32;
    screenW, screenH : uint32;
    i, count     : uint32;
    trace        : pchar;
    ctx          : PProcessContext;
    stateStr     : pchar;
begin
    screenW := driver.video.frontBufferWidth;
    screenH := driver.video.frontBufferHeight;
    if (screenW = 0) or (screenH = 0) then exit;

    { Colours matching the LVGL BSOD theme }
    bgColor.R     := $7A; bgColor.G     := $28; bgColor.B     := $28; bgColor.A     := $FF;
    textColor.R   := $FF; textColor.G   := $FF; textColor.B   := $FF; textColor.A   := $FF;
    headerColor.R := $FF; headerColor.G := $AA; headerColor.B := $AA; headerColor.A := $FF;
    dimColor.R    := $DD; dimColor.G    := $AA; dimColor.B    := $AA; dimColor.A    := $FF;

    { Fill the entire screen with the background colour }
    driver.video.FillRect(0, 0, screenW - 1, screenH - 1, 0, bgColor, bgColor);

    cy := 16;

    { Title banner }
    driver.video.DrawString(16, cy,
        'Asuro encountered an error and your computer is now a teapot.', textColor);
    cy := cy + 20;
    driver.video.DrawString(16, cy,
        'Don''t worry, your data is almost certainly safe.', dimColor);
    cy := cy + 32;

    { ---- Fault Details ---- }
    driver.video.DrawString(16, cy, '--- Fault Details ---', headerColor);
    cy := cy + 20;
    cx := driver.video.DrawString(16, cy, fault, textColor);
    cx := driver.video.DrawString(cx, cy, ' : ', textColor);
    driver.video.DrawString(cx, cy, info, textColor);
    cy := cy + 28;

    { ---- CPU Registers ---- }
    if (regs <> nil) and (regs^.Count > 0) then begin
        driver.video.DrawString(16, cy, '--- CPU Registers ---', headerColor);
        cy := cy + 20;
        cx := 16;
        for i := 0 to regs^.Count - 1 do begin
            if (i > 0) and ((i mod 3) = 0) then begin
                cy := cy + 18;
                cx := 16;
            end;
            cx := driver.video.DrawString(cx, cy, regs^.Entries[i].Name, textColor);
            cx := driver.video.DrawString(cx, cy, ': ', textColor);
            cx := driver.video.DrawHex(cx, cy, regs^.Entries[i].Value, textColor);
            cx := cx + 24;  { gap between register groups }
        end;
        cy := cy + 28;
    end;

    { ---- Process Info ---- }
    driver.video.DrawString(16, cy, '--- Process Info ---', headerColor);
    cy := cy + 20;
    ctx := proc.mgr.CurrentProcess;
    if ctx <> nil then begin
        cx := driver.video.DrawString(16, cy, 'Name     : ', textColor);
        driver.video.DrawString(cx, cy, @ctx^.Name[0], textColor);
        cy := cy + 18;
        cx := driver.video.DrawString(16, cy, 'PID      : ', textColor);
        driver.video.DrawInt(cx, cy, ctx^.ProcessID, textColor);
        cy := cy + 18;
        cx := driver.video.DrawString(16, cy, 'Parent   : ', textColor);
        driver.video.DrawInt(cx, cy, ctx^.ParentID, textColor);
        cy := cy + 18;
        case ctx^.State of
            psCreated:   stateStr := 'Created';
            psRunning:   stateStr := 'Running';
            psReady:     stateStr := 'Ready';
            psSuspended: stateStr := 'Suspended';
            psAwaiting:  stateStr := 'Awaiting';
            psFinished:  stateStr := 'Finished';
            psError:     stateStr := 'Error';
        else
            stateStr := 'Unknown';
        end;
        cx := driver.video.DrawString(16, cy, 'State    : ', textColor);
        driver.video.DrawString(cx, cy, stateStr, textColor);
        cy := cy + 18;
        cx := driver.video.DrawString(16, cy, 'Priority : ', textColor);
        driver.video.DrawInt(cx, cy, ctx^.Priority, textColor);
    end else begin
        driver.video.DrawString(16, cy, 'None', textColor);
    end;
    cy := cy + 28;

    { ---- System Info ---- }
    driver.video.DrawString(16, cy, '--- System Info ---', headerColor);
    cy := cy + 20;
    cx := driver.video.DrawString(16, cy, 'Kernel    : Asuro ', textColor);
    driver.video.DrawString(cx, cy, VERSION, textColor);
    cy := cy + 18;
    cx := driver.video.DrawString(16, cy, 'Built     : ', textColor);
    cx := driver.video.DrawString(cx, cy, COMPILE_DATE, textColor);
    cx := driver.video.DrawString(cx, cy, ' ', textColor);
    driver.video.DrawString(cx, cy, COMPILE_TIME, textColor);
    cy := cy + 18;
    cx := driver.video.DrawString(16, cy, 'Compiler  : FPC ', textColor);
    driver.video.DrawString(cx, cy, FPC_VERSION, textColor);
    cy := cy + 18;
    cx := driver.video.DrawString(16, cy, 'Revision  : ', textColor);
    driver.video.DrawString(cx, cy, REVISION, textColor);
    cy := cy + 28;

    { ---- Call Stack ---- }
    driver.video.DrawString(16, cy, '--- Call Stack ---', headerColor);
    cy := cy + 20;
    count := debug.tracer.get_trace_count;
    trace := debug.tracer.get_last_trace;
    if trace <> nil then begin
        cx := driver.video.DrawString(16, cy, '[-0] ', textColor);
        driver.video.DrawString(cx, cy, trace, textColor);
        cy := cy + 18;
        for i := 1 to count - 1 do begin
            cx := driver.video.DrawString(16, cy, '[-', textColor);
            cx := driver.video.DrawInt(cx, cy, i, textColor);
            cx := driver.video.DrawString(cx, cy, '] ', textColor);
            trace := debug.tracer.get_trace_N(i);
            if trace <> nil then
                driver.video.DrawString(cx, cy, trace, textColor)
            else
                driver.video.DrawString(cx, cy, '?????????', textColor);
            cy := cy + 18;
            { Stop if we run off the bottom of the screen }
            if cy + 18 > screenH then break;
        end;
    end else begin
        driver.video.DrawString(16, cy, 'No trace data available.', textColor);
    end;

    { Flush the back buffer to the hardware framebuffer }
    driver.video.Flush;
end;

{ Build an lv_image_dsc_t that points to decoded ARGB8888 pixel data. }
function buildImageDsc(tex : PTexture) : PLVImageDsc;
var
    dsc : PLVImageDsc;
begin
    dsc := PLVImageDsc(kalloc(sizeof(TLVImageDsc)));

    { Pack the bitfield header: magic | cf | flags=0 }
    dsc^.header.magic_cf_flags := uint32(LV_IMAGE_HEADER_MAGIC)
                               OR (uint32(LV_CF_ARGB8888) SHL 8);
    { w | h }
    dsc^.header.w_h := uint32(tex^.Width)
                     OR (uint32(tex^.Height) SHL 16);
    { stride = width * 4 bytes per pixel }
    dsc^.header.stride_res := uint32(tex^.Width * 4);

    dsc^.data_size := tex^.Width * tex^.Height * 4;
    dsc^.data      := tex^.Pixels;
    dsc^.reserved  := nil;

    buildImageDsc := dsc;
end;

{ Update the pre-built BSOD screen with fault data and display it.
  All widgets already exist — we only update the four dynamic labels
  and then switch to the screen and force a render. }
procedure showBSODScreen(fault : pchar; info : pchar; regs : PRegisterSnapshot);
var
    off : uint32;
begin
    { Format the combined fault line: "fault.id : Description" }
    off := 0;
    off := writeStrToBuffer(faultTextBuf, off, fault);
    off := writeStrToBuffer(faultTextBuf, off, ' : ');
    off := writeStrToBuffer(faultTextBuf, off, info);
    terminateBuffer(faultTextBuf, off);
    lv_label_set_text(faultLabel, faultTextBuf);

    formatRegisters(regs);
    lv_label_set_text(regLabel, regTextBuf);

    formatTraceLog;
    lv_label_set_text(traceLabel, traceTextBuf);

    formatProcessInfo;
    lv_label_set_text(processLabel, processTextBuf);

    formatSystemInfo;
    lv_label_set_text(systemLabel, systemTextBuf);

    { Switch to the pre-built BSOD screen and render }
    lv_screen_load(bsodScreen);
    lv_refr_now(bsodScreen);
    lv_tick_inc(100);
    lv_timer_handler;
    driver.video.Flush;
end;

{ ====================================================================
  Fallback halt — used if no arch-specific halt was registered.
  Loops forever with nothing to do.
  ==================================================================== }

procedure fallbackHalt;
begin
    while true do begin
        { Infinite loop — last resort if no arch halt registered }
    end;
end;

{ ====================================================================
  Public API
  ==================================================================== }

procedure registerHaltProc(proc : THaltProc);
begin
    HaltProc := proc;
end;

procedure panic(fault : pchar; info : pchar; regs : PRegisterSnapshot);
var
    isGfxdCrash : boolean;
    ctx         : PProcessContext;
begin
    { Re-entrancy guard: if we fault during panic, halt immediately }
    if PanicInProgress then begin
        HaltProc;
        exit;
    end;
    PanicInProgress := true;

    if not BSOD_ENABLE then exit;

    { Freeze the tracer so the call stack is preserved }
    debug.tracer.freeze;

    { Always dump to syslog (serial) }
    syslogDump(fault, info, regs);

    { Check if the crash occurred in the gfxd process — if so, LVGL
      state may be corrupt, so fall back to direct VESA rendering }
    isGfxdCrash := false;
    ctx := proc.mgr.CurrentProcess;
    if ctx <> nil then
        isGfxdCrash := core.strings.stringEquals(@ctx^.Name[0], 'gfxd');

    if isGfxdCrash then
        showVESAFallbackScreen(fault, info, regs)
    else if ScreenReady then
        showBSODScreen(fault, info, regs);

    { Halt the system }
    HaltProc;
end;

procedure init;
var
    topBanner     : Plv_obj;
    teapotImage   : Plv_obj;
    bannerTextCol : Plv_obj;
    titleLabel    : Plv_obj;
    subtitleLabel : Plv_obj;
    contentRow    : Plv_obj;
    leftCol       : Plv_obj;
    rightCol      : Plv_obj;
    faultCard     : Plv_obj;
    faultHeader   : Plv_obj;
    regCard       : Plv_obj;
    regHeader     : Plv_obj;
    procCard      : Plv_obj;
    procHeader    : Plv_obj;
    sysCard       : Plv_obj;
    sysHeader     : Plv_obj;
    traceCard     : Plv_obj;
    traceHeader   : Plv_obj;
begin
    { Allocate text buffers — kernel-heap, persist for system lifetime }
    faultTextBuf := pchar(kalloc(512));
    regTextBuf := pchar(kalloc(PANIC_TEXT_BUF_SIZE));
    traceTextBuf := pchar(kalloc(PANIC_TEXT_BUF_SIZE));
    systemTextBuf := pchar(kalloc(PANIC_TEXT_BUF_SIZE));
    processTextBuf := pchar(kalloc(PANIC_TEXT_BUF_SIZE));
    faultTextBuf[0] := #0;
    regTextBuf[0] := #0;
    traceTextBuf[0] := #0;
    systemTextBuf[0] := #0;
    processTextBuf[0] := #0;

    { Decode the embedded teapot TGA into an ARGB pixel buffer }
    panicTexture := core.fmt.targa.Parse(@panic_tga_start, panic_tga_size);
    panicDsc := nil;
    if panicTexture <> nil then
        panicDsc := buildImageDsc(panicTexture);

    { ---- Create the BSOD screen ---- }
    bsodScreen := lv_obj_create(nil);
    lv_obj_remove_flag(bsodScreen, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_color(bsodScreen, lv_color_hex($7A2828), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(bsodScreen, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_flex_flow(bsodScreen, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(bsodScreen,
                          LV_FLEX_ALIGN_START,
                          LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_all(bsodScreen, 16, LV_PART_MAIN);
    lv_obj_set_style_pad_row(bsodScreen, 10, LV_PART_MAIN);

    { ==== TOP BANNER (row: teapot image + text column, centred) ==== }
    topBanner := lv_obj_create(bsodScreen);
    lv_obj_set_width(topBanner, LV_SIZE_CONTENT);
    lv_obj_set_height(topBanner, LV_SIZE_CONTENT);
    lv_obj_set_style_bg_opa(topBanner, LV_OPA_TRANSP, LV_PART_MAIN);
    lv_obj_set_style_border_width(topBanner, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_all(topBanner, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_column(topBanner, 16, LV_PART_MAIN);
    lv_obj_remove_flag(topBanner, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_flex_flow(topBanner, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(topBanner,
                          LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);

    { Teapot TGA image — decoded at boot, displayed at 50% (128x128) }
    teapotImage := lv_image_create(topBanner);
    if panicDsc <> nil then begin
        lv_image_set_src(teapotImage, panicDsc);
        lv_image_set_scale(teapotImage, 128);  { 128/256 = 50% -> 128x128 }
        lv_image_set_inner_align(teapotImage, LV_IMAGE_ALIGN_CENTER);
        { Force the widget layout size to match the scaled visual size,
          otherwise LVGL uses the source 256x256 and wastes space }
        lv_obj_set_size(teapotImage, 128, 128);
    end;

    { Text column: title + subtitle, vertically centered beside image }
    bannerTextCol := lv_obj_create(topBanner);
    lv_obj_set_width(bannerTextCol, LV_SIZE_CONTENT);
    lv_obj_set_height(bannerTextCol, LV_SIZE_CONTENT);
    lv_obj_set_style_bg_opa(bannerTextCol, LV_OPA_TRANSP, LV_PART_MAIN);
    lv_obj_set_style_border_width(bannerTextCol, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_all(bannerTextCol, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_left(bannerTextCol, 8, LV_PART_MAIN);
    lv_obj_set_style_pad_row(bannerTextCol, 4, LV_PART_MAIN);
    lv_obj_remove_flag(bannerTextCol, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_flex_flow(bannerTextCol, LV_FLEX_FLOW_COLUMN);

    titleLabel := lv_label_create(bannerTextCol);
    lv_label_set_text(titleLabel,
        'Asuro encountered an error and your computer is now a teapot.');
    lv_obj_set_style_text_font(titleLabel, @lv_font_montserrat_14, LV_PART_MAIN);
    lv_obj_set_style_text_color(titleLabel, lv_color_hex($FFFFFF), LV_PART_MAIN);

    subtitleLabel := lv_label_create(bannerTextCol);
    lv_label_set_text(subtitleLabel,
        'Don''t worry, your data is almost certainly safe.');
    lv_obj_set_style_text_font(subtitleLabel, @lv_font_montserrat_14, LV_PART_MAIN);
    lv_obj_set_style_text_color(subtitleLabel, lv_color_hex($DDAAAA), LV_PART_MAIN);

    { ==== CONTENT AREA (two-column row, fills remaining height) ==== }
    contentRow := lv_obj_create(bsodScreen);
    lv_obj_set_width(contentRow, lv_pct(100));
    lv_obj_set_flex_grow(contentRow, 1);
    lv_obj_set_style_bg_opa(contentRow, LV_OPA_TRANSP, LV_PART_MAIN);
    lv_obj_set_style_border_width(contentRow, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_all(contentRow, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_column(contentRow, 12, LV_PART_MAIN);
    lv_obj_remove_flag(contentRow, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_flex_flow(contentRow, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(contentRow,
                          LV_FLEX_ALIGN_START,
                          LV_FLEX_ALIGN_START,
                          LV_FLEX_ALIGN_START);

    { ==== LEFT COLUMN (Fault Details + CPU Registers + System Info) ==== }
    leftCol := lv_obj_create(contentRow);
    lv_obj_set_flex_grow(leftCol, 1);
    lv_obj_set_height(leftCol, lv_pct(100));
    lv_obj_set_style_bg_opa(leftCol, LV_OPA_TRANSP, LV_PART_MAIN);
    lv_obj_set_style_border_width(leftCol, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_all(leftCol, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_row(leftCol, 12, LV_PART_MAIN);
    lv_obj_remove_flag(leftCol, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_flex_flow(leftCol, LV_FLEX_FLOW_COLUMN);

    { -- Fault Details card -- }
    faultCard := lv_obj_create(leftCol);
    lv_obj_set_width(faultCard, lv_pct(100));
    lv_obj_set_height(faultCard, LV_SIZE_CONTENT);
    lv_obj_set_style_bg_color(faultCard, lv_color_hex($000000), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(faultCard, 50, LV_PART_MAIN);
    lv_obj_set_style_radius(faultCard, 8, LV_PART_MAIN);
    lv_obj_set_style_border_width(faultCard, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_all(faultCard, 12, LV_PART_MAIN);
    lv_obj_set_style_pad_row(faultCard, 6, LV_PART_MAIN);
    lv_obj_remove_flag(faultCard, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_flex_flow(faultCard, LV_FLEX_FLOW_COLUMN);

    faultHeader := lv_label_create(faultCard);
    lv_label_set_text(faultHeader, 'Fault Details');
    lv_obj_set_style_text_font(faultHeader, @lv_font_montserrat_14, LV_PART_MAIN);
    lv_obj_set_style_text_color(faultHeader, lv_color_hex($FFAAAA), LV_PART_MAIN);

    faultLabel := lv_label_create(faultCard);
    lv_label_set_text(faultLabel, ' ');
    lv_obj_set_style_text_font(faultLabel, @hack_14, LV_PART_MAIN);
    lv_obj_set_style_text_color(faultLabel, lv_color_hex($FFFFFF), LV_PART_MAIN);

    { -- CPU Registers card -- }
    regCard := lv_obj_create(leftCol);
    lv_obj_set_width(regCard, lv_pct(100));
    lv_obj_set_height(regCard, LV_SIZE_CONTENT);
    lv_obj_set_style_bg_color(regCard, lv_color_hex($000000), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(regCard, 50, LV_PART_MAIN);
    lv_obj_set_style_radius(regCard, 8, LV_PART_MAIN);
    lv_obj_set_style_border_width(regCard, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_all(regCard, 12, LV_PART_MAIN);
    lv_obj_set_style_pad_row(regCard, 6, LV_PART_MAIN);
    lv_obj_remove_flag(regCard, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_flex_flow(regCard, LV_FLEX_FLOW_COLUMN);

    regHeader := lv_label_create(regCard);
    lv_label_set_text(regHeader, 'CPU Registers');
    lv_obj_set_style_text_font(regHeader, @lv_font_montserrat_14, LV_PART_MAIN);
    lv_obj_set_style_text_color(regHeader, lv_color_hex($FFAAAA), LV_PART_MAIN);

    regLabel := lv_label_create(regCard);
    lv_label_set_text(regLabel, ' ');
    lv_obj_set_style_text_font(regLabel, @hack_14, LV_PART_MAIN);
    lv_obj_set_style_text_color(regLabel, lv_color_hex($FFFFFF), LV_PART_MAIN);

    { -- Process Info card -- }
    procCard := lv_obj_create(leftCol);
    lv_obj_set_width(procCard, lv_pct(100));
    lv_obj_set_height(procCard, LV_SIZE_CONTENT);
    lv_obj_set_style_bg_color(procCard, lv_color_hex($000000), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(procCard, 50, LV_PART_MAIN);
    lv_obj_set_style_radius(procCard, 8, LV_PART_MAIN);
    lv_obj_set_style_border_width(procCard, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_all(procCard, 12, LV_PART_MAIN);
    lv_obj_set_style_pad_row(procCard, 6, LV_PART_MAIN);
    lv_obj_remove_flag(procCard, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_flex_flow(procCard, LV_FLEX_FLOW_COLUMN);

    procHeader := lv_label_create(procCard);
    lv_label_set_text(procHeader, 'Process Info');
    lv_obj_set_style_text_font(procHeader, @lv_font_montserrat_14, LV_PART_MAIN);
    lv_obj_set_style_text_color(procHeader, lv_color_hex($FFAAAA), LV_PART_MAIN);

    processLabel := lv_label_create(procCard);
    lv_label_set_text(processLabel, ' ');
    lv_obj_set_style_text_font(processLabel, @hack_14, LV_PART_MAIN);
    lv_obj_set_style_text_color(processLabel, lv_color_hex($FFFFFF), LV_PART_MAIN);

    { -- System Info card -- }
    sysCard := lv_obj_create(leftCol);
    lv_obj_set_width(sysCard, lv_pct(100));
    lv_obj_set_flex_grow(sysCard, 1);
    lv_obj_set_style_bg_color(sysCard, lv_color_hex($000000), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(sysCard, 50, LV_PART_MAIN);
    lv_obj_set_style_radius(sysCard, 8, LV_PART_MAIN);
    lv_obj_set_style_border_width(sysCard, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_all(sysCard, 12, LV_PART_MAIN);
    lv_obj_set_style_pad_row(sysCard, 6, LV_PART_MAIN);
    lv_obj_remove_flag(sysCard, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_flex_flow(sysCard, LV_FLEX_FLOW_COLUMN);

    sysHeader := lv_label_create(sysCard);
    lv_label_set_text(sysHeader, 'System Info');
    lv_obj_set_style_text_font(sysHeader, @lv_font_montserrat_14, LV_PART_MAIN);
    lv_obj_set_style_text_color(sysHeader, lv_color_hex($FFAAAA), LV_PART_MAIN);

    systemLabel := lv_label_create(sysCard);
    lv_label_set_text(systemLabel, ' ');
    lv_obj_set_style_text_font(systemLabel, @hack_14, LV_PART_MAIN);
    lv_obj_set_style_text_color(systemLabel, lv_color_hex($FFFFFF), LV_PART_MAIN);

    { ==== RIGHT COLUMN (Call Stack, full height) ==== }
    rightCol := lv_obj_create(contentRow);
    lv_obj_set_flex_grow(rightCol, 1);
    lv_obj_set_height(rightCol, lv_pct(100));
    lv_obj_set_style_bg_opa(rightCol, LV_OPA_TRANSP, LV_PART_MAIN);
    lv_obj_set_style_border_width(rightCol, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_all(rightCol, 0, LV_PART_MAIN);
    lv_obj_remove_flag(rightCol, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_flex_flow(rightCol, LV_FLEX_FLOW_COLUMN);

    { -- Call Stack card (fills full height of right column) -- }
    traceCard := lv_obj_create(rightCol);
    lv_obj_set_width(traceCard, lv_pct(100));
    lv_obj_set_flex_grow(traceCard, 1);
    lv_obj_set_style_bg_color(traceCard, lv_color_hex($000000), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(traceCard, 50, LV_PART_MAIN);
    lv_obj_set_style_radius(traceCard, 8, LV_PART_MAIN);
    lv_obj_set_style_border_width(traceCard, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_all(traceCard, 12, LV_PART_MAIN);
    lv_obj_set_style_pad_row(traceCard, 6, LV_PART_MAIN);
    lv_obj_remove_flag(traceCard, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_flex_flow(traceCard, LV_FLEX_FLOW_COLUMN);

    traceHeader := lv_label_create(traceCard);
    lv_label_set_text(traceHeader, 'Call Stack');
    lv_obj_set_style_text_font(traceHeader, @lv_font_montserrat_14, LV_PART_MAIN);
    lv_obj_set_style_text_color(traceHeader, lv_color_hex($FFAAAA), LV_PART_MAIN);

    traceLabel := lv_label_create(traceCard);
    lv_label_set_text(traceLabel, ' ');
    lv_obj_set_style_text_font(traceLabel, @hack_14, LV_PART_MAIN);
    lv_obj_set_style_text_color(traceLabel, lv_color_hex($FFFFFF), LV_PART_MAIN);

    { Mark BSOD screen as ready for panic rendering }
    ScreenReady := true;
end;

{ ====================================================================
  Unit initialization — set safe defaults before init() is called.
  ==================================================================== }
begin
    ScreenReady := false;
    PanicInProgress := false;
    HaltProc := @fallbackHalt;
    faultTextBuf := nil;
    regTextBuf := nil;
    traceTextBuf := nil;
    systemTextBuf := nil;
    bsodScreen := nil;
    faultLabel := nil;
    regLabel := nil;
    traceLabel := nil;
    systemLabel := nil;
    panicTexture := nil;
    panicDsc := nil;
end.
