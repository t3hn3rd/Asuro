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

{ Monotonic time must advance while IRQ delivery is masked.
  Prefer the fixed-rate Hyper-V reference counter; RTC-calibrated TSC is a fallback. }
unit core.clock;
interface
function prepare : boolean;
function ready : boolean;
function nowUS : uint64;
function sourceName : pchar;
function errorReason : pchar;
procedure UnitTest;
implementation
uses arch.platform.cpu, io.syslog, test.harness;
var clockReady, clockBusy, referenceClock : boolean;
    failure : pchar;
    frequency, epoch : uint64;

{ Hv#1 is an interface signature, not a vendor string: VirtualBox also
  implements it. Never probe a synthetic MSR without its advertised privilege.
  https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/tlfs/timers }
function referenceAvailable(cpuECX, cpuEDX, maxLeaf, signature, privileges : uint32) : boolean;
begin
    referenceAvailable := ((cpuECX and $80000000)<>0) and
        ((cpuEDX and $20)<>0) and (maxLeaf >= $40000003) and
        (signature=$31237648) and ((privileges and 2)<>0);
end;
function referenceSupported : boolean;
var
    cpu, maximum, signature, privileges: TCPURegisters;
begin
    referenceSupported := false;
    queryCPU(1, 0, cpu);
    if ((cpu.ecx and $80000000) = 0) or ((cpu.edx and $20) = 0) then exit;
    queryCPU($40000000, 0, maximum);
    if maximum.eax < $40000003 then exit;
    queryCPU($40000001, 0, signature);
    if signature.eax <> $31237648 then exit;
    queryCPU($40000003, 0, privileges);
    referenceSupported := referenceAvailable(cpu.ecx, cpu.edx,
        maximum.eax, signature.eax, privileges.eax);
end;

function readReference : uint64;
begin
    readReference := readMSR($40000020);
end;
function referenceUS(value : uint64) : uint64;
begin referenceUS:=value div 10; end; { reference ticks are 100 ns }
function sourceName : pchar;
begin
    if not clockReady then sourceName:='unavailable'
    else if referenceClock then sourceName:='VM reference clock (no calibration)'
    else sourceName:='RTC-calibrated invariant TSC';
end;
function errorReason : pchar;
begin
    if failure=nil then errorReason:='Clock initialization is already running; retry shortly.'
    else errorReason:=failure;
end;

function readCycles : uint64;
begin
    readCycles := readTimestamp;
end;

function supported : boolean;
var
    basic, features, extended, invariant: TCPURegisters;
begin
    supported := false;
    queryCPU(0, 0, basic);
    if basic.eax < 1 then exit;
    queryCPU(1, 0, features);
    if (features.edx and $04000010) <> $04000010 then exit;
    queryCPU($80000000, 0, extended);
    if extended.eax < $80000007 then exit;
    queryCPU($80000007, 0, invariant);
    supported := (invariant.edx and $100) <> 0;
end;
function toUS(cycles, hz : uint64) : uint64;
begin
    toUS := 0;
    if hz=0 then exit;
    { Split before multiplying: raw TSC values can exceed 32 bits every second. }
    toUS := (cycles div hz)*1000000 + ((cycles mod hz)*1000000) div hz;
end;
function acceptSamples(first, second : uint64; var hz : uint64) : boolean;
var delta : uint64;
begin
    acceptSamples := false; hz := 0;
    if (first<1000000) or (first>20000000000) or (second<1000000) or (second>20000000000) then exit;
    if first>second then delta:=first-second else delta:=second-first;
    if delta>first div 100 then exit; { reject >1% calibration disagreement }
    hz := (first+second) div 2; acceptSamples := true;
end;
function rtcSecond(var seconds : uint32) : boolean;
var flags : PtrUInt; before, after, raw, again, mode : uint8;
begin
    { Keep each CMOS index/data transaction together, but never wait under CLI. }
    flags := arch.platform.cpu.lock;
    outb($70,$0A); before:=inb($71);
    outb($70,$00); raw:=inb($71);
    outb($70,$00); again:=inb($71);
    outb($70,$0B); mode:=inb($71);
    outb($70,$0A); after:=inb($71);
    arch.platform.cpu.unlock(flags);
    rtcSecond := false;
    if (((before or after) and $80)<>0) or (raw<>again) then exit;
    if (mode and 4)<>0 then seconds:=raw
    else begin
        if ((raw and $0F)>9) or ((raw shr 4)>5) then exit;
        seconds:=(raw shr 4)*10+(raw and $0F);
    end;
    rtcSecond := seconds<60;
end;
function nextSecond(var previous : uint32; var stamp : uint64) : boolean;
var i, current : uint32; start, now : uint64;
begin
    nextSecond:=false; start:=readCycles;
    for i:=1 to 2000000 do begin
        if rtcSecond(current) then if current<>previous then begin
            if current<>(previous+1) mod 60 then exit;
            previous:=current; stamp:=readCycles; nextSecond:=true; exit;
        end;
        now:=readCycles;
        if (now<start) or (now-start>40000000000) then exit;
    end;
end;
function prepare : boolean;
var flags: PtrUInt; second, attempt, i : uint32;
    first, middle, last, hz : uint64; ok : boolean;
