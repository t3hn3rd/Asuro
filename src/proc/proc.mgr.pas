//  Copyright 2026 Kieron Morris
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
    core.ds.dynamic, memory.heap, proc.types, proc.scheduler,
    io.types, driver.storage.fdtable, arch.platform.cpu, arch.common.legacyirq,
    arch.platform.process, arch.platform.diagnostics,
    io.stdio, core.strings;

{ Core API }
function  create(name : pchar;
                 entry : TProcessEntryPoint;
                 localData : void;
                 priority : uint8) : PProcessContext;

function createSuspended(name: pchar; entry: TProcessEntryPoint;
    localData: void;
    priority: uint8): PProcessContext;
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

type PProcessSlot = ^PtrUInt;
     PProcessState = ^TProcessState;

procedure log(message: pchar);
begin
    arch.platform.diagnostics.log('PROCMGR', message);
end;

procedure releaseFileTable(ctx: PProcessContext);
begin
    if ctx^.FDTable <> nil then fd_table_free(PFDTable(ctx^.FDTable));
    ctx^.FDTable := nil;
end;

function rootDirectory: pchar;
begin
    rootDirectory := pchar(kalloc(2));
    if rootDirectory <> nil then begin
        rootDirectory[0] := '/';
        rootDirectory[1] := #0;
    end;
end;

function nameEquals(left, right: pchar): boolean;
var
    i: uint32;
begin
    nameEquals := false;
    if (left = nil) or (right = nil) then exit;
    i := 0;
    while i < 32 do begin
        if left[i] <> right[i] then exit;
        if left[i] = #0 then begin
            nameEquals := true;
            exit;
        end;
        inc(i);
    end;
end;
var
    nextProcessID: uint32;
    reaperProcess: PProcessContext;
    reapPending: boolean;

procedure requestReap;
begin
    { Called with IRQs excluded. Coalesces completed tasks into one worker wake. }
    reapPending := true;
    if (reaperProcess <> nil) and (reaperProcess^.State = psAwaiting) then
        reaperProcess^.State := psReady;
end;

procedure reaperEntry(ctx: PProcessContext);
var
    flags: PtrUInt;
begin
    while true do begin
        flags := arch.platform.cpu.lock;
        reapPending := false;
        arch.platform.cpu.unlock(flags);
        reapFinished;
        flags := arch.platform.cpu.lock;
        if not reapPending then ctx^.State := psAwaiting;
        arch.platform.cpu.unlock(flags);
        proc_await;
    end;
end;

function newProcessID: uint32;
var
    flags: PtrUInt;
begin
    flags := arch.platform.cpu.lock;
    { IDs are never recycled; reject exhaustion rather than aliasing live IDs. }
    newProcessID := nextProcessID;
    if nextProcessID <> 0 then inc(nextProcessID);
    arch.platform.cpu.unlock(flags);
end;

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
function createInternal(name : pchar;
                entry : TProcessEntryPoint;
                localData : void;
                priority : uint8;
                runnable : boolean) : PProcessContext;
var
    ctx      : PProcessContext;
    slotPtr  : PProcessSlot;
    stack    : void;
    prio     : uint8;
    savedFlags: PtrUInt;
