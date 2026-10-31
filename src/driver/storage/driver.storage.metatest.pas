unit driver.storage.metatest;

interface
procedure UnitTest;
procedure init;

implementation
uses boot.mgr, io.stdio, io.syslog, memory.heap, core.util, core.ds.cfifo,
     driver.storage.types, driver.storage.mgr, driver.storage.vol.mbr,
     driver.storage.vol.mgr, driver.storage.fs.fat32.types,
     driver.storage.fs.fat32.vol, driver.storage.fs.fat32.labels, core.strings;

type
    PMock = ^TMock;
    TMock = record
        Data : puint8;
        Writes, FailWrite, Callbacks : uint32;
        Error : TError;
        OutOfBounds, FailRead : boolean;
    end;

procedure dispatch(device : PStorage_Device; request : PIORequest);
var m : PMock; offset, size : uint32;
begin
    m := PMock(device^.controllerId0);
    if (request^.LBA >= device^.maxSectorCount) or
       (request^.SectorCount > device^.maxSectorCount-request^.LBA) then begin
        m^.OutOfBounds := true; complete_io(request, false, eInvalidArgument); exit;
    end;
    if (request^.RequestType <> ioWrite) and m^.FailRead then begin complete_io(request, false, eIOError); exit; end;
    offset := request^.LBA*512; size := request^.SectorCount*512;
    if request^.RequestType = ioWrite then begin
        Inc(m^.Writes);
        if m^.Writes = m^.FailWrite then begin complete_io(request, false, eIOError); exit; end;
        memcpy(uint32(request^.Buffer), uint32(m^.Data)+offset, size);
    end else memcpy(uint32(m^.Data)+offset, uint32(request^.Buffer), size);
    request^.ByteCount := size;
    complete_io(request, true, eNone);
end;

procedure completion(error : TError; data : pointer);
var m : PMock;
begin m := PMock(data); Inc(m^.Callbacks); m^.Error := error; end;

{ Only heap-backed synthetic storage is used. Never registers a hardware device,
  never accesses a host/guest disk, and every fake request completes inline. }
procedure UnitTest;
var
    device : PStorage_Device;
    volume, added : PStorage_Volume;
    mock : PMock;
    br : PBootRecord;
    mbr, before : PMaster_Boot_Record;
    params : TFSFormatParams;
    labelValue : TVolumeLabel;
    part : TPartition_table;
    passed, failed, oldCount, writes, i : uint32;
    err : TError;
    procedure Assert(ok : boolean; name : pchar);
    begin
        if ok then Inc(passed) else begin Inc(failed); io.syslog.logln('STORMETA FAIL', name); end;
    end;
