{ Read-only raw storage benchmark. No disk I/O is performed by UnitTest. }
unit driver.storage.bench;
interface
procedure init;
procedure UnitTest;
implementation
uses boot.mgr, io.stdio, io.syslog, core.strings, core.util, arch.x86.util,
     arch.x86.bda, arch.x86.isr.tmr0, memory.heap, proc.mgr, proc.types,
     driver.storage.types, driver.storage.mgr, core.ds.cfifo, driver.storage.bench.clock;
const
    MAX_DEPTH = 32;
    DEFAULT_MIB = 128;
    AUTO_MIB = 32;
    MIN_SAMPLE_US = 10000; { avoid presenting millisecond cache hits as drive ratings }
type
    PCaseResult = ^TCaseResult;
    TCaseResult = record
        Name : pchar;
        KiB, Depth : uint32;
        RandomRead, Measured : boolean;
        Error : TError;
        Rate10, IOPS, AvgUS, P95US, Bytes : uint64;
        Elapsed : uint64;
    end;
    PBench = ^TBench;
    PSlot = ^TSlot;
    TSlot = record
        Owner : PBench;
        Buffer : puint32;
        State, LBA, Sectors : uint32; { State: 0 free, 1 DMA, 2 completed }
        Started : uint64;
    end;
    TBench = record
        Device : PStorage_Device;
        Process : PProcessContext;
        Buffer : pointer;
        Depth, RequestBytes, ChunkSectors, StartLBA, Span, Remaining, Seed : uint32;
        RandomRead : boolean;
        Active, Peak, WakeSequence, Accepted, Completed, Successful : uint32;
        Error : TError;
        ErrorLBA : uint32;
        StartTick, Elapsed, LatencyMax : uint64;
        Bytes, LatencyTotal : uint64;
        Histogram : array[0..31] of uint32;
        BeforeStats, AfterStats : TStorageStats;
        Slots : array[0..MAX_DEPTH-1] of TSlot;
    end;

function nowTick : uint64;
begin nowTick := driver.storage.bench.clock.nowUS; end;

