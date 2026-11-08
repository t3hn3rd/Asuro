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

{ Architecture context mechanism only. Scheduling policy stays in proc.*.
  A saved context points at an aligned 512-byte FX image followed by the
  normalized interrupt-frame pointer. Only kernel contexts are supported. }
unit arch.x86_64.context;

interface
type
    PNative = ^PtrUInt;
    { Exact order produced by isr/entry.asm. Long mode always pushes SS/RSP,
      even without a privilege transition; only the error code is conditional. }
    PFrame = ^TFrame;
    TFrame = packed record
        cr2: uint64;
        r15, r14, r13, r12, r11, r10, r9, r8: uint64;
        rdi, rsi, rbp, rbx, rdx, rcx, rax: uint64;
        vector, error, rip, cs, flags, rsp, ss: uint64;
    end;

    TSelectContext = function(saved: PtrUInt): PtrUInt;
procedure setSelector(selector: TSelectContext);
function prepare(stack: pointer; bytes: SizeUInt; entry: pointer; argument: PtrUInt): PtrUInt;
procedure UnitTest;

implementation
uses proc.types, proc.scheduler, arch.x86_64.util, arch.x86_64.irq, arch.common.legacyirq, memory.heap, debug.early;
var
    choose: TSelectContext;
    testProcesses: array[0..2] of PProcessContext;
    testCurrent: PProcessContext;
    testCursor: uint32;
    testDone: array[0..1] of uint32;
    testFailures: uint32;
    testSwitches: uint32;

procedure setSelector(selector: TSelectContext);
begin
    { Caller owns IRQ exclusion and context lifetimes. }
    choose := selector;
end;

function selectContext(saved: PtrUInt): PtrUInt; cdecl; [public, alias: 'x64_select_context'];
var
    frame: PFrame;
begin
    selectContext := saved;
    frame := PFrame(PNative(saved + 512)^);
    if (frame^.vector = 32) and assigned(choose) then
        selectContext := choose(saved);
end;

function prepare(stack: pointer; bytes: SizeUInt; entry: pointer; argument: PtrUInt): PtrUInt;
var
    top, frameAddress, fx: PtrUInt;
    frame: PFrame;
begin
    prepare := 0;
    if (stack = nil) or (entry = nil) or (bytes < 2048) or
       (PtrUInt(stack) > High(PtrUInt) - bytes) then exit;
    top := (PtrUInt(stack) + bytes) and not PtrUInt(15);
    { SysV entry has RSP mod 16 = 8, as if CALL pushed a return address. }
    top := top - 8;
    PNative(top)^ := PtrUInt(@bootstrap_halt);
    frameAddress := top - sizeof(TFrame);
    fx := (frameAddress - 528) and not PtrUInt(15);
    zero(pointer(fx), top - fx);
    frame := PFrame(frameAddress);
    frame^.rdi := argument;
    frame^.rip := PtrUInt(entry);
    frame^.cs := $18;
    frame^.ss := $10;
    frame^.flags := $202;
    frame^.rsp := top;
    PUInt16(fx)^ := $037F; { initial x87 control word; empty tag word }
    PUInt32(fx + 24)^ := $1F80; { initial MXCSR }
    PNative(fx + 512)^ := frameAddress;
    prepare := fx;
end;

function testGetProcess(index: uint32): PProcessContext;
begin
    if index < 3 then testGetProcess := testProcesses[index] else testGetProcess := nil;
end;

function testSelect(saved: PtrUInt): PtrUInt;
begin
    testCurrent^.SavedStack := saved;
    testCurrent := proc.scheduler.pickNext(testCurrent, testProcesses[0], 3,
        testCursor, @testGetProcess);
    inc(testSwitches);
    testSelect := testCurrent^.SavedStack;
end;

function testRegisters(counter: PUInt32; pattern: uint64): uint32; cdecl; external name 'x64_test_context_registers';

procedure worker(index: PtrUInt); cdecl;
var
    value: PtrUInt;
    allocation: void;
begin
    value := PtrUInt($1234567800000000) + index;
    allocation := memory.heap.kalloc(17 + index);
    PUInt64(allocation)^ := value;
    if testRegisters(@testSwitches, value) <> 1 then inc(testFailures);
    if (PUInt64(allocation)^ <> value) or
       (value <> PtrUInt($1234567800000000) + index) then inc(testFailures);
    memory.heap.kfree(allocation);
    asm
        cli
    end;
    testProcesses[index + 1]^.State := psFinished;
    PUInt32(@testDone[index])^ := 1;
    asm
        sti
    end;
    { The next timer moves away permanently; stack is freed by bootstrap. }
    while true do asm
        pause
    end;
end;

procedure UnitTest;
var
    stackA, stackB: void;
    beforeFree: SizeUInt;
    attempts, i: uint32;
    saved: PtrUInt;
begin
    beforeFree := lmm_total_free;
    stackA := kalloc(16384);
    stackB := kalloc(16384);
    for i := 0 to 2 do begin
        testProcesses[i] := PProcessContext(kalloc(sizeof(TProcessContext)));
        testProcesses[i]^.ProcessID := i;
        testProcesses[i]^.Quantum := 1;
        testProcesses[i]^.State := psReady;
    end;
    testProcesses[1]^.SavedStack := prepare(pointer(stackA), 16384, @worker, 0);
    testProcesses[2]^.SavedStack := prepare(pointer(stackB), 16384, @worker, 1);
    if (testProcesses[1]^.SavedStack = 0) or (testProcesses[2]^.SavedStack = 0) then begin
        puts('FAIL: prepare kernel contexts'#13#10);
        bootstrap_halt;
    end;
    testCurrent := testProcesses[0];
    testCurrent^.State := psRunning;
    testCursor := 0;
    testDone[0] := 0;
    testDone[1] := 0;
    testFailures := 0;
    testSwitches := 0;
    setSelector(@testSelect);
    masks($FE, $FF);
    asm
        sti
    end;
    attempts := 0;
    while ((PUInt32(@testDone[0])^ = 0) or (PUInt32(@testDone[1])^ = 0)) and
          (attempts < 10000000) do begin
        inc(attempts);
        asm
            pause
        end;
    end;
    saved := lockIRQ;
    masks($FF, $FF);
    setSelector(nil);
    if (testDone[0] = 0) or (testDone[1] = 0) or (testSwitches < 6) or
       ((saved and $200) = 0) then inc(testFailures);
    kfree(stackA);
    kfree(stackB);
    for i := 0 to 2 do begin
        kfree(void(testProcesses[i]));
        testProcesses[i] := nil;
    end;
    if lmm_total_free <> beforeFree then inc(testFailures);
    field('CONTEXT_SWITCHES', testSwitches);
    field('CONTEXT_TESTS_FAILED', testFailures);
    if testFailures <> 0 then begin
        puts('FAIL: preemptive kernel contexts'#13#10);
        bootstrap_halt;
    end;
    puts('PASS: two kernel contexts preserve registers/x87/SSE, allocate and release stacks'#13#10);
end;
end.