begin
    prepare:=false;
    flags := arch.platform.cpu.lock;
    if clockReady then begin
        arch.platform.cpu.unlock(flags);
        prepare:=true; exit;
    end;
    if clockBusy then begin
        arch.platform.cpu.unlock(flags);
        exit;
    end;
    clockBusy:=true; failure:=nil;
    arch.platform.cpu.unlock(flags);
    ok:=false;
    if referenceSupported then begin
        first:=readReference;
        for i:=1 to 10000 do begin
            last:=readReference;
            if last<first then break;
            if last-first>=10 then begin ok:=true; break; end;
        end;
        if ok then begin
            arch.platform.cpu.lock;
            referenceClock:=true; epoch:=first; clockReady:=true; clockBusy:=false;
            arch.platform.cpu.unlock(flags);
            io.syslog.logln('BENCHCLOCK','Using VM reference clock; no calibration.');
            prepare:=true; exit;
        end;
        failure:='VM reference clock did not advance.';
    end;
    if (flags and $200)=0 then failure:='TSC fallback needs interrupts enabled.'
    else if not supported then failure:='No VM reference clock or invariant TSC available.'
    else begin
        { A transient RTC update or a delayed VM timeslice must not permanently
          reject an otherwise usable clock. Retry bounded full-second samples. }
        for attempt:=1 to 3 do begin
            ok:=false;
            for i:=1 to 10000 do if rtcSecond(second) then begin ok:=true; break; end;
            if ok then ok:=nextSecond(second,first);
            if ok then ok:=nextSecond(second,middle);
            if ok then ok:=nextSecond(second,last);
            if ok then begin
                ok:=(middle>first) and (last>middle);
                if ok then ok:=acceptSamples(middle-first,last-middle,hz);
            end;
            if ok then break;
        end;
        if not ok then failure:='RTC/TSC fallback samples were unstable; retry when the system is idle.';
    end;
    arch.platform.cpu.lock;
    if ok then begin frequency:=hz; epoch:=last; referenceClock:=false; clockReady:=true; end;
    clockBusy:=false;
    arch.platform.cpu.unlock(flags);
    prepare:=ok;
end;
function ready : boolean;
begin ready:=clockReady; end;
function nowUS : uint64;
var value : uint64;
begin
    nowUS:=0;
    if not clockReady then exit;
    if referenceClock then begin
        value:=readReference;
        if value>=epoch then nowUS:=referenceUS(value-epoch);
    end else begin
        value:=readCycles;
        if value>=epoch then nowUS:=toUS(value-epoch,frequency);
    end;
end;
procedure UnitTest;
var hz, first, last : uint64; i : uint32; flags : PtrUInt;
    context : TTestContext;
begin
    test.harness.Start(@context, 'driver.storage.bench.clock');
    test.harness.Assert(@context, referenceAvailable($80000000,$20,$40000006,$31237648,$AF2),'VBox Hv#1 reference clock');
    test.harness.Assert(@context, not referenceAvailable(0,$20,$40000006,$31237648,$AF2),'no hypervisor no MSR');
    test.harness.Assert(@context, not referenceAvailable($80000000,0,$40000006,$31237648,$AF2),'no RDMSR support');
    test.harness.Assert(@context, not referenceAvailable($80000000,$20,$40000002,$31237648,$AF2),'missing feature leaf');
    test.harness.Assert(@context, not referenceAvailable($80000000,$20,$40000006,0,$AF2),'different hypervisor interface');
    test.harness.Assert(@context, not referenceAvailable($80000000,$20,$40000006,$31237648,$AF0),'missing reference privilege');
    test.harness.Assert(@context, referenceUS(10000000)=1000000,'100 ns ticks to microseconds');
    test.harness.Assert(@context, referenceUS(50000000000)=5000000000,'reference conversion beyond uint32');
    test.harness.Assert(@context, referenceUS(9)=0,'reference sub-microsecond truncation');
    { Safe hardware smoke test only when CPUID explicitly grants MSR access.
      No disk I/O and no RTC calibration occurs during boot tests. }
    if referenceSupported then begin
        test.harness.Assert(@context, prepare,'VM reference clock initialization');
        if ready then begin
            flags := arch.platform.cpu.lock;
            first:=nowUS; last:=first;
            for i:=1 to 10000 do begin last:=nowUS; if last>first then break; end;
            arch.platform.cpu.unlock(flags);
            test.harness.Assert(@context, last>first,'VM clock advances with interrupts masked');
        end;
    end;
    test.harness.Assert(@context, acceptSamples(4291845105,4291845105,hz) and (hz=4291845105),'near uint32 frequency boundary');
    test.harness.Assert(@context, acceptSamples(5000000000,5000000000,hz) and (hz=5000000000),'frequency above uint32');
    test.harness.Assert(@context, not acceptSamples(5000000000,5100000000,hz),'reject unstable calibration');
    test.harness.Assert(@context, not acceptSamples(0,0,hz),'reject missing clock');
    test.harness.Assert(@context, toUS(10000000000,5000000000)=2000000,'64-bit elapsed conversion');
    test.harness.Assert(@context, toUS(5000002500,5000000000)=1000000,'fractional microsecond truncation');
    test.harness.Assert(@context, toUS(18000000000000,5000000000)=3600000000,'one hour does not overflow');
    test.harness.Assert(@context, toUS(123,0)=0,'invalid divisor');
    test.harness.Finish(@context);
end;
end.
