{
    ProcessManager - Preemptive process management for the Asuro kernel.

    Manages a process table (DList), creates processes with per-process
    core.version stacks, provides find/send/terminate/kill APIs, and implements
    the round-robin scheduler called from the context switch ISR.

    @author(Kieron Morris <kjm@kieronmorris.me>)
    @author(Aaron Hance <ah@aaronhance.me>)
}
unit proc.mgr;

interface

uses
    arch.x86.bda,
    driver.storage.fdtable,
    core.ds.lists,
    memory.heap,
    proc.types,
    core.rand,
    io.stdio,
    core.strings,
    io.syslog,
    debug.tracer,
    core.util, arch.x86.util;

{ Core API }
function  create(name : pchar;
                 entry : TProcessEntryPoint;
                 localData : void;
                 priority : uint8) : PProcessContext;

function  findByID(pid : uint32) : PProcessContext;
function  findByName(name : pchar) : PProcessContext;
procedure sendMessage(pid : uint32; msg : TProcessSysMsg; data : void);
procedure terminate(pid : uint32);
procedure kill(pid : uint32);

{ Process self-management (called by the running process) }
procedure proc_yield;
procedure proc_sleep_ms(ms : uint32);
procedure proc_await;
procedure proc_suspend;
procedure proc_exit(exitCode : uint32);

{ Resource binding }
procedure bindResource(ctx : PProcessContext; kind : TResourceKind; handle : void; cleanup : TResourceCleanup);
procedure unbindResource(ctx : PProcessContext; handle : void);
procedure unbindResourceNoCleanup(ctx : PProcessContext; handle : void);
procedure unbindAllResources(ctx : PProcessContext);

{ Legacy command wrapper }
function  runCommand(name : pchar; method : TCommandMethod; params : PParamList;
                     stdin_buf, stdout_buf, stderr_buf : POutBuf) : PProcessContext;

{ Query }
function  processCount : uint32;
function  getProcessByIndex(idx : uint32) : PProcessContext;

{ Scheduler - called from context switch ISR }
function  scheduler_pick_next : PProcessContext;

{ Reap dead processes - called from scheduler }
procedure reapFinished;

{ Init (called from kernel.pas) }
procedure init;

