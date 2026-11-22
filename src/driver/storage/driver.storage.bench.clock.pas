{ Benchmark time must advance while IRQ delivery is masked.
  Prefer the fixed-rate Hyper-V reference counter; RTC-calibrated TSC is a fallback. }
unit driver.storage.bench.clock;
interface
function prepare : boolean;
function ready : boolean;
function nowUS : uint64;
function sourceName : pchar;
function errorReason : pchar;
procedure UnitTest;
implementation
uses arch.x86.util, io.syslog;
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
var cpuECX, cpuEDX, maxLeaf, signature, privileges : uint32;
begin
    referenceSupported:=false;
    asm
        push ebx
        mov eax,1
        cpuid
        mov cpuECX,ecx
        mov cpuEDX,edx
        pop ebx
    end;
    if ((cpuECX and $80000000)=0) or ((cpuEDX and $20)=0) then exit;
    asm
        push ebx
        mov eax,$40000000
        cpuid
        mov maxLeaf,eax
        mov eax,$40000001
        cpuid
        mov signature,eax
        pop ebx
    end;
    if (maxLeaf<$40000003) or (signature<>$31237648) then exit;
    asm
        push ebx
        mov eax,$40000003
        cpuid
        mov privileges,eax
        pop ebx
    end;
    referenceSupported:=referenceAvailable(cpuECX,cpuEDX,maxLeaf,signature,privileges);
end;
function readReference : uint64;
var hi, lo : uint32;
begin
    asm
        mov ecx,$40000020
        rdmsr
        mov lo,eax
        mov hi,edx
    end;
    readReference:=(uint64(hi) shl 32) or lo;
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
var hi, lo : uint32;
begin
    { prepare checks SSE2 and invariant TSC before this is ever used. }
    asm
        lfence
        rdtsc
        mov lo,eax
        mov hi,edx
        lfence
    end;
    readCycles := (uint64(hi) shl 32) or lo;
end;
function supported : boolean;
var basic, extended, features, invariant : uint32;
begin
    asm
        push ebx
        xor eax,eax
        cpuid
        mov basic,eax
        mov eax,1
        cpuid
        mov features,edx
        mov eax,$80000000
        cpuid
        mov extended,eax
        pop ebx
    end;
    supported := false;
    if (basic<1) or ((features and $04000010)<>$04000010) or (extended<$80000007) then exit;
    asm
        push ebx
        mov eax,$80000007
        cpuid
        mov invariant,edx
        pop ebx
    end;
    supported := (invariant and $100)<>0;
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
var flags : uint32; before, after, raw, again, mode : uint8;
begin
    { Keep each CMOS index/data transaction together, but never wait under CLI. }
    asm pushfd; cli; pop flags end;
    outb($70,$0A); before:=inb($71);
    outb($70,$00); raw:=inb($71);
    outb($70,$00); again:=inb($71);
    outb($70,$0B); mode:=inb($71);
    outb($70,$0A); after:=inb($71);
    if (flags and $200)<>0 then asm sti end;
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
var flags, second, attempt, i : uint32;
    first, middle, last, hz : uint64; ok : boolean;
begin
    prepare:=false;
    asm pushfd; cli; pop flags end;
    if clockReady then begin
        if (flags and $200)<>0 then asm sti end;
        prepare:=true; exit;
    end;
    if clockBusy then begin
        if (flags and $200)<>0 then asm sti end;
        exit;
    end;
    clockBusy:=true; failure:=nil;
    if (flags and $200)<>0 then asm sti end;
    ok:=false;
    if referenceSupported then begin
        first:=readReference;
        for i:=1 to 10000 do begin
            last:=readReference;
            if last<first then break;
            if last-first>=10 then begin ok:=true; break; end;
        end;
        if ok then begin
            asm cli end;
            referenceClock:=true; epoch:=first; clockReady:=true; clockBusy:=false;
            if (flags and $200)<>0 then asm sti end;
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
    asm cli end;
    if ok then begin frequency:=hz; epoch:=last; referenceClock:=false; clockReady:=true; end;
    clockBusy:=false;
    if (flags and $200)<>0 then asm sti end;
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
var hz, first, last : uint64; passed, failed, flags, i : uint32;
    procedure Assert(ok : boolean; name : pchar);
    begin if ok then Inc(passed) else begin Inc(failed); io.syslog.logln('BENCHCLOCK FAIL',name); end; end;
begin
    passed:=0;failed:=0;
    Assert(referenceAvailable($80000000,$20,$40000006,$31237648,$AF2),'VBox Hv#1 reference clock');
    Assert(not referenceAvailable(0,$20,$40000006,$31237648,$AF2),'no hypervisor no MSR');
    Assert(not referenceAvailable($80000000,0,$40000006,$31237648,$AF2),'no RDMSR support');
    Assert(not referenceAvailable($80000000,$20,$40000002,$31237648,$AF2),'missing feature leaf');
    Assert(not referenceAvailable($80000000,$20,$40000006,0,$AF2),'different hypervisor interface');
    Assert(not referenceAvailable($80000000,$20,$40000006,$31237648,$AF0),'missing reference privilege');
    Assert(referenceUS(10000000)=1000000,'100 ns ticks to microseconds');
    Assert(referenceUS(50000000000)=5000000000,'reference conversion beyond uint32');
    Assert(referenceUS(9)=0,'reference sub-microsecond truncation');
    { Safe hardware smoke test only when CPUID explicitly grants MSR access.
      No disk I/O and no RTC calibration occurs during boot tests. }
    if referenceSupported then begin
        Assert(prepare,'VM reference clock initialization');
        if ready then begin
            asm pushfd; cli; pop flags end;
            first:=nowUS; last:=first;
            for i:=1 to 10000 do begin last:=nowUS; if last>first then break; end;
            if (flags and $200)<>0 then asm sti end;
            Assert(last>first,'VM clock advances with interrupts masked');
        end;
    end;
    Assert(acceptSamples(4291845105,4291845105,hz) and (hz=4291845105),'near uint32 frequency boundary');
    Assert(acceptSamples(5000000000,5000000000,hz) and (hz=5000000000),'frequency above uint32');
    Assert(not acceptSamples(5000000000,5100000000,hz),'reject unstable calibration');
    Assert(not acceptSamples(0,0,hz),'reject missing clock');
    Assert(toUS(10000000000,5000000000)=2000000,'64-bit elapsed conversion');
    Assert(toUS(5000002500,5000000000)=1000000,'fractional microsecond truncation');
    Assert(toUS(18000000000000,5000000000)=3600000000,'one hour does not overflow');
    Assert(toUS(123,0)=0,'invalid divisor');
    io.syslog.log('BENCHCLOCK','Passed: '); io.syslog.writeint(passed);
    io.syslog.writestring(' Failed: '); io.syslog.writeintln(failed);
end;
end.
