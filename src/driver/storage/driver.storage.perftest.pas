unit driver.storage.perftest;
interface
procedure UnitTest;
procedure init;
implementation
uses boot.mgr, io.stdio, io.syslog, memory.heap, core.util, core.ds.cfifo,
     driver.storage.types, driver.storage.mgr, driver.storage.fs.fat32.types,
     driver.storage.fs.fat32.core, driver.storage.fs.fat32.transfer;
type
    PMock = ^TMock;
    TMock = record
        Data : puint8;
        Pending : array[0..7] of PIORequest;
        Count, Calls, FailLBA, Callbacks, Bytes : uint32;
        Deferred : boolean;
        Error : TError;
    end;
procedure finish(request : PIORequest);
var m : PMock; bytes : uint32;
begin
    m := PMock(request^.Device^.controllerId0);
    if request^.LBA = m^.FailLBA then begin complete_io(request,false,eIOError); exit; end;
    if (request^.LBA >= 128) or (request^.SectorCount > 128-request^.LBA) then begin
        complete_io(request,false,eInvalidArgument); exit;
    end;
    if (uint32(request^.Buffer) and 1) <> 0 then begin complete_io(request,false,eInvalidArgument); exit; end;
    bytes := request^.SectorCount*512;
    if request^.RequestType = ioRead then memcpy(uint32(m^.Data)+request^.LBA*512,uint32(request^.Buffer),bytes)
    else memcpy(uint32(request^.Buffer),uint32(m^.Data)+request^.LBA*512,bytes);
    complete_io(request,true,eNone);
end;
procedure dispatch(device : PStorage_Device; request : PIORequest);
var m : PMock;
begin
    m := PMock(device^.controllerId0); Inc(m^.Calls);
    if m^.Deferred then begin
        if m^.Count = 8 then begin complete_io(request,false,eQueueFull); exit; end;
        m^.Pending[m^.Count] := request; Inc(m^.Count);
    end else finish(request);
end;
procedure done(error : TError; data : pointer);
var m : PMock;
begin m := PMock(data); Inc(m^.Callbacks); m^.Error := error; end;
procedure drain(m : PMock);
var request : PIORequest; n : uint32;
begin
    n := 0;
    while (m^.Count > 0) and (n < 64) do begin
        Inc(n); Dec(m^.Count); request := m^.Pending[m^.Count]; finish(request);
    end;
end;
procedure UnitTest;
var device : PStorage_Device; volume : PStorage_Volume; ofi : PFATOpenFile;
    m : PMock; vc : PFATVolumeCtx; br : PBootRecord; buffer : puint8;
    i, j, idx, base, cluster, off, available, passed, failed, before : uint32;
    ok : boolean;
    queued : PIORequest;
    procedure Assert(value : boolean; name : pchar);
    begin
        if value then Inc(passed) else begin Inc(failed); io.syslog.logln('STORPERF FAIL',name); end;
    end;
