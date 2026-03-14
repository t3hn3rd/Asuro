{
    boot.mgr - Boot Initialization Manager.

    Provides a self-registering, dependency-ordered boot sequence. Units
    register themselves during their Pascal initialization sections by calling
    registerBoot() with a name, an init procedure, a splash-screen status
    message, and an optional dependency name.  boot.mgr.run() performs a
    topological sort on the entries and executes them in dependency order,
    updating the splash screen as it goes.

    Because registration happens before kmain (and therefore before the
    heap exists), all storage is statically allocated.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit boot.mgr;

interface

const
    { Maximum number of boot entries that can be registered.  This is a
      static upper bound sized for the number of kernel units.  If exceeded,
      registration halts the system (fatal misconfiguration). }
    MAX_BOOT_ENTRIES = 128;

const
    { BARRIER_NAMES }
    BOOT_MGR_BARRIER_IMMEDIATE = 'immediate';
    BOOT_MGR_BARRIER_EARLY     = 'early';
    BOOT_MGR_BARRIER_MID       = 'middle';
    BOOT_MGR_BARRIER_STORAGE   = 'storage';
    BOOT_MGR_BARRIER_DEVICE    = 'device';
    BOOT_MGR_BARRIER_BUS       = 'bus';
    BOOT_MGR_BARRIER_BUS_LATE  = 'bus.late';
    BOOT_MGR_BARRIER_LATE      = 'late';
    BOOT_MGR_BARRIER_FINAL     = 'final';

type
    { Parameterless procedure pointer for boot init callbacks }
    TBootProc = procedure;
    PBootProc = ^TBootProc;

    { A single boot registration entry }
    TBootEntry = record
        Name      : PChar;     { Unique identifier, e.g. 'arch.x86.gdt' }
        InitProc  : TBootProc; { Procedure to call during boot }
        Status    : PChar;     { Splash screen status text }
        DependsOn : PChar;     { Name of the entry this depends on, or nil }
        Barrier   : Boolean;   { If true, deferred until all non-barrier entries
                                 at this dependency level have been emitted }
    end;
    PBootEntry = ^TBootEntry;

{ Register a boot entry.  Called from unit initialization sections.
  - Name      : unique identifier for this entry (must be a string literal / constant)
  - InitProc  : parameterless procedure to call during boot
  - Status    : splash screen progress text shown while this entry runs
  - DependsOn : name of another entry that must run first, or nil for no dependency }
procedure registerBoot(Name: PChar; InitProc: TBootProc; Status: PChar; DependsOn: PChar);

{ Register a barrier entry.  Same as registerBoot but the entry is deferred
  until all non-barrier entries at the same dependency level have been
  emitted.  Use this for phase markers that define ordering boundaries
  (e.g. 'immediate', 'early', 'middle', 'late'). }
procedure registerBarrier(Name: PChar; InitProc: TBootProc; Status: PChar; DependsOn: PChar);

{ Execute all registered boot entries in dependency order.
  Updates syslog and the splash screen as each entry completes. }
procedure run;

implementation

uses
    io.syslog, boot.splash,

    // Silo units that must be included here to compile
    driver.storage.boot,
    test,
    core,
    app.wasm,
    driver.storage.ctl.ahci,
    core.enc.base64,
    core.panic,
    driver.video.bga,
    arch.x86.bda,
    arch.x86.panic,
    core.ds.cfifo,
    core.ds.cfifols,
    core.ds.circ,
    core.gfx.color,
    arch.x86.proc.sched,
    arch.x86.cpu,
    driver.video.desktop,
    driver.video.doublebuffer,
    driver.mgr,
    driver.net.dev.e1000,
    driver.bus.usb.ehci,
    driver.storage.fs.fat32,
    arch.x86.fault,
    core.ds.fifo,
    driver.storage.fs.mgr,
    driver.storage.fs.flatfs,
    core.gfx.fonts,
    arch.x86.gdt,
    driver.video.gpu,
    svc.gfxd,
    core.ds.hashmap,
    arch.x86.idt,
    arch.x86.isr.ioapic,
    arch.x86.irq,
    driver.storage.fs.iso9660,
    arch.x86.isr,
    arch.x86.isr.mgr,
    driver.hid.keyboard,
    core.ds.lifo,
    core.ds.lists,
    memory.heap,
    driver.video.lvgl,
    core.ds.maxh,
    core.enc.md5,
    core.ds.minh,
    driver.hid.mouse,
    arch.x86.multiboot,
    driver.net,
    driver.bus.usb.ohci,
    app.partcmd,
    driver.bus.pci,
    arch.x86.memory.physical,
    core.ds.prio,
    proc.mgr,
    app.mgr,
    driver.hid.ps2.keyboard,
    driver.hid.ps2.mouse,
    core.rand,
    driver.timer.rtc,
    driver.io.serial,
    io.stdio,
    driver.storage.mgr,
    driver.storage.test,
    core.strings,
    driver.exp.testdriver,
    proc.testprocs,
    arch.x86.isr.tmr0,
    debug.tracer,
    driver.bus.usb.uhci,
    app.uidebug,
    driver.bus.usb,
    driver.hid.usb.keyboard,
    driver.hid.usb.mouse,
    driver.storage.ctl.usb,
    driver.bus.usb.core,
    svc.usbd,
    driver.bus.usb.hub,
    driver.bus.usb.types,
    core.util, 
    arch.x86.util,
    arch.x86.v86,
    driver.video.vesa,
    driver.storage.vfs,
    driver.video,
    arch.x86.memory.virtual,
    core.enc.fnv1a,
    core.enc.djb2,
    core.ds.bloom,
    app.volcmd,
    driver.storage.vol.mgr,
    app.vterminal,
    wasm, 
    wasm.vm.io, 
    wasm.test, 
    wasm.test.framework,
    driver.video.windows,
    driver.bus.usb.xhci,
    core.fmt.json;

type
    { Resolved execution order — indices into Entries[] }
    TOrderArray = array[0..MAX_BOOT_ENTRIES - 1] of uint32;

var
    { Registration table — filled during initialization sections }
    Entries    : array[0..MAX_BOOT_ENTRIES - 1] of TBootEntry;
    EntryCount : uint32 = 0;

    { Shared scratch space for topoSort results — kept at module scope
      rather than on the stack because this 512-byte array would otherwise
      live on the 16 KB kernel stack for the entire duration of run(),
      leaving too little headroom for the deeply-nested driver init
      chains and their ISRs. }
    SortedOrder : TOrderArray;

{ ---- Internal helpers ---- }

{ Null-safe PChar equality test.  Does not allocate memory. }
function pcharEqual(a, b: PChar): Boolean;
var
    i: uint32;
begin
    if (a = nil) and (b = nil) then exit(true);
    if (a = nil) or  (b = nil) then exit(false);
    i := 0;
    while (a[i] <> #0) and (b[i] <> #0) do begin
        if a[i] <> b[i] then exit(false);
        Inc(i);
    end;
    pcharEqual := (a[i] = #0) and (b[i] = #0);
end;

{ Return the length of a null-terminated PChar string. }
function pcharLen(s: PChar): uint32;
var
    i: uint32;
begin
    i := 0;
    while s[i] <> #0 do Inc(i);
    pcharLen := i;
end;

{ Check whether a DependsOn string contains any '*' characters. }
function isGlob(pattern: PChar): Boolean;
var
    i: uint32;
begin
    if pattern = nil then exit(false);
    i := 0;
    while pattern[i] <> #0 do begin
        if pattern[i] = '*' then exit(true);
        Inc(i);
    end;
    isGlob := false;
end;

{ Match a name against a glob pattern.  '*' matches zero or more of any
  character and may appear anywhere in the pattern, including multiple
  times (e.g. 'arch.*.memory.*').

  Uses a greedy two-cursor algorithm with backtracking:
    ni — current position in name
    pi — current position in pattern
    starP / starN — saved positions after the most recent '*' for retry

  No heap allocation.  Runs in O(n*m) worst case where n = name length
  and m = pattern length, but typical patterns are short. }
function globMatches(name, pattern: PChar): Boolean;
var
    ni, pi      : uint32;
    starP, starN: uint32;
    nameLen, patLen: uint32;
begin
    if (name = nil) or (pattern = nil) then exit(false);

    nameLen := pcharLen(name);
    patLen  := pcharLen(pattern);
    ni := 0;
    pi := 0;
    starP := $FFFFFFFF;  { no star seen yet }
    starN := 0;

    while ni < nameLen do begin
        if (pi < patLen) and (pattern[pi] = '*') then begin
            { Record star position and advance pattern past the '*' }
            starP := pi;
            starN := ni;
            Inc(pi);
        end
        else if (pi < patLen) and (pattern[pi] = name[ni]) then begin
            { Characters match — advance both cursors }
            Inc(ni);
            Inc(pi);
        end
        else if starP <> $FFFFFFFF then begin
            { Mismatch but we have a prior '*' — backtrack:
              let that '*' consume one more character from name }
            pi := starP + 1;
            Inc(starN);
            ni := starN;
        end
        else begin
            { Mismatch with no '*' to fall back on }
            exit(false);
        end;
    end;

    { Consume any trailing '*' characters in the pattern }
    while (pi < patLen) and (pattern[pi] = '*') do
        Inc(pi);

    globMatches := (pi = patLen);
end;

{ Check whether all entries matching a glob pattern have been emitted.
  Returns true if every entry whose Name matches the pattern has Emitted[]=true.
  Also returns true if no entries match (vacuous truth — nothing to wait for). }
function allGlobEmitted(pattern: PChar; var Emitted: array of Boolean): Boolean;
var
    i: uint32;
begin
    for i := 0 to EntryCount - 1 do begin
        if globMatches(Entries[i].Name, pattern) and (not Emitted[i]) then
            exit(false);
    end;
    allGlobEmitted := true;
end;

{ Look up an entry index by name.  Returns index, or $FFFFFFFF if not found. }
function findEntry(Name: PChar): uint32;
var
    i: uint32;
begin
    for i := 0 to EntryCount - 1 do begin
        if pcharEqual(Entries[i].Name, Name) then exit(i);
    end;
    findEntry := $FFFFFFFF;
end;

{ Check whether entry i is eligible for emission (all dependencies met). }
function isEligible(i: uint32; var Emitted: array of Boolean): Boolean;
var
    depIdx: uint32;
begin
    if Emitted[i] then exit(false);

    { No dependency — always eligible }
    if Entries[i].DependsOn = nil then exit(true);

    { Glob dependency — eligible when all matching entries are emitted }
    if isGlob(Entries[i].DependsOn) then
        exit(allGlobEmitted(Entries[i].DependsOn, Emitted));

    { Exact dependency — eligible when that specific entry is emitted }
    depIdx := findEntry(Entries[i].DependsOn);
    if depIdx = $FFFFFFFF then exit(false); { unresolved dependency }
    isEligible := Emitted[depIdx];
end;

{ Perform a topological sort of Entries[] into Order[].
  Uses a repeated-scan approach that is O(n^2) but requires only a
  small static boolean array — no heap allocation needed.

  Supports two kinds of DependsOn values:
    - Exact name   (e.g. 'io.syslog')  — waits for that one entry.
    - Glob pattern (e.g. 'arch.*', 'arch.*.memory.*') — waits for ALL
      entries whose names match the pattern.  '*' matches zero or more
      of any character and may appear multiple times.

  Barrier entries are deferred within each pass: non-barrier entries are
  always emitted before barrier entries at the same dependency level.
  This means that if 'immediate' is a barrier and 'mydriver' depends on
  'immediate', 'mydriver' will be scheduled before the next barrier
  ('early') even though both become eligible at the same time.

  Returns the number of entries placed into Order[].  If this is less
  than EntryCount, there is a cycle or a missing dependency. }
function topoSort(var Order: TOrderArray): uint32;
var
    Emitted            : array[0..MAX_BOOT_ENTRIES - 1] of Boolean;
    count              : uint32;
    i                  : uint32;
    progress           : Boolean;
    nonBarrierProgress : Boolean;
begin
    for i := 0 to EntryCount - 1 do
        Emitted[i] := false;

    count := 0;

    repeat
        progress := false;

        { Sub-pass 1: emit all eligible NON-barrier entries }
        nonBarrierProgress := true;
        while nonBarrierProgress do begin
            nonBarrierProgress := false;
            for i := 0 to EntryCount - 1 do begin
                if Entries[i].Barrier then continue;
                if not isEligible(i, Emitted) then continue;
                Order[count] := i;
                Inc(count);
                Emitted[i] := true;
                nonBarrierProgress := true;
                progress := true;
            end;
        end;

        { Sub-pass 2: emit exactly ONE eligible barrier, then return to
          sub-pass 1 so that non-barrier entries unlocked by this barrier
          get a chance to run before the next barrier fires.  Without this
          break, barriers cascade (immediate -> early -> middle -> late all
          in one shot) and non-barriers never interleave. }
        for i := 0 to EntryCount - 1 do begin
            if not Entries[i].Barrier then continue;
            if not isEligible(i, Emitted) then continue;
            Order[count] := i;
            Inc(count);
            Emitted[i] := true;
            progress := true;
            break;
        end;
    until (count = EntryCount) or (not progress);

    topoSort := count;
end;

{ ---- Public API ---- }

{ Shared registration logic used by both registerBoot and registerBarrier. }
procedure internalRegister(Name: PChar; InitProc: TBootProc; Status: PChar; DependsOn: PChar; IsBarrier: Boolean);
begin
    if EntryCount >= MAX_BOOT_ENTRIES then begin
        { Fatal: too many boot entries — halt immediately.
          We cannot use syslog/panic here as they may not be initialized. }
        asm
            cli
            hlt
        end;
    end;

    Entries[EntryCount].Name      := Name;
    Entries[EntryCount].InitProc  := InitProc;
    Entries[EntryCount].Status    := Status;
    Entries[EntryCount].DependsOn := DependsOn;
    Entries[EntryCount].Barrier   := IsBarrier;
    Inc(EntryCount);
end;

procedure registerBoot(Name: PChar; InitProc: TBootProc; Status: PChar; DependsOn: PChar);
begin
    internalRegister(Name, InitProc, Status, DependsOn, false);
end;

procedure registerBarrier(Name: PChar; InitProc: TBootProc; Status: PChar; DependsOn: PChar);
begin
    internalRegister(Name, InitProc, Status, DependsOn, true);
end;

{ Append a PChar string to a buffer at position pos.
  Does not write past bufLen.  Returns updated pos. }
function bufAppend(var buf: array of char; pos, bufLen: uint32; s: PChar): uint32;
var
    i: uint32;
begin
    if s = nil then exit(pos);
    i := 0;
    while (s[i] <> #0) and (pos < bufLen - 1) do begin
        buf[pos] := s[i];
        Inc(pos);
        Inc(i);
    end;
    buf[pos] := #0;
    bufAppend := pos;
end;

{ Return the dependency depth of an entry by following its DependsOn chain
  iteratively.  Glob dependencies are treated as depth 1 (group boundary).
  Cap at 16 to guard against cycles. }
function entryDepth(idx: uint32): uint32;
var
    depIdx, depth: uint32;
begin
    depth := 0;
    while (depth < 16) and (Entries[idx].DependsOn <> nil) do begin
        if isGlob(Entries[idx].DependsOn) then begin
            Inc(depth);
            break;
        end;
        depIdx := findEntry(Entries[idx].DependsOn);
        if depIdx = $FFFFFFFF then break;
        Inc(depth);
        idx := depIdx;
    end;
    entryDepth := depth;
end;

procedure printBootEntriesTree;
const
    LINE_BUF_SIZE = 256;
var
    Sorted : uint32;
    i      : uint32;
    idx    : uint32;
    depth  : uint32;
    d      : uint32;
    line   : array[0..LINE_BUF_SIZE - 1] of char;
    pos    : uint32;
begin
    Sorted := topoSort(SortedOrder);

    io.syslog.logln('BOOT', '--- Boot Entries Tree ---');

    for i := 0 to Sorted - 1 do begin
        idx := SortedOrder[i];
        depth := entryDepth(idx);

        pos := 0;

        { Indent by depth — two spaces per level }
        if depth > 0 then
            for d := 0 to depth - 1 do
                pos := bufAppend(line, pos, LINE_BUF_SIZE, '  ');

        { Barrier marker }
        if Entries[idx].Barrier then
            pos := bufAppend(line, pos, LINE_BUF_SIZE, '[B] ')
        else
            pos := bufAppend(line, pos, LINE_BUF_SIZE, '    ');

        { Entry name }
        pos := bufAppend(line, pos, LINE_BUF_SIZE, Entries[idx].Name);

        io.syslog.logln('BOOT', @line[0]);
    end;

    io.syslog.logln('BOOT', '--- End Boot Entries ---');
end;

procedure run;
var
    Sorted    : uint32;
    i         : uint32;
    idx       : uint32;
begin
    { No entries to run — exit early. }
    if EntryCount = 0 then exit;

    { Phase barriers form the main chain.  The "after" barriers are
      registered between the phase they gate and the next phase so that
      when multiple barriers become eligible simultaneously, the for-loop
      in topoSort picks the lower-indexed one first — giving "after"
      barriers priority over the next phase marker. }
    registerBarrier(BOOT_MGR_BARRIER_IMMEDIATE, nil, 'Immediate Section', nil);
    registerBarrier(BOOT_MGR_BARRIER_EARLY,     nil, 'Early Section',     BOOT_MGR_BARRIER_IMMEDIATE);
    registerBarrier(BOOT_MGR_BARRIER_MID,       nil, 'Middle Section',    BOOT_MGR_BARRIER_EARLY);
    registerBarrier(BOOT_MGR_BARRIER_STORAGE,   nil, 'Storage Section',   BOOT_MGR_BARRIER_MID);
    registerBarrier(BOOT_MGR_BARRIER_BUS,       nil, 'Bus Section',       BOOT_MGR_BARRIER_STORAGE);
    registerBarrier(BOOT_MGR_BARRIER_DEVICE,    nil, 'Device Section',    BOOT_MGR_BARRIER_BUS);
    registerBarrier(BOOT_MGR_BARRIER_BUS_LATE,  nil, 'Late Bus Section',  BOOT_MGR_BARRIER_DEVICE);
    registerBarrier(BOOT_MGR_BARRIER_LATE,      nil, 'Late Section',      BOOT_MGR_BARRIER_BUS_LATE);
    registerBarrier(BOOT_MGR_BARRIER_FINAL,     nil, 'Final Section',     BOOT_MGR_BARRIER_LATE);

    { Sort entries into dependency order }
    Sorted := topoSort(SortedOrder);

    { Execute each entry in order.
      Log AFTER calling InitProc so that io.syslog is already initialized
      by the time we first try to write through it. }
    for i := 0 to Sorted - 1 do begin
        idx := SortedOrder[i];
        io.syslog.logln('BOOT', Entries[idx].Name);
        if Entries[idx].InitProc <> nil then begin
            boot.splash.update((100 * i) div Sorted, Entries[idx].Status);
            Entries[idx].InitProc();
        end;
    end;
end;

initialization
    { EntryCount lives in BSS and is zeroed by the bootloader's memory
      clear.  We intentionally do NOT reset it here because the INITFINAL
      table calls initialization sections in alphabetical order — units
      whose names sort before 'boot.mgr' (e.g. arch.x86.gdt, asuro) will
      have already registered by the time this section runs, and resetting
      EntryCount would silently discard their registrations. }
    registerBoot('boot.mgr.debug', @printBootEntriesTree, 'Debug: Print Boot Entries Tree', 'io.syslog');

end.