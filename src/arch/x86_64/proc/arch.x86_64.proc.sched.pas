// Copyright 2026 Aaron Hance
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

{ Adapter between saved CPU contexts and the shared process manager. }
unit arch.x86_64.proc.sched;

interface
procedure init;
procedure UnitTest;

implementation
uses proc.mgr, proc.types, io.stdio, core.strings, driver.storage.fdtable, arch.x86_64.context, arch.x86_64.util,
     arch.x86_64.irq, arch.common.legacyirq, memory.heap, memory.raw,
     core.ds.dynamic, debug.early;
var
    switches, cleaned, returned, woke, exited, forbidden: uint32;
    childID, parentID: uint32;
    cleanupCtx: PProcessContext;
    commandParams: PParamList;
    commandBuffer: POutBuf;
    commandValid, sleepValid, asyncRetained: boolean;
    asyncEntry: PFileDescriptor;
    fdReleased: uint32;

function selectProcess(saved: PtrUInt): PtrUInt;
begin
    CurrentProcess^.SavedStack := saved;
    CurrentProcess := scheduler_pick_next;
    inc(switches);
    selectProcess := CurrentProcess^.SavedStack;
end;

procedure init;
begin
    { Caller owns IRQ exclusion; proc.mgr.init must have installed idle. }
    setSelector(@selectProcess);
end;

procedure cleanupResource(handle: void);
begin
    inc(cleaned);
    { Re-enter cleanup to verify the resource was detached before invocation. }
    unbindResource(cleanupCtx, handle);
    kfree(handle);
end;

procedure parentWorker(ctx: PProcessContext);
var
    flags: PtrUInt;
begin
    flags := lockIRQ;
    if ctx^.PendingMsg <> smChildExited then ctx^.State := psAwaiting;
    unlockIRQ(flags);
    proc_await;
    if (ctx^.PendingMsg = smChildExited) and (PtrUInt(ctx^.MsgData) = childID) then inc(woke);
    inc(returned);
end;

procedure childWorker(ctx: PProcessContext);
begin
    inc(exited);
    proc_exit(7);
    inc(forbidden);
end;

procedure forbiddenWorker(ctx: PProcessContext);
begin
    inc(forbidden);
end;

procedure closeChildFD(data: pointer);
begin
    inc(fdReleased);
    kfree(void(data));
end;