begin
    passed := 0; failed := 0;
    device := PStorage_Device(kalloc(sizeof(TStorage_Device)));
    volume := PStorage_Volume(kalloc(sizeof(TStorage_Volume)));
    mock := PMock(kalloc(sizeof(TMock)));
    br := PBootRecord(kalloc(sizeof(TBootRecord)));
    if (device = nil) or (volume = nil) or (mock = nil) or (br = nil) then begin
        if device <> nil then kfree(void(device));
        if volume <> nil then kfree(void(volume));
        if mock <> nil then kfree(void(mock));
        if br <> nil then kfree(void(br));
        io.syslog.logln('STORMETA FAIL', 'test allocation'); exit;
    end;
    memset(uint32(device),0,sizeof(TStorage_Device));
    memset(uint32(volume),0,sizeof(TStorage_Volume));
    memset(uint32(mock),0,sizeof(TMock)); memset(uint32(br),0,sizeof(TBootRecord));
    mock^.Data := puint8(kalloc(256*512));
    memset(uint32(mock^.Data),$CC,256*512);
    device^.controllerId0 := uint32(mock); device^.sectorSize := 512;
    device^.maxSectorCount := 256; device^.writable := true; device^.maxActive := 1;
    device^.dispatchRead := @dispatch; device^.dispatchWrite := @dispatch;
    device^.requestQueue := CFIFO_New(sizeof(Pointer),4);
    device^.cachedMBR := kalloc(512);
    mbr := PMaster_Boot_Record(device^.cachedMBR);
    memset(uint32(mbr),0,512); mbr^.boot_sector := $AA55; mbr^.signature := $12345678;
    Assert(write_mbr(device,mbr) = eNone,'aliased MBR write succeeds');
    Assert(PMaster_Boot_Record(mock^.Data)^.signature = $12345678,'aliased MBR bytes preserved');
    before := PMaster_Boot_Record(device^.cachedMBR);
    mock^.FailWrite := mock^.Writes+1;
    Assert(write_mbr(device,before) = eIOError,'write failure propagated');
    Assert(device^.cachedMBR = before,'failed write retains cache');
    mock^.FailWrite := 0; mock^.Callbacks := 0;
    write_mbr_async(device,PMaster_Boot_Record(device^.cachedMBR),@completion,mock);
    Assert((mock^.Callbacks = 1) and (mock^.Error = eNone),'async MBR callback once');
    Assert(PMaster_Boot_Record(mock^.Data)^.signature = $12345678,'async alias preserved');
    before := PMaster_Boot_Record(device^.cachedMBR); mock^.Callbacks := 0;
    mock^.FailWrite := mock^.Writes+1;
    write_mbr_async(device,before,@completion,mock);
    Assert((mock^.Callbacks = 1) and (mock^.Error = eIOError),'async failure callback once');
    Assert(device^.cachedMBR = before,'async failure retains cache');
    mock^.FailWrite := 0;
    volume^.device := device; volume^.sectorStart := 64; volume^.sectorCount := 128; volume^.sectorSize := 512;
    memset(uint32(@params),0,sizeof(params)); params.Version := 1;
    params.Flags := FS_FORMAT_PARAM_CLUSTER_SIZE; params.ClusterSize := 1;
    Assert(validate_format(volume,128,64,@params) = eNone,'valid format geometry');
    params.ClusterSize := 3;
    Assert(validate_format(volume,128,64,@params) = eInvalidArgument,'reject non-power-of-two clusters');
    params.ClusterSize := 1; volume^.sectorCount := 33; writes := mock^.Writes;
    Assert(create_volume(volume,33,64,@params) = eInvalidArgument,'reject tiny partition');
    Assert(mock^.Writes = writes,'rejected format does not write');
    volume^.sectorCount := 128;
    for i := 1 to 6 do begin
        mock^.FailWrite := mock^.Writes+i;
        Assert(create_volume(volume,128,64,@params) = eIOError,'each failed format write propagated');
    end;
    mock^.FailWrite := 0;
    Assert(create_volume(volume,128,64,@params) = eNone,'format completes');
    Assert(not mock^.OutOfBounds,'all writes within device');
    Assert((mock^.Data[63*512] = $CC) and (mock^.Data[192*512] = $CC),'neighbor partitions untouched');
    memcpy(uint32(mock^.Data)+64*512,uint32(br),sizeof(TBootRecord));
    Assert(FAT32ClusterLimit(br) = 97,'cluster bound excludes FAT padding');
    Assert(identify_volume(volume),'fresh format identified');
    Assert(volume^.freeSectors = 93,'free space excludes metadata and allocated directories');
    mock^.FailRead := true;
    Assert(not identify_volume(volume),'failed probe read cannot report success');
    mock^.FailRead := false;
    Assert(normalize_label(' projects ',labelValue) = eNone,'label accepts spaces');
    Assert(stringEquals(@labelValue[0],'PROJECTS'),'label trims and uppercases');
    Assert(normalize_label('ABCDEFGHIJKL',labelValue) = eInvalidArgument,'reject long label');
    Assert(normalize_label('BAD/NAME',labelValue) = eInvalidArgument,'reject invalid label character');
    writes := mock^.Writes;
    Assert(write_label(volume,'BAD/NAME') = eInvalidArgument,'invalid rename rejected');
    Assert(mock^.Writes = writes,'invalid label does not write');
    Assert(write_label(volume,'Projects') = eNone,'write volume label');
    volume^.labelText[0] := #0;
    Assert(read_label(volume) = eNone,'reload label from disk');
    Assert(stringEquals(@volume^.labelText[0],'PROJECTS'),'label survives cache reset');
    Assert(PDirectory(uint32(mock^.Data)+97*512)^.fileName[0] = 'S','rename preserves SYSTEM directory');
    { Add a valid backup boot sector and verify all three metadata writes. }
    PBootRecord(uint32(mock^.Data)+64*512)^.backupCluster := 6;
    memcpy(uint32(mock^.Data)+64*512,uint32(mock^.Data)+70*512,512);
    for i := 1 to 3 do begin
        mock^.FailWrite := mock^.Writes+i;
        Assert(write_label(volume,'NEW NAME') = eIOError,'label write failure propagated');
        mock^.FailWrite := 0;
        Assert(read_label(volume) = eNone,'label readable after failed rename');
        Assert(stringEquals(@volume^.labelText[0],'PROJECTS'),'failed rename retains previous label');
    end;
    Assert(write_label(volume,'ABCDEFGHIJK') = eNone,'maximum length label');
    Assert(PBootRecord(uint32(mock^.Data)+70*512)^.volumeLabel[10] = ord('K'),'backup label updated');
    Assert(write_label(volume,'') = eNone,'clear label');
    volume^.labelText[0] := 'X';
    Assert(read_label(volume) = eNone,'reload cleared label');
    Assert(volume^.labelText[0] = #0,'blank label persists');
    params.Flags := params.Flags or FS_FORMAT_PARAM_LABEL;
    memcpy(uint32(pchar('MY DATA')),uint32(@params.LabelText[0]),8);
    Assert(create_volume(volume,128,64,@params) = eNone,'format with label');
    Assert(read_label(volume) = eNone,'read format label');
    Assert(stringEquals(@volume^.labelText[0],'MY DATA'),'format label persists');
    Assert(PDirectory(uint32(mock^.Data)+97*512)^.attributes = $08,'format creates root volume label entry');
    Assert(not mock^.OutOfBounds,'label operations stay inside volume');
    oldCount := get_volume_count();
    memset(uint32(@part),0,sizeof(part)); part.LBA_start := 64; part.sector_count := 128;
    mock^.FailWrite := mock^.Writes+1;
    Assert(add_partition(device,0,part) = eIOError,'failed partition creation reported');
    Assert(get_volume_count() = oldCount,'failed create publishes no volume');
    Assert(PMaster_Boot_Record(device^.cachedMBR)^.partition[0].sector_count = 0,'failed create leaves MBR cache');
    mock^.FailWrite := 0;
    Assert(add_partition(device,0,part) = eNone,'partition creation committed');
    added := get_volume(get_volume_count()-1);
    added^.lifecycleFlags := STORAGE_VOLUME_FLAG_FORMATTING;
    writes := mock^.Writes;
    Assert(remove_partition(device,0) = eFileInUse,'delete rejects formatting volume');
    Assert(mock^.Writes = writes,'busy delete leaves disk untouched');
    mock^.Callbacks := 0;
    Assert(not format_volume_async(device,get_volume_count()-1,'FAT32',@params,@completion,mock),'busy format rejected');
    Assert(mock^.Callbacks = 0,'false submission never calls callback');
    added^.lifecycleFlags := 0;
    mock^.FailWrite := mock^.Writes+1;
    Assert(remove_partition(device,0) = eIOError,'delete propagates failed MBR write');
    Assert(get_volume_count() = oldCount+1,'failed delete retains volume');
    mock^.FailWrite := 0;
    Assert(remove_partition(device,0) = eNone,'delete commits');
    Assert(get_volume_count() = oldCount,'delete detaches volume after write');
    kfree(device^.cachedMBR); CFIFO_Free(device^.requestQueue);
    kfree(void(mock^.Data)); kfree(void(mock)); kfree(void(volume)); kfree(void(device)); kfree(void(br));
    io.syslog.log('STORMETA','Passed: '); io.syslog.writeint(passed);
    io.syslog.writestring(' Failed: '); io.syslog.writeintln(failed);
end;

procedure command(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin
    UnitTest;
    io.stdio.bufWriteStrLn(stdout_buf,'Storage metadata regression results written to serial log.');
end;

procedure init;
begin io.stdio.registerCommand('STORMETA',@command,'Run memory-backed storage metadata regression tests'); end;

initialization
    boot.mgr.registerBoot('driver.storage.metatest',@init,'Storage Metadata Tests',BOOT_MGR_BARRIER_MID);
end.