begin
    push_trace('proc.mgr.create');
    createInternal := nil;

    if (entry = nil) or (name = nil) or (Processes = nil) then begin
        pop_trace;
        exit;
    end;
    if priority = 0 then prio := 1 else prio := priority;

    { Allocate process context }
    ctx := PProcessContext(kalloc(SizeOf(TProcessContext)));
    if ctx = nil then begin
        log('Failed to allocate process context.');
        pop_trace;
        exit;
    end;

    { Identity }
    ctx^.ProcessID := newProcessID;
    if ctx^.ProcessID = 0 then begin
        kfree(void(ctx));
        pop_trace;
        exit;
    end;
    copyName(@ctx^.Name[0], name, 32);
    ctx^.ParentID := 0;
    if CurrentProcess <> nil then
        ctx^.ParentID := CurrentProcess^.ProcessID;

    { State }
    ctx^.State := psSuspended;
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
    if ctx^.Resources = nil then begin
        log('Failed to allocate resource list.');
        kfree(void(ctx));
        pop_trace;
        exit;
    end;

    { Per-process file descriptor table }
    ctx^.FDTable := void(fd_table_new);
    if ctx^.FDTable = nil then begin
        log('Failed to allocate FD table.');
        DL_Free(PDList(ctx^.Resources));
        kfree(void(ctx));
        pop_trace;
        exit;
    end;

    { Per-process working directory }
    ctx^.Cwd := rootDirectory;
    if ctx^.Cwd = nil then begin
        log('Failed to allocate working directory.');
        releaseFileTable(ctx);
        DL_Free(PDList(ctx^.Resources));
        kfree(void(ctx));
        pop_trace;
        exit;
    end;

    { Allocate per-process core.version stack }
    stack := kalloc(PROCESS_STACK_SIZE);
    if stack = nil then begin
        log('Failed to allocate process stack.');
        kfree(void(ctx^.Cwd));
        releaseFileTable(ctx);
        DL_Free(PDList(ctx^.Resources));
        kfree(void(ctx));
        pop_trace;
        exit;
    end;
    ctx^.StackBase := stack;
    ctx^.StackTop := PtrUInt(stack) + PROCESS_STACK_SIZE;

    ctx^.SavedStack := arch.platform.process.prepare(pointer(stack), PROCESS_STACK_SIZE,
        @process_trampoline);

    { Add to process table }
    savedFlags := arch.platform.cpu.lock;
    slotPtr := PProcessSlot(DL_Add(Processes));
    if slotPtr = nil then begin
        arch.platform.cpu.unlock(savedFlags);
        log('Failed to allocate process table slot.');
        if ctx^.StackBase <> nil then
            kfree(ctx^.StackBase);
        if ctx^.Cwd <> nil then
            kfree(void(ctx^.Cwd));
        if ctx^.FDTable <> nil then begin
            releaseFileTable(ctx);
        end;
        if ctx^.Resources <> nil then
            DL_Free(PDList(ctx^.Resources));
        kfree(void(ctx));
        pop_trace;
        exit;
    end;
    slotPtr^ := PtrUInt(ctx);

    { Mark as ready for scheduling }
    if runnable then ctx^.State := psReady;
    arch.platform.cpu.unlock(savedFlags);

    log(name);

    pop_trace;
    createInternal := ctx;
end;

{ Public creation retains its ready-on-return behavior. Commands need their
  arguments and streams installed before the scheduler may enter them. }
function create(name : pchar; entry : TProcessEntryPoint;
                localData : void;
                priority : uint8) : PProcessContext;
begin
    create := createInternal(name, entry, localData, priority, true);
end;

function createSuspended(name: pchar; entry: TProcessEntryPoint;
    localData: void;
    priority: uint8): PProcessContext;
begin
    createSuspended := createInternal(name, entry, localData, priority, false);
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
        arch.platform.cpu.idle;
    end;
end;

{ ---- Find ---- }
function findByID(pid : uint32) : PProcessContext;
var
    i      : uint32;
    slotPtr : PProcessSlot;
    ctx    : PProcessContext;
begin
    findByID := nil;
    if DL_Size(Processes) = 0 then exit;
    for i := 0 to DL_Size(Processes) - 1 do begin
        slotPtr := PProcessSlot(DL_Get(Processes, i));
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
    slotPtr : PProcessSlot;
    ctx    : PProcessContext;
begin
    findByName := nil;
    if DL_Size(Processes) = 0 then exit;
    for i := 0 to DL_Size(Processes) - 1 do begin
        slotPtr := PProcessSlot(DL_Get(Processes, i));
        if slotPtr <> nil then begin
            ctx := PProcessContext(slotPtr^);
            if nameEquals(@ctx^.Name[0], name) then begin
                findByName := ctx;
                exit;
            end;
        end;
    end;
end;

{ ---- Messaging ---- }
procedure sendMessage(pid: uint32; msg: TProcessSysMsg; data: void);
var
    ctx: PProcessContext;
    savedFlags: PtrUInt;
begin
    savedFlags := arch.platform.cpu.lock;
    ctx := findByID(pid);
    if ctx <> nil then begin
        ctx^.MsgData := data;
        ctx^.PendingMsg := msg;
        if (ctx^.State = psAwaiting) or
           ((ctx^.State = psSuspended) and (msg = smResume)) then ctx^.State := psReady;
    end;
    arch.platform.cpu.unlock(savedFlags);
end;

procedure terminate(pid : uint32);
begin
    if pid = 0 then exit;  { Cannot terminate idle }
    if (reaperProcess <> nil) and (pid = reaperProcess^.ProcessID) then exit;
    sendMessage(pid, smTerminate, nil);
end;

procedure kill(pid: uint32);
var
    ctx: PProcessContext;
    savedFlags: PtrUInt;
begin
    if pid = 0 then exit;
    savedFlags := arch.platform.cpu.lock;
    ctx := findByID(pid);
    if (ctx <> nil) and (ctx <> reaperProcess) then begin
        ctx^.State := psFinished;
        ctx^.ExitCode := High(uint32);
        requestReap;
    end;
    arch.platform.cpu.unlock(savedFlags);
end;

{ ---- Process self-management ---- }
procedure proc_yield;
var
    savedFlags: PtrUInt;
begin
    if CurrentProcess <> nil then begin
        savedFlags := arch.platform.cpu.lock;
        CurrentProcess^.TicksUsed := CurrentProcess^.Quantum;
        arch.platform.cpu.unlock(savedFlags);
        { Next timer tick will preempt us }
        arch.platform.cpu.idle;
    end;