{ Reject overflow before multiplication; CLI parsing must never wrap. }
function parseNumber(text : pchar; limit : uint32; var value : uint32) : boolean;
var i, digit : uint32;
begin
    parseNumber := false; value := 0;
    if (text=nil) or (text[0]=#0) then exit;
    i := 0;
    while text[i]<>#0 do begin
        if (text[i]<'0') or (text[i]>'9') then exit;
        digit := ord(text[i])-ord('0');
        if (value>limit div 10) or ((value=limit div 10) and (digit>limit mod 10)) then exit;
        value := value*10+digit; Inc(i);
    end;
    parseNumber := true;
end;

function ticksToUS(ticks : uint64) : uint64;
begin ticksToUS := ticks; end; { samples now use independent hardware microseconds }
function perSecond(value, ticks : uint64) : uint64;
begin
    perSecond := 0;
    if ticks<>0 then perSecond := (value*1000000) div ticks;
end;
function latencyBucket(ticks : uint64) : uint32;
var bucket : uint32;
begin
    bucket := 0;
    while (ticks<>0) and (bucket<31) do begin Inc(bucket); ticks := ticks shr 1; end;
    latencyBucket := bucket;
end;
function p95Ticks(run : PBench) : uint64;
var target, count, i : uint32;
begin
    p95Ticks := 0;
    if run^.Completed=0 then exit;
    target := run^.Completed - run^.Completed div 20; count := 0;
    for i := 0 to 31 do begin
        Inc(count,run^.Histogram[i]);
        if count>=target then begin
            if i=31 then p95Ticks := run^.LatencyMax
            else p95Ticks := (uint32(1) shl i)-1;
            exit;
        end;
    end;
end;

procedure writeNumber(output : POutBuf; value : uint64);
var digits : array[0..20] of char; n : uint32;
begin
    n := 0;
    repeat digits[n] := char(ord('0')+value mod 10); value := value div 10; Inc(n); until value=0;
    while n>0 do begin Dec(n); bufWriteChar(output,digits[n]); end;
end;
procedure writeValue(output : POutBuf; name : pchar; value : uint64);
begin bufWriteStr(output,name); writeNumber(output,value); end;

{ All geometry arithmetic is bounded before buffer allocation or I/O. }
function configure(run : PBench; device : PStorage_Device; mib, kib, depth, start : uint32;
                   explicitStart, randomRead : boolean) : boolean;
var sectors : uint64;
begin
    configure := false;
    if device=nil then exit;
    if device^.removed or (device^.dispatchRead=nil) or (device^.maxSectorCount=0) then exit;
    if (device^.sectorSize=0) or (device^.sectorSize>1048576) then exit;
    if (mib=0) or (mib>16384) or (kib=0) or (kib>1024) or (depth=0) or (depth>MAX_DEPTH) then exit;
    if ((kib*1024) mod device^.sectorSize)<>0 then exit;
    sectors := (uint64(mib) shl 20) div device^.sectorSize;
    if not explicitStart then begin
        start := 0;
        if device^.maxSectorCount>2048 then
            if sectors<=device^.maxSectorCount-2048 then start := 2048;
    end;
    if start>=device^.maxSectorCount then exit;
    if sectors>device^.maxSectorCount-start then sectors := device^.maxSectorCount-start;
    if sectors=0 then exit;
    run^.Device := device; run^.Depth := depth; run^.RequestBytes := kib*1024;
    run^.ChunkSectors := run^.RequestBytes div device^.sectorSize;
    run^.StartLBA := start; run^.Span := uint32(sectors); run^.Remaining := run^.Span;
    run^.Seed := $6D2B79F5; run^.RandomRead := randomRead;
    configure := true;
end;

procedure planRead(run : PBench; slot : PSlot);
var span : uint32;
begin
    slot^.Sectors := run^.ChunkSectors;
    if slot^.Sectors>run^.Remaining then slot^.Sectors := run^.Remaining;
    if run^.RandomRead then begin
        run^.Seed := run^.Seed xor (run^.Seed shl 13);
        run^.Seed := run^.Seed xor (run^.Seed shr 17);
        run^.Seed := run^.Seed xor (run^.Seed shl 5);
        span := run^.Span-slot^.Sectors+1;
        slot^.LBA := run^.StartLBA + run^.Seed mod span;
    end else slot^.LBA := run^.StartLBA + (run^.Span-run^.Remaining);
    Dec(run^.Remaining,slot^.Sectors);
end;

procedure readDone(error : TError; data : pointer);
var slot : PSlot; run : PBench; ticks : uint64;
begin
    slot := PSlot(data); run := slot^.Owner;
    ticks := nowTick-slot^.Started;
    Inc(run^.Completed); Inc(run^.LatencyTotal,ticks);
    if ticks>run^.LatencyMax then run^.LatencyMax := ticks;
    Inc(run^.Histogram[latencyBucket(ticks)]);
    if error=eNone then begin
        Inc(run^.Successful); Inc(run^.Bytes,uint64(slot^.Sectors)*run^.Device^.sectorSize);
    end else if run^.Error=eNone then begin run^.Error := error; run^.ErrorLBA := slot^.LBA; end;
    Dec(run^.Active); slot^.State := 2;
    if run^.Process<>nil then run^.Process^.State := psReady;
    Inc(run^.WakeSequence);
end;

{ Task context only. Reserve before submit to support immediate callbacks.
  Stop submitting on the first error, but drain accepted DMA before freeing. }
procedure execute(run : PBench);
var i, flags, wake, attemptedActive : uint32; slot : PSlot; err : TError; finished, ready : boolean;
begin
    run^.Process := CurrentProcess;
    for i := 0 to run^.Depth-1 do begin
        run^.Slots[i].Owner := run;
        run^.Slots[i].Buffer := puint32(uint32(run^.Buffer)+i*run^.RequestBytes);
    end;
    storage_get_stats(run^.Device,run^.BeforeStats); run^.StartTick := nowTick;
    repeat
        for i := 0 to run^.Depth-1 do begin
            asm pushfd; cli; pop flags end;
            slot := @run^.Slots[i];
            if slot^.State=2 then slot^.State := 0;
            if (slot^.State=0) and (run^.Remaining>0) and (run^.Error=eNone) then begin
                planRead(run,slot); slot^.State := 1; slot^.Started := nowTick;
                Inc(run^.Active); Inc(run^.Accepted); attemptedActive := run^.Active;
                err := storage_read_async(run^.Device,slot^.LBA,slot^.Sectors,slot^.Buffer,@readDone,slot);
                if err<>eNone then begin
                    Dec(run^.Active); Dec(run^.Accepted); slot^.State := 0;
                    if run^.Error=eNone then begin run^.Error := err; run^.ErrorLBA := slot^.LBA; end;
                end;
                if (err=eNone) and (attemptedActive>run^.Peak) then run^.Peak := attemptedActive;
            end;
            if (flags and $200)<>0 then asm sti end;
        end;
        asm pushfd; cli; pop flags end;
        finished := (run^.Active=0) and ((run^.Remaining=0) or (run^.Error<>eNone));
        ready := false;
        for i := 0 to run^.Depth-1 do if run^.Slots[i].State=2 then ready := true;
        wake := run^.WakeSequence;
        if not finished and not ready and (run^.Process<>nil) then run^.Process^.State := psAwaiting;
        if (flags and $200)<>0 then asm sti end;
        if not finished and not ready then
            while puint32(@run^.WakeSequence)^=wake do asm hlt end;
    until finished;
    run^.Elapsed := nowTick-run^.StartTick;
    storage_get_stats(run^.Device,run^.AfterStats);
end;

procedure report(run : PBench; output, errors : POutBuf);
var rate, ticks, commands : uint64;
begin
    if run^.Error<>eNone then begin
        writeValue(errors,'Read failed at LBA ',run^.ErrorLBA);
        writeValue(errors,', error=',ord(run^.Error));
        bufWriteStrLn(errors,'. All accepted reads drained; results below are partial.');
    end;
    writeValue(output,'  Read ',run^.Bytes div 1024); bufWriteStr(output,' KiB');
    writeValue(output,' in ',ticksToUS(run^.Elapsed)); bufWriteStr(output,' us; ');
    if run^.Elapsed<MIN_SAMPLE_US then bufWriteStrLn(output,'sample shorter than 10 ms; use a larger disk/range.')
    else begin
        rate := perSecond(run^.Bytes*10,run^.Elapsed) div 1048576;
        writeNumber(output,rate div 10); bufWriteChar(output,'.'); writeNumber(output,rate mod 10);
        bufWriteStr(output,' MiB/s; '); writeNumber(output,perSecond(run^.Successful,run^.Elapsed)); bufWriteStrLn(output,' IOPS');
    end;
    writeValue(output,'  Requests accepted/completed/successful: ',run^.Accepted);
    writeValue(output,' / ',run^.Completed); writeValue(output,' / ',run^.Successful);
    writeValue(output,'; peak outstanding: ',run^.Peak); bufWriteNewLine(output);
    if run^.Completed>0 then begin
        writeValue(output,'  Latency avg: ',ticksToUS(run^.LatencyTotal) div run^.Completed);
        ticks := p95Ticks(run);
        if ticks=0 then writeValue(output,' us; p95 < ',ticksToUS(1)+1)
        else writeValue(output,' us; p95 < ',ticksToUS(ticks+1)+1);
        writeValue(output,' us; max < ',ticksToUS(uint64(run^.LatencyMax)+1)+1);
        bufWriteStrLn(output,' us (hardware clock; p95 uses log buckets)');
    end;
    commands := uint32(run^.AfterStats.Commands-run^.BeforeStats.Commands);
    writeValue(output,'  Device deltas: commands=',commands);
    writeValue(output,', merged=',uint32(run^.AfterStats.Merged-run^.BeforeStats.Merged));
    writeValue(output,', failed=',uint32(run^.AfterStats.Failed-run^.BeforeStats.Failed));
    writeValue(output,', queue-full=',uint32(run^.AfterStats.QueueFull-run^.BeforeStats.QueueFull));
    bufWriteNewLine(output);

end;

function runCase(device : PStorage_Device; mib, kib, depth, start : uint32;
                 explicitStart, randomRead : boolean; output, errors : POutBuf;
                 summary : PCaseResult) : boolean;
var run : PBench;
begin
    runCase := false;
    run := PBench(kalloc(sizeof(TBench)));
    if summary<>nil then summary^.Error := eOutOfMemory;
    if run=nil then begin bufWriteStrLn(errors,'Out of memory allocating benchmark state.'); exit; end;
    memset(uint32(run),0,sizeof(TBench));
    if not configure(run,device,mib,kib,depth,start,explicitStart,randomRead) then begin
        if summary<>nil then summary^.Error := eInvalidArgument;
        bufWriteStrLn(errors,'Invalid/unreadable device, range, or request size (must be a whole number of device sectors).');
        kfree(void(run)); exit;
    end;
    run^.Buffer := kalloc(run^.Depth*run^.RequestBytes);
    if run^.Buffer=nil then begin bufWriteStrLn(errors,'Out of memory allocating benchmark buffers.'); kfree(void(run)); exit; end;
    memset(uint32(run^.Buffer),0,run^.Depth*run^.RequestBytes);
    if summary=nil then begin
        if randomRead then bufWriteStr(output,'Random') else bufWriteStr(output,'Sequential');
        writeValue(output,' read: ',kib); writeValue(output,' KiB/request, depth=',depth);
        writeValue(output,', LBA=',run^.StartLBA);
        writeValue(output,', span=',uint64(run^.Span)*device^.sectorSize div 1024); bufWriteStrLn(output,' KiB');
    end;
    execute(run); runCase := run^.Error=eNone;
    if summary=nil then report(run,output,errors)
    else begin
        summary^.Error := run^.Error; summary^.Bytes := run^.Bytes;
        summary^.Elapsed := run^.Elapsed; summary^.Measured := run^.Elapsed>=MIN_SAMPLE_US;
        if summary^.Measured then begin
            summary^.Rate10 := perSecond(run^.Bytes*10,run^.Elapsed) div 1048576;
            summary^.IOPS := perSecond(run^.Successful,run^.Elapsed);
        end;
        if run^.Completed>0 then begin
            summary^.AvgUS := ticksToUS(run^.LatencyTotal) div run^.Completed;
            summary^.P95US := ticksToUS(uint64(p95Ticks(run))+1)+1;
        end;
        if run^.Error<>eNone then begin
            writeValue(errors,'Read failed at LBA ',run^.ErrorLBA);
            writeValue(errors,', error=',ord(run^.Error)); bufWriteStrLn(errors,'. Accepted reads drained.');
        end;
    end;
    kfree(run^.Buffer); kfree(void(run));
end;

{ Fixed-width ASCII output stays readable in terminals and redirected logs. }
procedure textCell(output : POutBuf; text : pchar; width : uint32);
var i : uint32;
begin
    i := 0;
    while (i<width) and (text[i]<>#0) do begin bufWriteChar(output,text[i]); Inc(i); end;
    while i<width do begin bufWriteChar(output,' '); Inc(i); end;
end;
procedure numberCell(output : POutBuf; value : uint64; width : uint32; decimal : boolean);
var copyValue : uint64; digits : uint32;
begin
    copyValue := value; digits := 0;
    repeat Inc(digits); copyValue := copyValue div 10; until copyValue=0;
    if decimal then begin if digits<2 then digits:=2; Inc(digits); end;
    while digits<width do begin bufWriteChar(output,' '); Inc(digits); end;
    if decimal then begin writeNumber(output,value div 10); bufWriteChar(output,'.'); writeNumber(output,value mod 10); end
    else writeNumber(output,value);
end;
procedure tableLine(output : POutBuf);
begin bufWriteStrLn(output,'-------------------------------------------------------------------------------'); end;
procedure tableHeader(output : POutBuf);
begin
    tableLine(output);
    textCell(output,'Workload',18); textCell(output,'   KiB',6); textCell(output,'  QD',4);
    textCell(output,'     MiB/s',10); textCell(output,'      IOPS',10);
    textCell(output,'    Avg us',10); textCell(output,'   P95< us',10); bufWriteStrLn(output,'  Status');
    tableLine(output);
end;
procedure tableRow(output : POutBuf; summary : PCaseResult);
begin
    textCell(output,summary^.Name,18); numberCell(output,summary^.KiB,6,false);
    numberCell(output,summary^.Depth,4,false);
    if (summary^.Error=eNone) and summary^.Measured then begin
        numberCell(output,summary^.Rate10,10,true); numberCell(output,summary^.IOPS,10,false);
        numberCell(output,summary^.AvgUS,10,false); numberCell(output,summary^.P95US,10,false);
        bufWriteStrLn(output,'  OK');
    end else begin
        bufWriteStr(output,'         -         -         -         -');
        if summary^.Error<>eNone then bufWriteStrLn(output,'  FAILED') else bufWriteStrLn(output,'  SHORT');
    end;
end;
function suiteProfile(index : uint32; automatic : boolean; hardwareDepth : uint32;
                      summary : PCaseResult) : boolean;
var queued : uint32;
begin
    suiteProfile := false;
    memset(uint32(summary),0,sizeof(TCaseResult));
    queued := hardwareDepth; if queued<4 then queued:=4; if queued>16 then queued:=16;
    if automatic then begin
        if index>=6 then exit;
        case index of
            0:begin summary^.Name:='Seq large'; summary^.KiB:=1024; summary^.Depth:=1; end;
            1:begin summary^.Name:='Seq queued'; summary^.KiB:=1024; summary^.Depth:=queued; end;
            2:begin summary^.Name:='Seq medium'; summary^.KiB:=64; summary^.Depth:=queued; end;
            3:begin summary^.Name:='Random small'; summary^.KiB:=4; summary^.Depth:=1; end;
            4:begin summary^.Name:='Random queued'; summary^.KiB:=4; summary^.Depth:=queued; end;
            5:begin summary^.Name:='Random medium'; summary^.KiB:=64; summary^.Depth:=queued; end;
        end;
        summary^.RandomRead := index>=3;
    end else begin
        if index>=12 then exit;
        summary^.Name := 'Sequential';
        case index div 4 of 0:summary^.KiB:=4; 1:summary^.KiB:=64; 2:summary^.KiB:=1024; end;
        case index mod 4 of 0:summary^.Depth:=1; 1:summary^.Depth:=4; 2:summary^.Depth:=16; 3:summary^.Depth:=32; end;
    end;
    suiteProfile := true;
end;
procedure queueGain(output : POutBuf; name : pchar; baseline, queued : PCaseResult);
begin
    if (baseline^.Error<>eNone) or (queued^.Error<>eNone) or
       not baseline^.Measured or not queued^.Measured or (baseline^.Rate10=0) then exit;
    bufWriteStr(output,name); numberCell(output,(queued^.Rate10*10) div baseline^.Rate10,0,true);
    bufWriteStrLn(output,'x QD1 throughput');
end;
procedure runSuite(device : PStorage_Device; disk, mib : uint32; automatic : boolean;
                   output, errors : POutBuf);
var summaries, row : PCaseResult; count, i, completed, bestSeq, bestRandom : uint32;
    totalBytes, totalTicks : uint64; ok : boolean;
begin
    if automatic then count:=6 else count:=12;
    summaries := PCaseResult(kalloc(count*sizeof(TCaseResult)));
    if summaries=nil then begin bufWriteStrLn(errors,'Out of memory allocating results.'); exit; end;
    memset(uint32(summaries),0,count*sizeof(TCaseResult));
    bufWriteNewLine(output); tableLine(output);
    if automatic then bufWriteStrLn(output,'  STORAGE BENCHMARK / AUTO') else bufWriteStrLn(output,'  STORAGE BENCHMARK / COMPARE');
    writeValue(output,'  Disk ',disk); writeValue(output,' | ',mib); writeValue(output,' MiB/profile | ',count);
    writeValue(output,' profiles | hardware QD ',device^.maxActive); bufWriteNewLine(output);
    bufWriteStrLn(output,'  Raw read throughput (includes host/drive cache effects).');
    bufWriteStrLn(output,'  Asuro filesystem cache bypassed. Host/drive caches are not flushed.');
    bufWriteStrLn(output,'  Profiles reuse the same range; later reads may be warm-cache hits.');
    writeValue(output,'  Device capacity: ',(uint64(device^.maxSectorCount)*device^.sectorSize) div 1048576); bufWriteStrLn(output,' MiB');
    if (uint64(mib) shl 20)>uint64(device^.maxSectorCount)*device^.sectorSize then
        bufWriteStrLn(output,'  Requested size exceeds this disk; each profile is clamped to capacity.');
    tableHeader(output);
    completed:=0; bestSeq:=$FFFFFFFF; bestRandom:=$FFFFFFFF; totalBytes:=0; totalTicks:=0;
    for i:=0 to count-1 do begin
        row:=@summaries[i];
        if not suiteProfile(i,automatic,device^.maxActive,row) then break;
        { Keep the small-request profiles usable on larger-sector devices. }
        if (row^.KiB*1024<device^.sectorSize) and (device^.sectorSize<=1048576) then
            row^.KiB:=(device^.sectorSize+1023) div 1024;
        ok:=runCase(device,mib,row^.KiB,row^.Depth,0,false,row^.RandomRead,output,errors,row);
        tableRow(output,row); Inc(totalBytes,row^.Bytes); Inc(totalTicks,row^.Elapsed);
        if not ok then break;
        Inc(completed);
        if row^.Measured then begin
            if not row^.RandomRead then begin
                if bestSeq=$FFFFFFFF then bestSeq:=i
                else if row^.Rate10>summaries[bestSeq].Rate10 then bestSeq:=i;
            end else begin
                if bestRandom=$FFFFFFFF then bestRandom:=i
                else if row^.IOPS>summaries[bestRandom].IOPS then bestRandom:=i;
            end;
        end;
    end;
    tableLine(output);
    if bestSeq<>$FFFFFFFF then begin
        bufWriteStr(output,'  Best sequential: '); numberCell(output,summaries[bestSeq].Rate10,0,true);
        writeValue(output,' MiB/s (',summaries[bestSeq].KiB); writeValue(output,' KiB, QD ',summaries[bestSeq].Depth); bufWriteStrLn(output,')');
    end;
    if bestRandom<>$FFFFFFFF then begin
        writeValue(output,'  Peak random: ',summaries[bestRandom].IOPS); bufWriteStr(output,' IOPS (');
        writeNumber(output,summaries[bestRandom].KiB); writeValue(output,' KiB, QD ',summaries[bestRandom].Depth); bufWriteStrLn(output,')');
    end;
    if automatic then begin
        if completed>=2 then queueGain(output,'  Sequential queue gain: ',@summaries[0],@summaries[1]);
        if completed>=5 then queueGain(output,'  Small random queue gain: ',@summaries[3],@summaries[4]);
    end;
    writeValue(output,'  Finished ',completed); writeValue(output,'/',count);
    writeValue(output,' profiles | read ',totalBytes div 1024);
    writeValue(output,' KiB | measured ',ticksToUS(totalTicks) div 1000); bufWriteStrLn(output,' ms');
    if completed<count then bufWriteStrLn(output,'  Suite stopped after an error; remaining profiles were not run.');
    bufWriteStrLn(output,'  P95 is a microsecond-bucket bound. SHORT means less than 10 ms.');
    bufWriteStrLn(output,'  Virtual/cached/sparse reads can exceed physical drive speed.');
    tableLine(output); kfree(void(summaries));
end;

type TBenchMode = (bmAuto, bmCompare, bmManual, bmList, bmHelp);
function commandMode(first : pchar; count : uint32; var base : uint32) : TBenchMode;
begin
    base:=0; commandMode:=bmAuto;
    if count=0 then exit;
    if stringEqualsCI(first,'help') then commandMode:=bmHelp
    else if stringEqualsCI(first,'list') then commandMode:=bmList
    else if stringEqualsCI(first,'auto') then begin commandMode:=bmAuto; base:=1; end
    else if stringEqualsCI(first,'compare') then begin commandMode:=bmCompare; base:=1; end
    else if stringEqualsCI(first,'run') then begin commandMode:=bmManual; base:=1; end
    else if count>2 then commandMode:=bmManual; { retain detailed numeric syntax }
end;
procedure usage(output : POutBuf);
begin
    bufWriteStrLn(output,'STORBENCH [disk] [MiB]             Default six-profile suite');
    bufWriteStrLn(output,'STORBENCH auto [disk] [MiB]        Same suite (default 32 MiB/profile)');
    bufWriteStrLn(output,'STORBENCH list                     List disks and capacities');
    bufWriteStrLn(output,'STORBENCH compare [disk] [MiB]     Twelve sequential cases');
    bufWriteStrLn(output,'STORBENCH run [disk] [MiB] [KiB/request] [depth] [seq|random] [start_lba]');
    bufWriteStrLn(output,'Examples: STORBENCH 2 512       STORBENCH run 2 512 64 4');
    bufWriteStrLn(output,'Manual defaults: disk 0, 128 MiB, 1024 KiB/request, depth up to 4, sequential.');
    bufWriteStrLn(output,'Limits: 1..16384 MiB, 1..1024 KiB/request, depth 1..32; sizes clamp to disk.');
    bufWriteStrLn(output,'Read-only. Cached/sparse VM reads do not measure physical media speed.');
end;
procedure listDisks(output : POutBuf);
var count, i : uint32; device : PStorage_Device;
begin
    count:=get_device_count;
    if count=0 then begin bufWriteStrLn(output,'No storage devices.'); exit; end;
    bufWriteStrLn(output,'Disk  Controller            MiB     Sector bytes  HW QD');
    tableLine(output);
    for i:=0 to count-1 do begin
        device:=get_device(i);
        if device<>nil then begin
            numberCell(output,i,4,false); bufWriteStr(output,'  ');
            textCell(output,controller_type_2_string(device^.controller),16);
            numberCell(output,(uint64(device^.maxSectorCount)*device^.sectorSize) div 1048576,9,false);
            numberCell(output,device^.sectorSize,17,false); numberCell(output,device^.maxActive,7,false);
            if device^.removed then bufWriteStr(output,'  removed');
            bufWriteNewLine(output);
        end;
    end;
    bufWriteStrLn(output,'Select a disk and MiB per profile: STORBENCH 2 512');
end;
procedure command(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var count, disk, mib, kib, depth, start, base : uint32;
    mode : TBenchMode; randomRead, explicitStart : boolean; device : PStorage_Device; first : pchar;
begin
    count:=paramCount(params); first:=nil;
    if count>0 then first:=getParam(0,params);
    mode:=commandMode(first,count,base);
    if mode=bmHelp then begin usage(stdout_buf); exit; end;
    if mode=bmList then begin
        if count<>1 then usage(stderr_buf) else listDisks(stdout_buf);
        exit;
    end;
    if ((mode<>bmManual) and (count>base+2)) or ((mode=bmManual) and (count>base+6)) then begin usage(stderr_buf); exit; end;
    disk:=0; mib:=DEFAULT_MIB; kib:=1024; start:=0;
    if mode=bmAuto then mib:=AUTO_MIB;
    randomRead:=false; explicitStart:=false;
    if count>base then if not parseNumber(getParam(base,params),$FFFFFFFF,disk) then begin usage(stderr_buf); exit; end;
    if count>base+1 then if not parseNumber(getParam(base+1,params),16384,mib) or (mib=0) then begin usage(stderr_buf); exit; end;
    device:=get_device(disk);
    if device=nil then begin bufWriteStrLn(stderr_buf,'Storage device not found. Use STORBENCH list.'); exit; end;
    depth:=device^.maxActive; if depth>4 then depth:=4; if depth=0 then depth:=1;
    if mode=bmManual then begin
        if count>base+2 then if not parseNumber(getParam(base+2,params),1024,kib) or (kib=0) then begin usage(stderr_buf); exit; end;
        if count>base+3 then if not parseNumber(getParam(base+3,params),MAX_DEPTH,depth) or (depth=0) then begin usage(stderr_buf); exit; end;
        if count>base+4 then begin
            randomRead:=stringEqualsCI(getParam(base+4,params),'random');
            if not randomRead and not stringEqualsCI(getParam(base+4,params),'seq') then begin usage(stderr_buf); exit; end;
        end;
        if count>base+5 then begin
            explicitStart:=true;
            if not parseNumber(getParam(base+5,params),$FFFFFFFF,start) then begin usage(stderr_buf); exit; end;
        end;
    end;
    if not driver.storage.bench.clock.prepare then begin
        bufWriteStr(stderr_buf,'Benchmark clock unavailable: ');
        bufWriteStrLn(stderr_buf,driver.storage.bench.clock.errorReason); exit;
    end;
    bufWriteStr(stdout_buf,'Clock: '); bufWriteStrLn(stdout_buf,driver.storage.bench.clock.sourceName);
    if mode<>bmManual then begin runSuite(device,disk,mib,mode=bmAuto,stdout_buf,stderr_buf); exit; end;
    writeValue(stdout_buf,'Disk ',disk); writeValue(stdout_buf,', sector bytes=',device^.sectorSize);
    writeValue(stdout_buf,', hardware depth=',device^.maxActive); bufWriteNewLine(stdout_buf);
    bufWriteStrLn(stdout_buf,'Virtual/cached/sparse reads can exceed physical media speed. Device deltas include background I/O.');
    runCase(device,mib,kib,depth,start,explicitStart,randomRead,stdout_buf,stderr_buf,nil);
end;

type
    PBenchMock = ^TBenchMock;
    TBenchMock = record
        Pending : array[0..3] of PIORequest;
        Count, Batch, Calls, FailLBA : uint32;
        InvalidRange : boolean;
    end;
procedure testDispatch(device : PStorage_Device; request : PIORequest);
var mock : PBenchMock; pending : PIORequest;
begin
    mock := PBenchMock(device^.controllerId0); Inc(mock^.Calls);
    if (request^.RequestType<>ioRead) or (request^.LBA>=device^.maxSectorCount) or
       (request^.SectorCount>device^.maxSectorCount-request^.LBA) then mock^.InvalidRange := true;
    mock^.Pending[mock^.Count] := request; Inc(mock^.Count);
    if mock^.Count=mock^.Batch then while mock^.Count>0 do begin
        Dec(mock^.Count); pending := mock^.Pending[mock^.Count];
        if pending^.LBA=mock^.FailLBA then complete_io(pending,false,eIOError)
        else complete_io(pending,true,eNone);
    end;
end;

procedure UnitTest;
var run : PBench; device : PStorage_Device; slot : PSlot; value, i, passed, failed : uint32;
    mock : PBenchMock; buffer : pointer; summary : PCaseResult;
    procedure Assert(ok : boolean; name : pchar);
    begin if ok then Inc(passed) else begin Inc(failed); io.syslog.logln('STORBENCH FAIL',name); end; end;
begin
    passed := 0; failed := 0;
    Assert(parseNumber('4294967295',$FFFFFFFF,value) and (value=$FFFFFFFF),'parse uint32 max');
    Assert(not parseNumber('4294967296',$FFFFFFFF,value),'reject numeric overflow');
    Assert(not parseNumber('-1',16384,value),'reject negative');
    Assert(not parseNumber('',16384,value),'reject empty');
    Assert(not parseNumber('1x',16384,value),'reject trailing junk');
    Assert((commandMode(nil,0,value)=bmAuto) and (value=0),'no args select suite');
    Assert((commandMode('2',2,value)=bmAuto) and (value=0),'disk and size select suite');
    Assert((commandMode('auto',3,value)=bmAuto) and (value=1),'explicit auto arguments');
    Assert((commandMode('run',7,value)=bmManual) and (value=1),'explicit manual arguments');
    Assert((commandMode('2',4,value)=bmManual) and (value=0),'legacy detailed arguments');
    Assert(commandMode('list',1,value)=bmList,'disk list mode');
    driver.storage.bench.clock.UnitTest;
    Assert(ticksToUS(1234567)=1234567,'hardware microseconds');
    Assert(perSecond(1,1000000)=1,'hardware rate conversion');
    Assert(perSecond(uint64(4096) shl 20,2000000)=(uint64(4096) shl 20) div 2,'rate beyond 4 GiB');
    Assert(perSecond(100,0)=0,'zero ticks');
    Assert((latencyBucket(0)=0) and (latencyBucket(1)=1) and (latencyBucket(3)=2) and (latencyBucket($FFFFFFFF)=31),'latency buckets');
    summary := PCaseResult(kalloc(sizeof(TCaseResult)));
    if summary<>nil then begin
        Assert(suiteProfile(0,true,32,summary) and (summary^.KiB=1024) and (summary^.Depth=1) and not summary^.RandomRead,'auto sequential baseline');
        Assert(suiteProfile(1,true,32,summary) and (summary^.Depth=16),'auto caps queued depth');
        Assert(suiteProfile(1,true,1,summary) and (summary^.Depth=4),'auto tests software queue on serial devices');
        Assert(suiteProfile(3,true,8,summary) and (summary^.KiB=4) and (summary^.Depth=1) and summary^.RandomRead,'auto random baseline');
        Assert(suiteProfile(4,true,8,summary) and (summary^.KiB=4) and (summary^.Depth=8) and summary^.RandomRead,'auto random queued');
        Assert(suiteProfile(5,true,8,summary) and (summary^.KiB=64) and summary^.RandomRead,'auto medium random');
        Assert(not suiteProfile(6,true,8,summary),'auto has exactly six cases');
        Assert(suiteProfile(11,false,1,summary) and (summary^.KiB=1024) and (summary^.Depth=32),'compare retains full matrix');
        Assert(not suiteProfile(12,false,1,summary),'compare has exactly twelve cases');
        kfree(void(summary));
    end else Assert(false,'suite test allocation');
    run := PBench(kalloc(sizeof(TBench))); device := PStorage_Device(kalloc(sizeof(TStorage_Device)));
    if (run=nil) or (device=nil) then begin
        if run<>nil then kfree(void(run)); if device<>nil then kfree(void(device));
        io.syslog.logln('STORBENCH FAIL','test allocation'); exit;
    end;
    memset(uint32(run),0,sizeof(TBench)); memset(uint32(device),0,sizeof(TStorage_Device));
    device^.dispatchRead := @testDispatch; device^.sectorSize := 512; device^.maxSectorCount := $FFFFFFFF;
    Assert(configure(run,device,4096,1024,32,0,true,false) and (run^.Span=8388608),'4 GiB transfer does not wrap');
    Assert(not configure(run,device,1,1024,33,0,true,false),'depth memory cap');
    Assert(not configure(run,device,1,0,1,0,true,false),'zero request rejected');
    Assert(not configure(run,device,1,4,1,$FFFFFFFF,true,false),'start beyond device rejected');
    Assert(configure(run,device,1,4,1,$FFFFFFFE,true,false) and (run^.Span=1),'range clamp near uint32 end');
    slot := @run^.Slots[0]; planRead(run,slot);
    Assert((slot^.LBA=$FFFFFFFE) and (slot^.Sectors=1) and (run^.Remaining=0),'short final request');
    device^.maxSectorCount := 4096;
    Assert(configure(run,device,1,4,4,0,false,true) and (run^.StartLBA=2048),'default starting LBA');
    for i := 1 to 256 do begin
        planRead(run,slot);
        Assert((slot^.LBA>=2048) and (slot^.LBA<=4096-slot^.Sectors),'random request stays in range');
    end;
    Assert(run^.Remaining=0,'random workload has exact sector count');
    device^.sectorSize := 2048;
    Assert(not configure(run,device,1,1,1,0,true,false),'request sector alignment');
    run^.Completed := 20; run^.Histogram[0] := 18; run^.Histogram[2] := 1; run^.Histogram[10] := 1;
    Assert(p95Ticks(run)=3,'95th percentile excludes slowest five percent');
    { Synthetic driver only: callbacks arrive inline in reverse groups of four. }
    mock := PBenchMock(kalloc(sizeof(TBenchMock))); buffer := kalloc(4*65536);
    device^.requestQueue := CFIFO_New(sizeof(pointer),8);
    if (mock<>nil) and (buffer<>nil) and (device^.requestQueue<>nil) then begin
        memset(uint32(mock),0,sizeof(TBenchMock)); mock^.Batch := 4; mock^.FailLBA := $FFFFFFFF;
        device^.controllerId0 := uint32(mock); device^.sectorSize := 512; device^.maxActive := 4;
        memset(uint32(run),0,sizeof(TBench)); run^.Buffer := buffer;
        Assert(configure(run,device,1,64,4,0,true,false),'configure queued mock');
        execute(run);
        Assert((run^.Accepted=16) and (run^.Completed=16) and (run^.Bytes=1048576),'queued reads complete exact byte count');
        Assert((run^.Peak=4) and (mock^.Count=0) and (run^.Active=0),'reverse groups drain at configured depth');
        Assert(not mock^.InvalidRange,'benchmark issues only in-range reads');
        memset(uint32(run),0,sizeof(TBench)); run^.Buffer := buffer; mock^.FailLBA := 128;
        Assert(configure(run,device,1,64,4,0,true,false),'configure failing mock');
        execute(run);
        Assert((run^.Error=eIOError) and (run^.Accepted=4) and (run^.Completed=4),'failure stops new submissions and drains accepted requests');
        Assert((run^.Bytes=3*65536) and (run^.Active=0),'failed reads excluded from throughput');
        memset(uint32(run),0,sizeof(TBench)); run^.Buffer := buffer; mock^.FailLBA := $FFFFFFFF; mock^.Batch := 1;
        Assert(configure(run,device,1,64,1,0,true,false),'configure immediate mock');
        execute(run);
        Assert((run^.Peak=1) and (run^.Bytes=1048576),'inline completions preserve peak and byte accounting');
        memset(uint32(run),0,sizeof(TBench)); run^.Buffer := buffer;
        Assert(configure(run,device,1,64,4,0,true,false),'configure removed device mock');
        device^.removed := true; execute(run);
        Assert((run^.Error=eDeviceRemoved) and (run^.Accepted=0) and (run^.Active=0),'submission rejection has no completion ownership');
    end else Assert(false,'mock allocation');
    if mock<>nil then kfree(void(mock)); if buffer<>nil then kfree(buffer);
    if device^.requestQueue<>nil then CFIFO_Free(device^.requestQueue);
    kfree(void(device)); kfree(void(run));
    io.syslog.log('STORBENCH','Passed: '); io.syslog.writeint(passed);
    io.syslog.writestring(' Failed: '); io.syslog.writeintln(failed);
end;
procedure init;
begin registerCommand('STORBENCH',@command,'Read-only disk benchmark. STORBENCH help for sizes, queue depths and comparison mode.'); end;
initialization
    boot.mgr.registerBoot('driver.storage.bench',@init,'Storage Benchmark',BOOT_MGR_BARRIER_LATE);
end.