{ Terminal command procedures }
procedure terminal_command_ps(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
procedure terminal_command_kill(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
procedure terminal_command_terminate(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);

var
    { Currently executing process (never nil — at minimum the idle process) }
    CurrentProcess : PProcessContext;

    { The idle process — PID 0, unkillable, runs kernel.yield HLT loop }
    IdleProcess : PProcessContext;

    { Process table }
    Processes : PDList;

    { Round-robin index for scheduling }
    SchedulerIndex : uint32;

implementation

{ ---- Internal helpers ---- }

procedure copyName(dest : pchar; src : pchar; maxLen : uint32);
var
    i : uint32;
begin
    i := 0;
    while (i < maxLen - 1) and (src[i] <> #0) do begin
        dest[i] := src[i];
        i := i + 1;
    end;
    dest[i] := #0;
end;

{ Forward declaration for process_trampoline (used in create) }
procedure process_trampoline; forward;

{ ---- Process creation ---- }

function create(name : pchar;
                entry : TProcessEntryPoint;
                localData : void;
                priority : uint8) : PProcessContext;
var
    ctx      : PProcessContext;
    slotPtr  : ^uint32;
    stack    : void;
    sp       : uint32;
    prio     : uint8;
begin
    push_trace('proc.mgr.create');

    if priority = 0 then prio := 1 else prio := priority;

    { Allocate process context }
    ctx := PProcessContext(kalloc(SizeOf(TProcessContext)));
    memset(uint32(ctx), 0, SizeOf(TProcessContext));

    { Identity }
    ctx^.ProcessID := rand32;
    copyName(@ctx^.Name[0], name, 32);
    ctx^.ParentID := 0;
    if CurrentProcess <> nil then
        ctx^.ParentID := CurrentProcess^.ProcessID;

    { State }
    ctx^.State := psCreated;
    ctx^.ExitCode := 0;

    { Entry point }
    ctx^.EntryPoint := entry;

    { Local data }
    ctx^.Local := localData;

    { Scheduling }
    ctx^.Priority := prio;
    ctx^.Quantum := prio * BASE_QUANTUM;
    ctx^.TicksUsed := 0;

    { Messages }
    ctx^.PendingMsg := smNone;
    ctx^.MsgData := nil;

    { Resources }
    ctx^.Resources := void(DL_New(SizeOf(TResourceBinding)));

    { Per-process file descriptor table }
    ctx^.FDTable := void(fd_table_new);

    { Per-process working directory }
    ctx^.Cwd := stringCopy('/');

    { Allocate per-process core.version stack }
    stack := kalloc(PROCESS_STACK_SIZE);
    ctx^.StackBase := stack;
    ctx^.StackTop := uint32(stack) + PROCESS_STACK_SIZE;

    { Build fake interrupt frame on the stack so the first context switch
      IRET's into process_trampoline.

      Stack layout (growing downward):
        [StackTop - 4]   EFLAGS  ($0202 = IF set)
        [StackTop - 8]   CS      ($08 = core.version code)
        [StackTop - 12]  EIP     (-> process_trampoline)
        [StackTop - 16]  EAX     (0)
        [StackTop - 20]  ECX     (0)
        [StackTop - 24]  EDX     (0)
        [StackTop - 28]  EBX     (0)
        [StackTop - 32]  ESP     (ignored by POPAD)
        [StackTop - 36]  EBP     (0)
        [StackTop - 40]  ESI     (0)
        [StackTop - 44]  EDI     (0)
        [StackTop - 48]  DS      ($10 = core.version data, padded to 32-bit)
        [StackTop - 52]  ES      ($10)
        [StackTop - 56]  FS      ($10)
        [StackTop - 60]  GS      ($10)
      SavedESP = StackTop - 60
    }
    sp := ctx^.StackTop;

    { IRET frame }
    sp := sp - 4; PuInt32(sp)^ := $0202;                       { EFLAGS: IF=1 }
    sp := sp - 4; PuInt32(sp)^ := $08;                         { CS }
    sp := sp - 4; PuInt32(sp)^ := uint32(@process_trampoline); { EIP }

    { POPAD frame (8 registers) }
    sp := sp - 4; PuInt32(sp)^ := 0;  { EAX }
    sp := sp - 4; PuInt32(sp)^ := 0;  { ECX }
    sp := sp - 4; PuInt32(sp)^ := 0;  { EDX }
    sp := sp - 4; PuInt32(sp)^ := 0;  { EBX }
    sp := sp - 4; PuInt32(sp)^ := 0;  { ESP (ignored by POPAD) }
    sp := sp - 4; PuInt32(sp)^ := 0;  { EBP }
    sp := sp - 4; PuInt32(sp)^ := 0;  { ESI }
    sp := sp - 4; PuInt32(sp)^ := 0;  { EDI }

    { Segment registers (pushed as 32-bit values) }
    sp := sp - 4; PuInt32(sp)^ := $10; { DS }
    sp := sp - 4; PuInt32(sp)^ := $10; { ES }
    sp := sp - 4; PuInt32(sp)^ := $10; { FS }
    sp := sp - 4; PuInt32(sp)^ := $10; { GS }

    ctx^.SavedESP := sp;

    { Add to process table }
    asm pushf; cli end;
    slotPtr := DL_Add(Processes);
    slotPtr^ := uint32(ctx);

    { Mark as ready for scheduling }
    ctx^.State := psReady;
    asm popf end;

    io.syslog.log('PROCMGR', 'Created process: ');
    io.syslog.writestringln(name);

    pop_trace;
    create := ctx;
end;

{ ---- Process trampoline ---- }
{ This is the EIP that IRET jumps to on the first schedule of a process.
  It calls the process entry point, and when it returns, marks the process
  as finished and halts until reaped. }
procedure process_trampoline;
begin
    { Interrupts are enabled by IRET restoring EFLAGS with IF=1 }
    if CurrentProcess <> nil then begin
        CurrentProcess^.EntryPoint(CurrentProcess);
        { Entry point returned - process is done }
        CurrentProcess^.State := psFinished;
    end;
    { Wait for the scheduler to reap us }
    while true do begin
        asm
            hlt
        end;
    end;
end;

{ ---- Find ---- }

function findByID(pid : uint32) : PProcessContext;
var
    i      : uint32;
    slotPtr : ^uint32;
    ctx    : PProcessContext;
begin
    findByID := nil;
    if Processes = nil then exit;
    for i := 0 to DL_Size(Processes) - 1 do begin
        slotPtr := DL_Get(Processes, i);
        if slotPtr <> nil then begin
            ctx := PProcessContext(slotPtr^);
            if ctx^.ProcessID = pid then begin
                findByID := ctx;
                exit;
            end;
        end;
    end;
end;

function findByName(name : pchar) : PProcessContext;
var
    i      : uint32;
    slotPtr : ^uint32;
    ctx    : PProcessContext;
begin
    findByName := nil;
    if Processes = nil then exit;
    for i := 0 to DL_Size(Processes) - 1 do begin
        slotPtr := DL_Get(Processes, i);
        if slotPtr <> nil then begin
            ctx := PProcessContext(slotPtr^);
            if stringEquals(@ctx^.Name[0], name) then begin
                findByName := ctx;
                exit;
            end;
        end;
    end;
end;

{ ---- Messaging ---- }

procedure sendMessage(pid : uint32; msg : TProcessSysMsg; data : void);
var
    ctx : PProcessContext;
begin
    ctx := findByID(pid);
    if ctx <> nil then begin
        ctx^.PendingMsg := msg;
        ctx^.MsgData := data;
        { If the process is awaiting, wake it up on any message }
        if ctx^.State = psAwaiting then
            ctx^.State := psReady;
        { If suspended and receiving smResume, wake it }
        if (ctx^.State = psSuspended) and (msg = smResume) then
            ctx^.State := psReady;
    end;
end;

procedure terminate(pid : uint32);
begin
    if pid = 0 then exit;  { Cannot terminate idle }
    sendMessage(pid, smTerminate, nil);
end;

procedure kill(pid : uint32);
var
    ctx : PProcessContext;
begin
    if pid = 0 then exit;  { Cannot kill idle }
    ctx := findByID(pid);
    if ctx <> nil then begin
        asm pushf; cli end;
        ctx^.State := psFinished;
        ctx^.ExitCode := $FFFFFFFF;
        asm popf end;
    end;
end;

{ ---- Process self-management ---- }

procedure proc_yield;
begin
    if CurrentProcess <> nil then begin
        asm pushf; cli end;
        CurrentProcess^.TicksUsed := CurrentProcess^.Quantum;
        asm popf end;
        { Next timer tick will preempt us }
        asm
            hlt
        end;
    end;
end;

procedure proc_sleep_ms(ms : uint32);
var
    ticks : uint32;
    start, now, elapsed : uint32;
begin
    ticks := (ms * 1024) div 1000;
    if ticks = 0 then ticks := 1;
    start := Counters.c32;
    repeat
        proc_yield;
        now := Counters.c32;
        if now >= start then
            elapsed := now - start
        else
            elapsed := ($FFFFFFFF - start) + now + 1;
    until elapsed >= ticks;
end;

procedure proc_await;
begin
    { Caller must set CurrentProcess^.State := psAwaiting before calling.
      This procedure just spin-waits until an ISR sets the state back
      to something other than psAwaiting. }
    if CurrentProcess <> nil then begin
        while CurrentProcess^.State = psAwaiting do
            asm hlt end;
    end;
end;

procedure proc_suspend;
begin
    if CurrentProcess <> nil then begin
        asm pushf; cli end;
        CurrentProcess^.State := psSuspended;
        asm popf end;
        asm
            hlt
        end;
    end;
end;

procedure proc_exit(exitCode : uint32);
begin
    if CurrentProcess <> nil then begin
        CurrentProcess^.ExitCode := exitCode;
        CurrentProcess^.State := psFinished;
        while true do begin
            asm
                hlt
            end;
        end;
    end;
end;

{ ---- Resource binding ---- }

procedure bindResource(ctx : PProcessContext; kind : TResourceKind; handle : void; cleanup : TResourceCleanup);
var
    resList : PDList;
    binding : PResourceBinding;
begin
    if ctx = nil then exit;
    resList := PDList(ctx^.Resources);
    if resList = nil then exit;
    binding := PResourceBinding(DL_Add(resList));
    binding^.Kind := kind;
    binding^.Handle := handle;
    binding^.Cleanup := cleanup;
end;

procedure unbindResource(ctx : PProcessContext; handle : void);
var
    resList : PDList;
    binding : PResourceBinding;
    i       : uint32;
begin
    if ctx = nil then exit;
    resList := PDList(ctx^.Resources);
    if resList = nil then exit;
    for i := 0 to DL_Size(resList) - 1 do begin
        binding := PResourceBinding(DL_Get(resList, i));
        if binding^.Handle = handle then begin
            if binding^.Cleanup <> nil then
                binding^.Cleanup(binding^.Handle);
            DL_Delete(resList, i);
            exit;
        end;
    end;
end;

procedure unbindResourceNoCleanup(ctx : PProcessContext; handle : void);
var
    resList : PDList;
    binding : PResourceBinding;
    i       : uint32;
begin
    if ctx = nil then exit;
    resList := PDList(ctx^.Resources);
    if resList = nil then exit;
    for i := 0 to DL_Size(resList) - 1 do begin
        binding := PResourceBinding(DL_Get(resList, i));
        if binding^.Handle = handle then begin
            DL_Delete(resList, i);
            exit;
        end;
    end;
end;

procedure unbindAllResources(ctx : PProcessContext);
var
    resList : PDList;
    binding : PResourceBinding;
    i       : sint32;
begin
    if ctx = nil then exit;
    resList := PDList(ctx^.Resources);
    if resList = nil then exit;
    { Detach early so cleanup callbacks that re-enter find nothing }
    ctx^.Resources := nil;
    for i := sint32(DL_Size(resList)) - 1 downto 0 do begin
        binding := PResourceBinding(DL_Get(resList, uint32(i)));
        if binding <> nil then begin
            if binding^.Cleanup <> nil then
                binding^.Cleanup(binding^.Handle);
        end;
    end;
    DL_Free(resList);
end;

{ ---- Legacy command wrapper ---- }

{ Entry point for legacy TCommandMethod commands wrapped as processes }
procedure legacy_entry(ctx : PProcessContext);
var
    method : TCommandMethod;
    params : PParamList;
begin
    method := TCommandMethod(ctx^.Local);
    params := PParamList(ctx^.MsgData);
    method(params, ctx^.StdIn, ctx^.StdOut, ctx^.StdErr);
    { When method returns, process_trampoline will set psFinished }
end;

function runCommand(name : pchar; method : TCommandMethod; params : PParamList;
                    stdin_buf, stdout_buf, stderr_buf : POutBuf) : PProcessContext;
var
    ctx : PProcessContext;
begin
    ctx := create(name, @legacy_entry, void(method), 1);
    if ctx <> nil then begin
        ctx^.MsgData := void(params);
        ctx^.StdIn := stdin_buf;
        ctx^.StdOut := stdout_buf;
        ctx^.StdErr := stderr_buf;
    end;
    runCommand := ctx;
end;

{ ---- Query ---- }

function processCount : uint32;
begin
    if Processes = nil then
        processCount := 0
    else
        processCount := DL_Size(Processes);
end;

function getProcessByIndex(idx : uint32) : PProcessContext;
var
    slotPtr : ^uint32;
begin
    getProcessByIndex := nil;
    if Processes = nil then exit;
    if idx >= DL_Size(Processes) then exit;
    slotPtr := DL_Get(Processes, idx);
    if slotPtr <> nil then
        getProcessByIndex := PProcessContext(slotPtr^);
end;

{ ---- Reaping ---- }

procedure reapFinished;
var
    i       : sint32;
    slotPtr : ^uint32;
    ctx     : PProcessContext;
    parent  : PProcessContext;
begin
    if Processes = nil then exit;
    { Iterate in reverse so index shifting from DL_Delete is safe }
    for i := sint32(DL_Size(Processes)) - 1 downto 0 do begin
        slotPtr := DL_Get(Processes, uint32(i));
        if slotPtr = nil then continue;
        ctx := PProcessContext(slotPtr^);
        if (ctx^.State = psFinished) or (ctx^.State = psError) then begin
            { Don't reap the currently running process }
            if ctx = CurrentProcess then continue;
            { Never reap the idle process }
            if ctx^.ProcessID = 0 then continue;
            { Notify parent (if it exists) that a child has exited }
            if ctx^.ParentID <> 0 then begin
                parent := findByID(ctx^.ParentID);
                if parent <> nil then
                    sendMessage(parent^.ProcessID, smChildExited, void(ctx^.ProcessID));
            end;
            { Clean up file descriptors }
            if ctx^.FDTable <> nil then begin
                fd_table_free(PFDTable(ctx^.FDTable));
                ctx^.FDTable := nil;
            end;
            { Free per-process CWD }
            if ctx^.Cwd <> nil then begin
                kfree(void(ctx^.Cwd));
                ctx^.Cwd := nil;
            end;
            { Clean up resources }
            unbindAllResources(ctx);
            { Free stack }
            if ctx^.StackBase <> nil then
                kfree(ctx^.StackBase);
            { Remove from table }
            DL_Delete(Processes, uint32(i));
            { Free context }
            kfree(void(ctx));
        end;
    end;
end;

{ ---- Scheduler ---- }

function scheduler_pick_next : PProcessContext;
var
    count   : uint32;
    i       : uint32;
    idx     : uint32;
    slotPtr : ^uint32;
    ctx     : PProcessContext;
begin
    { Reap dead processes first }
    reapFinished;

    count := DL_Size(Processes);

    { Check if current process still has quantum left }
    if CurrentProcess^.State = psRunning then begin
        CurrentProcess^.TicksUsed := CurrentProcess^.TicksUsed + 1;
        if CurrentProcess^.TicksUsed < CurrentProcess^.Quantum then begin
            scheduler_pick_next := CurrentProcess;
            exit;
        end;
        { Quantum expired, move to ready }
        CurrentProcess^.State := psReady;
        CurrentProcess^.TicksUsed := 0;
    end;

    { Round-robin: scan from SchedulerIndex, skipping idle }
    if SchedulerIndex >= count then
        SchedulerIndex := 0;

    for i := 0 to count - 1 do begin
        idx := (SchedulerIndex + i) mod count;
        slotPtr := DL_Get(Processes, idx);
        if slotPtr = nil then continue;
        ctx := PProcessContext(slotPtr^);
        if ctx^.ProcessID = 0 then continue;  { Skip idle in round-robin }
        if (ctx^.State = psReady) or (ctx^.State = psCreated) then begin
            ctx^.State := psRunning;
            ctx^.TicksUsed := 0;
            SchedulerIndex := (idx + 1) mod count;
            scheduler_pick_next := ctx;
            exit;
        end;
    end;

    { No runnable process found — fall back to idle }
    IdleProcess^.State := psRunning;
    IdleProcess^.TicksUsed := 0;
    scheduler_pick_next := IdleProcess;
end;

{ ---- Terminal commands ---- }

{ Write a string padded with spaces to exactly 'width' characters }
procedure bufWritePadded(buf : POutBuf; s : pchar; width : uint32);
var
    len, j : uint32;
begin
    len := stringSize(s);
    bufWriteStr(buf, s);
    if len < width then
        for j := 1 to width - len do
            bufWriteChar(buf, ' ');
end;

procedure terminal_command_ps(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    i       : uint32;
    slotPtr : ^uint32;
    ctx     : PProcessContext;
    stStr   : pchar;
begin
    push_trace('proc.mgr.terminal_command_ps');

    bufWriteStrLn(stdout_buf, 'PID        NAME                      STATE       PRI');
    bufWriteStrLn(stdout_buf, '---------- ------------------------- ----------- ---');

    if Processes <> nil then begin
        for i := 0 to DL_Size(Processes) - 1 do begin
            slotPtr := DL_Get(Processes, i);
            if slotPtr = nil then continue;
            ctx := PProcessContext(slotPtr^);

            { PID — bufWriteHex writes exactly 10 chars, pad 1 space }
            bufWriteHex(stdout_buf, ctx^.ProcessID);
            bufWriteChar(stdout_buf, ' ');

            { Name — pad to 26 chars (25 + 1 separator) }
            bufWritePadded(stdout_buf, @ctx^.Name[0], 26);

            { State — pad to 12 chars (11 + 1 separator) }
            case ctx^.State of
                psCreated:    stStr := 'Created';
                psRunning:    stStr := 'Running';
                psReady:      stStr := 'Ready';
                psSuspended:  stStr := 'Suspended';
                psAwaiting:   stStr := 'Awaiting';
                psFinished:   stStr := 'Finished';
                psError:      stStr := 'Error';
            else
                stStr := 'Unknown';
            end;
            bufWritePadded(stdout_buf, stStr, 12);

            { Priority }
            bufWriteIntLn(stdout_buf, ctx^.Priority);
        end;
    end;

    pop_trace;
end;

procedure terminal_command_kill(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    pidStr : pchar;
    pid    : uint32;
begin
    push_trace('proc.mgr.terminal_command_kill');

    if paramCount(params) < 1 then begin
        bufWriteStrLn(stderr_buf, 'Usage: KILL <pid_hex>');
        pop_trace;
        exit;
    end;

    pidStr := getParam(0, params);
    pid := hexStringToInt(pidStr);
    if findByID(pid) = nil then begin
        bufWriteStrLn(stderr_buf, 'Process not found.');
        pop_trace;
        exit;
    end;

    kill(pid);
    bufWriteStr(stdout_buf, 'Killed process ');
    bufWriteHexLn(stdout_buf, pid);

    pop_trace;
end;

procedure terminal_command_terminate(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    pidStr : pchar;
    pid    : uint32;
begin
    push_trace('proc.mgr.terminal_command_terminate');

    if paramCount(params) < 1 then begin
        bufWriteStrLn(stderr_buf, 'Usage: TERMINATE <pid_hex>');
        pop_trace;
        exit;
    end;

    pidStr := getParam(0, params);
    pid := hexStringToInt(pidStr);
    if findByID(pid) = nil then begin
        bufWriteStrLn(stderr_buf, 'Process not found.');
        pop_trace;
        exit;
    end;

    terminate(pid);
    bufWriteStr(stdout_buf, 'Sent terminate to ');
    bufWriteHexLn(stdout_buf, pid);

    pop_trace;
end;

{ ---- Init ---- }

procedure init;
var
    slotPtr : ^uint32;
begin
    push_trace('proc.mgr.init');
    io.syslog.logln('PROCMGR', 'INIT BEGIN.');

    { Create process table }
    Processes := DL_New(SizeOf(uint32));
    SchedulerIndex := 0;

    { Create idle process — PID 0, unkillable, uses core.version main stack }
    IdleProcess := PProcessContext(kalloc(SizeOf(TProcessContext)));
    memset(uint32(IdleProcess), 0, SizeOf(TProcessContext));
    IdleProcess^.ProcessID := 0;
    copyName(@IdleProcess^.Name[0], 'Idle', 32);
    IdleProcess^.State := psRunning;
    IdleProcess^.Priority := 0;
    IdleProcess^.Quantum := 1;  { Yield to real processes ASAP }
    IdleProcess^.PendingMsg := smNone;
    IdleProcess^.Resources := void(DL_New(SizeOf(TResourceBinding)));
    IdleProcess^.FDTable := void(fd_table_new);
    IdleProcess^.Cwd := stringCopy('/');
    { No stack allocation — idle runs on the core.version's original stack }
    slotPtr := DL_Add(Processes);
    slotPtr^ := uint32(IdleProcess);
    CurrentProcess := IdleProcess;

    io.syslog.logln('PROCMGR', 'Idle process created (PID 0).');

    io.syslog.logln('PROCMGR', 'INIT END.');
    pop_trace;
end;

end.