procedure commandWorker(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
type PState = ^TProcessState;
var
    start: uint64;
    held: PProcessContext;
begin
    commandValid := (params = commandParams) and (stdin_buf = commandBuffer) and
        (stdout_buf = commandBuffer) and (stderr_buf = commandBuffer);
    start := ticks;
    proc_sleep_ms(2);
    sleepValid := ticks - start >= (uint64(2) * PIT_INPUT_HZ + PIT_DIVISOR * 1000 - 1) div (PIT_DIVISOR * 1000);
    held := findByID(childID);
    if held <> nil then begin
        while (PState(@held^.State)^ <> psFinished) and (ticks - start < 1000) do proc_yield;
        asyncRetained := (held^.State = psFinished) and fd_has_async(asyncEntry);
        fd_end_async(asyncEntry);
    end;
end;

procedure UnitTest;
type PCommandBuffer = ^TCommandBuffer;
var
    input: PCommandBuffer;
    parent, child, killed: PProcessContext;
    beforeFree: SizeUInt;
    started: uint64;
    flags: PtrUInt;
    list: PDList;
    slot: ^PtrUInt;
    i, failed, passed, baseCount: uint32;

    procedure Assert(condition: boolean; name: pchar);
    begin
        if condition then begin
            inc(passed);
            puts('PASS: ');
        end
        else begin
            inc(failed);
            puts('FAIL: ');
        end;
        puts(name);
        puts(#13#10);
    end;
begin
    failed := 0;
    passed := 0;
    beforeFree := lmm_total_free;
    baseCount := processCount;
    list := DL_New(sizeof(PtrUInt));
    for i := 0 to 79 do begin
        slot := pointer(DL_Add(list));
        slot^ := PtrUInt($1234567800000000) + i;
    end;
    slot := pointer(DL_Insert(list, 1));
    slot^ := 777;
    Assert(PUInt64(DL_Get(list, 2))^ = uint64($1234567800000001), 'native dynamic list overlapping insertion');
    DL_Delete(list, 1);
    Assert(PUInt64(DL_Get(list, 79))^ = uint64($123456780000004F), 'native dynamic list growth and deletion');
    DL_Clear(list);
    DL_ShrinkToFit(list);
    slot := pointer(DL_Add(list));
    Assert((slot <> nil) and (slot^ = 0), 'empty dynamic list regrows with zeroed slots');
    DL_Free(list);
    Assert(lmm_total_free = beforeFree, 'dynamic list releases allocation ownership');

    cleaned := 0;
    returned := 0;
    woke := 0;
    exited := 0;
    forbidden := 0;
    parent := createSuspended('lifecycle parent', @parentWorker, nil, 1);
    child := createSuspended('lifecycle child', @childWorker, nil, 3);
    killed := createSuspended('never run', @forbiddenWorker, nil, 1);
    parentID := parent^.ProcessID;
    childID := child^.ProcessID;
    child^.ParentID := parentID;
    asyncRetained := false;
    fdReleased := 0;
    asyncEntry := @PFDTable(child^.FDTable)^.Entries[0];
    asyncEntry^.InUse := true;
    asyncEntry^.FSPrivate := pointer(kalloc(11));
    asyncEntry^.FSCloseHook := @closeChildFD;
    fd_begin_async(asyncEntry);
    cleanupCtx := parent;
    bindResource(parent, rkCustom, kalloc(37), @cleanupResource);
    Assert((findByID(parentID) = parent) and (findByName('lifecycle child') = child), 'process lookup preserves native pointers');
    Assert((parent^.State = psSuspended) and (child^.State = psSuspended), 'processes stay suspended until published');
    kill(killed^.ProcessID);
    Assert(killed^.State = psFinished, 'killed suspended process never published for execution');
    input := PCommandBuffer(kalloc(sizeof(TCommandBuffer)));
    memory.raw.move(pchar('echo scheduled'), input, 14);
    commandParams := getParams(input^);
    kfree(void(input));
    commandBuffer := createOutBuf(1);
    commandValid := false;
    sleepValid := false;
    runCommand('scheduled ECHO', findCommand('echo')^.method, commandParams,
        nil, commandBuffer, nil);
    runCommand('lifecycle command', @commandWorker, commandParams,
        commandBuffer, commandBuffer, commandBuffer);
    parent^.State := psReady;
    child^.State := psReady;
    started := ticks;
    masks($FE, $FF);
    asm
        sti
    end;
    repeat
        asm
            pause
        end;
    until (processCount = baseCount) or (ticks - started > 16000);
    flags := lockIRQ;
    masks($FF, $FF);
    Assert((flags and $200) <> 0, 'process lifecycle preserves interrupt state');
    Assert((returned = 1) and (exited = 1) and (forbidden = 0), 'return and explicit exit never resume finished processes');
    Assert(woke = 1, 'child completion wakes awaiting parent');
    Assert(cleaned = 1, 'resource callback runs exactly once under reentry');
    Assert((processCount = baseCount) and (CurrentProcess = IdleProcess), 'reaper removes finished processes and retains system tasks');
    Assert(commandValid, 'command arguments and streams installed before execution');
    Assert(sleepValid, 'process sleep uses the programmed PIT rate');
    Assert(asyncRetained and (fdReleased = 1), 'reaper waits for async FD completion then closes exactly once');
    Assert(stringEquals(commandBuffer^.buf, 'scheduled '#10), 'shared ECHO executes through scheduler');
    freeParams(commandParams);
    freeOutBuf(commandBuffer);
    Assert(lmm_total_free = beforeFree, 'process contexts, stacks, CWD and resources freed');
    field('PROCESS_TESTS_PASSED', passed);
    field('PROCESS_TESTS_FAILED', failed);
    if failed <> 0 then bootstrap_halt;
end;
end.