end;

procedure proc_sleep_ms(ms: uint32);
var
    remaining: uint64;
    previous, now, delta: uint32;
begin
    remaining := (uint64(ms) * PIT_INPUT_HZ + uint64(PIT_DIVISOR) * 1000 - 1) div (PIT_DIVISOR * 1000);
    if remaining = 0 then remaining := 1;
    previous := arch.platform.process.timerTicks;
    repeat
        proc_yield;
        now := arch.platform.process.timerTicks;
        if now >= previous then delta := now - previous
        else delta := (High(uint32) - previous) + now + 1;
        previous := now;
        if remaining <= delta then exit;
        remaining := remaining - delta;
    until false;
end;

procedure proc_await;
begin
    { Caller must set CurrentProcess^.State := psAwaiting before calling.
      This procedure just spin-waits until an ISR sets the state back
      to something other than psAwaiting. }
    if CurrentProcess <> nil then begin
        while PProcessState(@CurrentProcess^.State)^ = psAwaiting do
            arch.platform.cpu.idle;
    end;
end;

procedure proc_suspend;
var
    savedFlags: PtrUInt;
begin
    if CurrentProcess <> nil then begin
        savedFlags := arch.platform.cpu.lock;
        CurrentProcess^.State := psSuspended;
        arch.platform.cpu.unlock(savedFlags);
        arch.platform.cpu.idle;
    end;
end;

procedure proc_exit(exitCode : uint32);
begin
    if CurrentProcess <> nil then begin
        CurrentProcess^.ExitCode := exitCode;
        CurrentProcess^.State := psFinished;
        while true do begin
            arch.platform.cpu.idle;
        end;
    end;
end;

{ ---- Resource binding ---- }
procedure bindResource(ctx: PProcessContext; kind: TResourceKind; handle: void; cleanup: TResourceCleanup);
var
    binding: PResourceBinding;
    savedFlags: PtrUInt;
begin
    if ctx = nil then exit;
    savedFlags := arch.platform.cpu.lock;
    if ctx^.Resources <> nil then begin
        binding := PResourceBinding(DL_Add(PDList(ctx^.Resources)));
        if binding <> nil then begin
            binding^.Kind := kind;
            binding^.Handle := handle;
            binding^.Cleanup := cleanup;
        end;
    end;
    arch.platform.cpu.unlock(savedFlags);
end;

procedure unbindResource(ctx: PProcessContext; handle: void);
var
    resList: PDList;
    binding: PResourceBinding;
    i: uint32;
    cleanup: TResourceCleanup;
    savedFlags: PtrUInt;
begin
    if ctx = nil then exit;
    savedFlags := arch.platform.cpu.lock;
    resList := PDList(ctx^.Resources);
    cleanup := nil;
    if DL_Size(resList) > 0 then for i := 0 to DL_Size(resList) - 1 do begin
        binding := PResourceBinding(DL_Get(resList, i));
        if binding^.Handle = handle then begin
            cleanup := binding^.Cleanup;
            DL_Delete(resList, i);
            break;
        end;
    end;
    arch.platform.cpu.unlock(savedFlags);
    if assigned(cleanup) then cleanup(handle);
end;

procedure unbindResourceNoCleanup(ctx: PProcessContext; handle: void);
var
    resList: PDList;
    binding: PResourceBinding;
    i: uint32;
    savedFlags: PtrUInt;
begin
    if ctx = nil then exit;
    savedFlags := arch.platform.cpu.lock;
    resList := PDList(ctx^.Resources);
    if DL_Size(resList) > 0 then for i := 0 to DL_Size(resList) - 1 do begin
        binding := PResourceBinding(DL_Get(resList, i));
        if binding^.Handle = handle then begin
            DL_Delete(resList, i);
            break;
        end;
    end;
    arch.platform.cpu.unlock(savedFlags);
end;

procedure unbindAllResources(ctx : PProcessContext);
var
    resList : PDList;
    binding : PResourceBinding;
    i       : sint32;
    savedFlags: PtrUInt;
begin
    if ctx = nil then exit;
    savedFlags := arch.platform.cpu.lock;
    resList := PDList(ctx^.Resources);
    if resList = nil then begin
        arch.platform.cpu.unlock(savedFlags);
        exit;
    end;
    { Detach early so cleanup callbacks that re-enter find nothing }
    ctx^.Resources := nil;
    arch.platform.cpu.unlock(savedFlags);
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
    savedFlags: PtrUInt;
