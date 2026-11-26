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

unit arch.x86_64.irq;

interface
type
    TIRQHandler = procedure;
    TTimerHandler = procedure(data: void);
function registerIRQ(vector: uint8; handler: TIRQHandler): boolean;
function unregisterIRQ(vector: uint8; handler: TIRQHandler): boolean;
function registerTimer(handler: TTimerHandler): boolean;
procedure init;
procedure dispatch(vector: uint32);
procedure UnitTest;
function ticks: uint64;
{$ifdef ASURO_TEST_STORAGE}
procedure startLatencySample;
procedure reportLatencySample;
{$endif}

implementation
uses {$ifdef ASURO_TEST_STORAGE}core.clock, arch.platform.cpu,{$endif} arch.common.legacyirq, arch.x86_64.util, debug.early, memory.heap;
type
    PIRQHook = ^TIRQHook;
    TIRQHook = record
        Next: PIRQHook;
        Handler: TIRQHandler;
    end;
    PTimerHook = ^TTimerHook;
    TTimerHook = record
        Next: PTimerHook;
        Handler: TTimerHandler;
    end;
var
    hooks: array[0..15] of PIRQHook;
    timerHooks: PTimerHook;
    timerTicks, unexpected, spurious: uint64;
    ready: boolean;
    dispatchDepth: uint32;

{$ifdef ASURO_TEST_STORAGE}
var sampling, sampleInUS: boolean;
    lastTimer, timerGap, maxDeviceTime, deviceCount: uint64;

function sampleClock: uint64;
begin
    if sampleInUS then sampleClock := core.clock.nowUS
    else sampleClock := arch.platform.cpu.readTimestamp;
end;

procedure startLatencySample;
var flags: PtrUInt;
begin
    sampleInUS := core.clock.prepare;
    flags := lockIRQ;
    lastTimer := 0;
    timerGap := 0;
    maxDeviceTime := 0;
    deviceCount := 0;
    sampling := true;
    unlockIRQ(flags);
end;