begin
    passed := 0; failed := 0;
    device := PStorage_Device(kalloc(sizeof(TStorage_Device)));
    volume := PStorage_Volume(kalloc(sizeof(TStorage_Volume)));
    ofi := PFATOpenFile(kalloc(sizeof(TFATOpenFile)));
    m := PMock(kalloc(sizeof(TMock))); buffer := puint8(kalloc(4096));
    if (device=nil) or (volume=nil) or (ofi=nil) or (m=nil) or (buffer=nil) then begin
        if device<>nil then kfree(void(device)); if volume<>nil then kfree(void(volume));
        if ofi<>nil then kfree(void(ofi)); if m<>nil then kfree(void(m)); if buffer<>nil then kfree(void(buffer));
        io.syslog.logln('STORPERF FAIL','allocation'); exit;
    end;
    memset(uint32(device),0,sizeof(TStorage_Device)); memset(uint32(volume),0,sizeof(TStorage_Volume));
    memset(uint32(ofi),0,sizeof(TFATOpenFile)); memset(uint32(m),0,sizeof(TMock));
    m^.Data := puint8(kalloc(128*512)); ofi^.RunMap.Runs := PFATRun(kalloc(4*sizeof(TFATRun)));
    if (m^.Data=nil) or (ofi^.RunMap.Runs=nil) then begin
        if m^.Data<>nil then kfree(void(m^.Data)); if ofi^.RunMap.Runs<>nil then kfree(void(ofi^.RunMap.Runs));
        kfree(void(device)); kfree(void(volume)); kfree(void(ofi)); kfree(void(m)); kfree(void(buffer));
        io.syslog.logln('STORPERF FAIL','data allocation'); exit;
    end;
    for i := 0 to 127 do memset(uint32(m^.Data)+i*512,i,512);
    br := PBootRecord(m^.Data); memset(uint32(br),0,sizeof(TBootRecord));
    br^.sectorSize := 512; br^.spc := 1; br^.rsvSectors := 1; br^.numFats := 1;
    br^.FATSize := 1; br^.manySectors := 128; br^.rootCluster := 2;
    device^.controllerId0 := uint32(m); device^.sectorSize := 512; device^.maxSectorCount := 128;
    device^.writable := true; device^.maxActive := 4;
    device^.dispatchRead := @dispatch; device^.dispatchWrite := @dispatch;
    device^.requestQueue := CFIFO_New(sizeof(pointer),16); m^.FailLBA := $FFFFFFFF;
    volume^.device := device; volume^.sectorCount := 128; volume^.sectorSize := 512;
    vc := FAT32GetVolumeCtx(volume);
    Assert(vc<>nil,'synthetic volume context');
    if vc<>nil then begin
        ofi^.Volume := volume; ofi^.VolumeInfo := @vc^.Info; ofi^.ByteSize := 4096;
        ofi^.AllocClusters := 8; ofi^.RunMap.Count := 4; ofi^.RunMap.Capacity := 4;
        ofi^.RunMap.TotalClusters := 8; ofi^.Exists := true; ofi^.Registered := true; ofi^.DirLoc.Valid := true;
        ofi^.ScratchSector := puint32(kalloc(512)); ofi^.ScratchSize := 512;
        for i := 0 to 3 do begin
            ofi^.RunMap.Runs[i].StartCluster := 10+i*10;
            ofi^.RunMap.Runs[i].ClusterCount := 2;
            ofi^.RunMap.Runs[i].FileClusterStart := i*2;
        end;
        Assert(FAT32FindRunForOffset(ofi,3584,false,0,0,idx,base,cluster,off,available) and
            (idx=3) and (cluster=41) and (available=512),'random run seek');
        Assert(FAT32FindRunForOffset(ofi,512,false,0,0,idx,base,cluster,off,available) and
            (idx=0) and (cluster=11),'backward persistent cursor seek');
        Assert(not FAT32FindRunForOffset(ofi,4096,false,0,0,idx,base,cluster,off,available),'run EOF');
        m^.Deferred := true; m^.Callbacks := 0;
        FAT32ReadFileAtOffsetAsync(volume,nil,nil,0,puint32(buffer),4096,ofi,@m^.Bytes,@done,m);
        Assert((m^.Count=4) and (m^.Callbacks=0),'four reads outstanding');
        Dec(m^.Count); finish(m^.Pending[m^.Count]);
        Assert(m^.Callbacks=0,'reverse completion retains context'); drain(m);
        Assert((m^.Callbacks=1) and (m^.Bytes=4096) and (m^.Error=eNone),'batch completes once');
        ok := true;
        for i := 0 to 4095 do if buffer[i] <> 10+(i div 1024)*10+(i mod 1024) div 512 then ok := false;
        Assert(ok,'fragmented DMA contents and cluster offsets');
        m^.Callbacks := 0; m^.FailLBA := 20;
        FAT32ReadFileAtOffsetAsync(volume,nil,nil,0,puint32(buffer),4096,ofi,@m^.Bytes,@done,m); drain(m);
        Assert((m^.Callbacks=1) and (m^.Bytes=1024) and (m^.Error=eIOError) and (device^.activeCount=0),'failure drains DMA and reports prefix');
        m^.FailLBA := $FFFFFFFF; m^.Callbacks := 0;
        FAT32ReadFileAtOffsetAsync(volume,nil,nil,513,puint32(buffer),3073,ofi,@m^.Bytes,@done,m); drain(m);
        ok := (m^.Callbacks=1) and (m^.Bytes=3073) and (m^.Error=eNone);
        for i := 0 to 3072 do begin j := i+513;
            if buffer[i] <> 10+(j div 1024)*10+(j mod 1024) div 512 then ok := false;
        end;
        Assert(ok,'unaligned head and tail around pipeline');
        m^.Deferred := false; m^.Callbacks := 0;
        FAT32ReadFileAtOffsetAsync(volume,nil,nil,0,puint32(buffer),4096,ofi,@m^.Bytes,@done,m);
        Assert((m^.Callbacks=1) and (m^.Bytes=4096) and (m^.Error=eNone),'inline batch completion is iterative');
        m^.FailLBA := 10; m^.Callbacks := 0;
        FAT32ReadFileAtOffsetAsync(volume,nil,nil,0,puint32(buffer),4096,ofi,@m^.Bytes,@done,m);
        Assert((m^.Callbacks=1) and (m^.Bytes=0) and (m^.Error=eIOError),'inline first-read failure completes once');
        m^.FailLBA := $FFFFFFFF;
        device^.maxActive := 0; m^.Callbacks := 0;
        for i := 0 to 15 do Assert(storage_read_async(device,50,1,puint32(buffer),nil,nil)=eNone,'fill fixed queue');
        FAT32ReadFileAtOffsetAsync(volume,nil,nil,0,puint32(buffer),4096,ofi,@m^.Bytes,@done,m);
        Assert((m^.Callbacks=1) and (m^.Bytes=0) and (m^.Error=eQueueFull),'rejected pipeline submission releases context');
        device^.maxActive := 4;
        { Simulate dispatch of the first queued request, then let completion drain. }
        if CFIFO_Dequeue(device^.requestQueue,@queued) then begin
            Inc(device^.activeCount); finish(queued);
        end;
        Assert(CFIFO_Size(device^.requestQueue)=0,'full queue drained');
        Assert(FAT32ReadFileAtOffset(volume,nil,nil,512,puint32(buffer),512,ofi)=512,'blocking read uses pipeline');
        Assert(buffer[0]=11,'offset inside contiguous run is not counted twice');
        m^.FailLBA := 10;
        Assert(FAT32WriteFileAtOffset(volume,nil,nil,0,puint32(buffer),512,ofi)=0,'failed write reports zero bytes');
        m^.FailLBA := $FFFFFFFF;
        if ofi^.ScratchSector<>nil then kfree(void(ofi^.ScratchSector));
        FAT32ReleaseVolumeCtx(volume);
    end;
    { Force a backlog without issuing hardware I/O, then drain through a mock. }
    device^.maxActive := 0; device^.mergeMaxSectors := 8; m^.Deferred := false;
    m^.Callbacks := 0; before := m^.Calls;
    for i := 0 to 3 do Assert(storage_read_async(device,10+i,1,puint32(uint32(buffer)+i*512),@done,m)=eNone,'merge enqueue');
    device^.maxActive := 1;
    Assert(storage_read_async(device,50,1,puint32(buffer),@done,m)=eNone,'drain trigger');
    Assert((m^.Calls-before=2) and (m^.Callbacks=5),'four requests merge with five callbacks including trigger');
    Assert(device^.Stats.Merged=3,'merge counter');
    device^.maxActive := 0; m^.Callbacks := 0; m^.FailLBA := 10;
    for i := 0 to 1 do Assert(storage_write_async(device,10+i,1,puint32(uint32(buffer)+i*512),@done,m)=eNone,'merged write enqueue');
    device^.maxActive := 1; before := device^.Stats.Failed;
    Assert(storage_read_async(device,50,1,puint32(buffer),@done,m)=eNone,'failed merge drain trigger');
    Assert((device^.Stats.Failed-before=2) and (m^.Callbacks=3),'merged failure fans out once');
    m^.FailLBA := $FFFFFFFF; device^.maxActive := 0; device^.mergeMaxSectors := 2;
    m^.Callbacks := 0; before := m^.Calls;
    for i := 0 to 3 do Assert(storage_read_async(device,10+i,1,puint32(uint32(buffer)+i*512),@done,m)=eNone,'limited merge enqueue');
    device^.maxActive := 1;
    Assert(storage_read_async(device,50,1,puint32(buffer),@done,m)=eNone,'limited merge drain trigger');
    Assert((m^.Calls-before=3) and (m^.Callbacks=5),'driver command limit splits merges');
    device^.maxActive := 0; device^.mergeMaxSectors := 8; before := m^.Calls;
    Assert(storage_read_async(device,10,1,puint32(buffer),nil,nil)=eNone,'ordering read');
    Assert(storage_write_async(device,11,1,puint32(uint32(buffer)+512),nil,nil)=eNone,'ordering write');
    Assert(storage_write_async(device,12,1,puint32(buffer),nil,nil)=eNone,'noncontiguous buffer');
    device^.maxActive := 1;
    Assert(storage_read_async(device,50,1,puint32(buffer),nil,nil)=eNone,'ordering drain trigger');
    Assert(m^.Calls-before=4,'operation and buffer boundaries prevent merging');
    Assert(device^.Stats.Completed=device^.Stats.Submitted,'all accepted requests accounted');
    CFIFO_Free(device^.requestQueue); kfree(void(ofi^.RunMap.Runs)); kfree(void(m^.Data));
    kfree(void(device)); kfree(void(volume)); kfree(void(ofi)); kfree(void(m)); kfree(void(buffer));
    io.syslog.log('STORPERF','Passed: '); io.syslog.writeint(passed);
    io.syslog.writestring(' Failed: '); io.syslog.writeintln(failed);
end;
procedure command(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin UnitTest; io.stdio.bufWriteStrLn(stdout_buf,'Storage performance regression results written to serial log.'); end;
procedure init;
begin io.stdio.registerCommand('STORPERF',@command,'Run memory-backed storage performance regression tests'); end;
initialization
    boot.mgr.registerBoot('driver.storage.perftest',@init,'Storage Performance Tests',BOOT_MGR_BARRIER_MID);
end.