begin
    ctx := createInternal(name, @legacy_entry, void(method), 1, false);
    if ctx <> nil then begin
        ctx^.MsgData := void(params);
        ctx^.StdIn := stdin_buf;
        ctx^.StdOut := stdout_buf;
        ctx^.StdErr := stderr_buf;
        { Publish only after all fields read by legacy_entry are initialized.
          psCreated is also runnable, so creation must use psSuspended. }
        savedFlags := arch.platform.cpu.lock;
        ctx^.State := psReady;
        arch.platform.cpu.unlock(savedFlags);
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
    slotPtr : PProcessSlot;
begin
    getProcessByIndex := nil;
    if Processes = nil then exit;
    if idx >= DL_Size(Processes) then exit;
    slotPtr := PProcessSlot(DL_Get(Processes, idx));
    if slotPtr <> nil then
        getProcessByIndex := PProcessContext(slotPtr^);
end;

{ ---- Reaping ---- }
procedure reapFinished;
var
    i: sint32;
    ctx: PProcessContext;
    savedFlags: PtrUInt;
begin
    { The reaper calls this in process context, never from the timer ISR.
      Detach under IRQ exclusion before callbacks can re-enter the registry. }
    i := sint32(DL_Size(Processes)) - 1;
    while i >= 0 do begin
        savedFlags := arch.platform.cpu.lock;
        ctx := getProcessByIndex(uint32(i));
        if (ctx <> nil) and (ctx <> CurrentProcess) and (ctx^.ProcessID <> 0) and
           ((ctx^.State = psFinished) or (ctx^.State = psError)) then
            if not fd_table_begin_close(PFDTable(ctx^.FDTable)) then begin
                ctx := nil; { final FD completion wakes the reaper }
            end;
        if (ctx <> nil) and (ctx <> CurrentProcess) and (ctx^.ProcessID <> 0) and
           ((ctx^.State = psFinished) or (ctx^.State = psError)) then begin
            DL_Delete(Processes, uint32(i));
            arch.platform.cpu.unlock(savedFlags);
            releaseFileTable(ctx);
            if ctx^.Cwd <> nil then kfree(void(ctx^.Cwd));
            unbindAllResources(ctx);
            if ctx^.StackBase <> nil then kfree(ctx^.StackBase);
            if ctx^.ParentID <> 0 then
                sendMessage(ctx^.ParentID, smChildExited, void(PtrUInt(ctx^.ProcessID)));
            kfree(void(ctx));
        end else arch.platform.cpu.unlock(savedFlags);
        dec(i);
    end;
end;

{ ---- Scheduler ---- }
function scheduler_pick_next : PProcessContext;
begin
    if (CurrentProcess^.State = psFinished) or (CurrentProcess^.State = psError) then requestReap;
    scheduler_pick_next := proc.scheduler.pickNext(CurrentProcess, IdleProcess,
        DL_Size(Processes), SchedulerIndex, @getProcessByIndex);
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
    slotPtr : PProcessSlot;
    ctx     : PProcessContext;
    stStr   : pchar;
begin
    push_trace('proc.mgr.terminal_command_ps');

    bufWriteStrLn(stdout_buf, 'PID        NAME                      STATE       PRI');
    bufWriteStrLn(stdout_buf, '---------- ------------------------- ----------- ---');

    if (Processes <> nil) and (DL_Size(Processes) > 0) then begin
        for i := 0 to DL_Size(Processes) - 1 do begin
            slotPtr := PProcessSlot(DL_Get(Processes, i));
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
    slotPtr : PProcessSlot;
begin
    push_trace('proc.mgr.init');
    log('INIT BEGIN.');

    nextProcessID := 1;
    fd_set_idle_hook(@requestReap);
    { Create process table }
    Processes := DL_New(SizeOf(PtrUInt));
    SchedulerIndex := 0;

    { Create idle process — PID 0, unkillable, uses core.version main stack }
    IdleProcess := PProcessContext(kalloc(SizeOf(TProcessContext)));
    IdleProcess^.ProcessID := 0;
    copyName(@IdleProcess^.Name[0], 'Idle', 32);
    IdleProcess^.State := psRunning;
    IdleProcess^.Priority := 0;
    IdleProcess^.Quantum := 1;  { Yield to real processes ASAP }
    IdleProcess^.PendingMsg := smNone;
    IdleProcess^.Resources := void(DL_New(SizeOf(TResourceBinding)));
    IdleProcess^.FDTable := void(fd_table_new);
    IdleProcess^.Cwd := rootDirectory;
    { No stack allocation — idle runs on the core.version's original stack }
    slotPtr := PProcessSlot(DL_Add(Processes));
    slotPtr^ := PtrUInt(IdleProcess);
    CurrentProcess := IdleProcess;
    reapPending := false;
    reaperProcess := createInternal('reaper', @reaperEntry, nil, 1, false);
    if reaperProcess <> nil then reaperProcess^.State := psAwaiting;

    log('Idle process created (PID 0).');

    log('INIT END.');
    pop_trace;
end;



end.