procedure reportLatencySample;
var flags: PtrUInt;
begin
    flags := lockIRQ;
    if not sampling then begin
        unlockIRQ(flags);
        puts('SKIP: IRQ latency clock unavailable'#13#10);
        exit;
    end;
    sampling := false;
    unlockIRQ(flags);
    field('IRQ_DEVICE_SAMPLES', deviceCount);
    if sampleInUS then begin
        field('IRQ_DEVICE_TO_EOI_MAX_US', maxDeviceTime);
        field('IRQ_TIMER_GAP_MAX_US', timerGap);
    end else begin
        field('IRQ_DEVICE_TO_EOI_MAX_TSC', maxDeviceTime);
        field('IRQ_TIMER_GAP_MAX_TSC', timerGap);
    end;
end;
{$endif}

function registerIRQ(vector: uint8; handler: TIRQHandler): boolean;
var
    node, current: PIRQHook;
    flags: PtrUInt;
begin
    registerIRQ := false;
    if (vector < 32) or (vector > 47) or (handler = nil) then exit;
    flags := lockIRQ;
    current := hooks[vector - 32];
    while current <> nil do begin
        if current^.Handler = handler then begin
            unlockIRQ(flags);
            registerIRQ := true;
            exit;
        end;
        current := current^.Next;
    end;
    node := PIRQHook(kalloc(sizeof(TIRQHook)));
    if node <> nil then begin
        node^.Handler := handler;
        node^.Next := hooks[vector - 32];
        hooks[vector - 32] := node;
        registerIRQ := true;
    end;
    unlockIRQ(flags);
end;

{ Removal runs outside dispatch on the BSP. The caller must quiesce the
  device before detaching its handler, especially on a shared PIC line. }
function unregisterIRQ(vector: uint8; handler: TIRQHandler): boolean;
var link: ^PIRQHook;
    node: PIRQHook;
    flags: PtrUInt;
begin
    unregisterIRQ := false;
    if (vector < 32) or (vector > 47) or (handler = nil) then exit;
    flags := lockIRQ;
    if dispatchDepth = 0 then begin
        link := @hooks[vector - 32];
        while link^ <> nil do begin
            node := link^;
            if node^.Handler = handler then begin
                link^ := node^.Next;
                kfree(void(node));
                unregisterIRQ := true;
                break;
            end;
            link := @node^.Next;
        end;
    end;
    unlockIRQ(flags);
end;

function registerTimer(handler: TTimerHandler): boolean;
var
    node, current: PTimerHook;
    flags: PtrUInt;
begin
    registerTimer := false;
    if handler = nil then exit;
    flags := lockIRQ;
    current := timerHooks;
    while current <> nil do begin
        if current^.Handler = handler then begin
            unlockIRQ(flags);
            registerTimer := true;
            exit;
        end;
        current := current^.Next;
    end;
    node := PTimerHook(kalloc(sizeof(TTimerHook)));
    if node <> nil then begin
        node^.Handler := handler;
        node^.Next := timerHooks;
        timerHooks := node;
        registerTimer := true;
    end;
    unlockIRQ(flags);
end;

procedure init;
begin
    asm
        cli
    end;
    remap($FF, $FF);
    timerTicks := 0;
    unexpected := 0;
    spurious := 0;
    timerStart;
    ready := true;
end;

function ticks: uint64;
begin
    ticks := PUInt64(@timerTicks)^;
end;

procedure dispatch(vector: uint32);
var
    line: uint8;
    hook: PIRQHook;
    timer: PTimerHook;
    {$ifdef ASURO_TEST_STORAGE}started, elapsed: uint64;{$endif}
begin
    if (not ready) or (vector < 32) or (vector > 47) then begin
        puts('FAIL: IRQ dispatched before controller setup'#13#10);
        bootstrap_halt;
    end;
    line := vector - 32;
    if not realIRQ(line) then begin
        inc(spurious);
        exit;
    end;
    {$ifdef ASURO_TEST_STORAGE}
    started := 0;
    if sampling then begin
        started := sampleClock;
        if line = 0 then begin
            if lastTimer <> 0 then begin
                elapsed := started - lastTimer;
                if elapsed > timerGap then timerGap := elapsed;
            end;
            lastTimer := started;
        end;
    end;
    {$endif}
    inc(dispatchDepth);
    if line = 0 then begin
        inc(timerTicks);
        timer := timerHooks;
        while timer <> nil do begin
            timer^.Handler(nil);
            timer := timer^.Next;
        end;
    end else if hooks[line] = nil then
        inc(unexpected);
    hook := hooks[line];
    while hook <> nil do begin
        hook^.Handler;
        hook := hook^.Next;
    end;
    {$ifdef ASURO_TEST_STORAGE}
    if sampling and (line <> 0) then begin
        elapsed := sampleClock - started;
        inc(deviceCount);
        if elapsed > maxDeviceTime then maxDeviceTime := elapsed;
    end;
    {$endif}
    acknowledge(line);
    dec(dispatchDepth);
end;

{$ifdef UNIT_TESTS}
var testFirst, testSecond: uint32;
    removedInHandler: boolean;

procedure firstTestHandler;
begin
    inc(testFirst);
    removedInHandler := unregisterIRQ(35, @firstTestHandler);
end;

procedure secondTestHandler;
begin
    inc(testSecond);
end;
{$endif}

procedure UnitTest;
var
    attempts, failed: uint32;
    saved, beforeTicks: uint64;
    allocation: void;

    procedure Assert(condition: boolean; name: pchar);
    begin
        if condition then puts('PASS: ') else begin
            inc(failed);
            puts('FAIL: ');
        end;
        puts(name);
        puts(#13#10);
    end;
begin
    failed := 0;
    { Synthetic spurious vectors must return without delivering device work. }
    asm
        int $27;
        int $2F
    end;
    Assert((spurious = 2) and (unexpected = 0), 'PIC spurious IRQ7/IRQ15 filtered');
    masks($FE, $FF); { only IRQ0; no storage or keyboard IRQs yet }
    beforeTicks := ticks;
    asm
        sti
    end;
    attempts := 0;
    { Bounded polling, not HLT: a missing timer must report failure. }
    while (ticks - beforeTicks < 16) and (attempts < 10000000) do begin
        asm
            pause
        end;
        inc(attempts);
    end;
    saved := lockIRQ;
    Assert((saved and $200) <> 0, 'IRQ return restores interrupt enable');
    Assert(ticks - beforeTicks >= 16, 'PIT delivers repeated hardware interrupts');
    beforeTicks := ticks;
    for attempts := 1 to 10000 do asm
        pause
    end;
    Assert(ticks = beforeTicks, 'CLI excludes timer interrupts');
    unlockIRQ(saved);
    allocation := memory.heap.kalloc(17);
    saved := lockIRQ;
    Assert((saved and $200) <> 0, 'heap allocation preserves enabled interrupts');
    unlockIRQ(saved);
    memory.heap.kfree(allocation);
    saved := lockIRQ;
    Assert((saved and $200) <> 0, 'heap release preserves enabled interrupts');
    masks($FF, $FF);
    {$ifdef UNIT_TESTS}
    Assert(registerIRQ(35, @firstTestHandler), 'register first shared IRQ handler');
    Assert(registerIRQ(35, @secondTestHandler), 'register second shared IRQ handler');
    dispatch(35);
    Assert((testFirst = 1) and (testSecond = 1) and not removedInHandler,
           'shared dispatch rejects handler removal during traversal');
    Assert(unregisterIRQ(35, @firstTestHandler), 'detach shared IRQ handler');
    dispatch(35);
    Assert((testFirst = 1) and (testSecond = 2), 'remaining shared IRQ handler still runs');
    Assert(not unregisterIRQ(35, @firstTestHandler), 'already detached IRQ handler is absent');
    Assert(unregisterIRQ(35, @secondTestHandler), 'detach final IRQ handler');
    {$endif}
    Assert(unexpected = 0, 'no unexpected hardware IRQs');
    field('IRQ_TIMER_TICKS', ticks);
    field('IRQ_TESTS_FAILED', failed);
    if failed <> 0 then bootstrap_halt;
end;
end.
