unit driver.storage.metatest;

interface
procedure RunTests(scheduled: boolean);
procedure UnitTest;
procedure init;

implementation
uses driver.storage.vfs, driver.storage.fs.mgr, driver.storage.fs.fat32, driver.storage.fs.fat32.core, arch.platform.diagnostics, io.stdio, io.syslog, memory.heap, core.util, core.ds.cfifo,
     driver.storage.types, driver.storage.mgr, driver.storage.vol.mbr,
     driver.storage.vol.mgr, driver.storage.fs.fat32.types,
     driver.storage.fs.fat32.vol, driver.storage.fs.fat32.labels, core.strings, test.harness;

type
    PMock = ^TMock;
    TMock = record
        Data : puint8;
        Writes, FailWrite, Callbacks, Depth, MaxDepth : uint32;
        MaxReadSectors, FailReadLBA : uint32;
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
    if request^.RequestType <> ioWrite then
        if request^.SectorCount > m^.MaxReadSectors then m^.MaxReadSectors := request^.SectorCount;
    if (request^.RequestType <> ioWrite) and (m^.FailRead or
       ((m^.FailReadLBA <> 0) and (request^.LBA = m^.FailReadLBA))) then begin
        Inc(m^.Depth); if m^.Depth > m^.MaxDepth then m^.MaxDepth := m^.Depth;
        complete_io(request,false,eIOError); Dec(m^.Depth); exit;
    end;
    offset := request^.LBA*512; size := request^.SectorCount*512;
    if request^.RequestType = ioWrite then begin
        Inc(m^.Writes);
        if m^.Writes = m^.FailWrite then begin complete_io(request, false, eIOError); exit; end;
        memcpy(PtrUInt(request^.Buffer), PtrUInt(m^.Data)+offset, size);
    end else memcpy(PtrUInt(m^.Data)+offset, PtrUInt(request^.Buffer), size);
    request^.ByteCount := size;
    complete_io(request, true, eNone);
end;

procedure completion(error : TError; data : pointer);
var m : PMock;
begin m := PMock(data); Inc(m^.Callbacks); m^.Error := error; end;

{ Only heap-backed synthetic storage is used. Never registers a hardware device,
  never accesses a host/guest disk, and every fake request completes inline. }
procedure RunTests(scheduled: boolean);
var
    device : PStorage_Device;
    volume, added : PStorage_Volume;
    mock : PMock;
    br : PBootRecord;
    mbr, before : PMaster_Boot_Record;
    params : TFSFormatParams;
    labelValue : TVolumeLabel;
    part : TPartition_table;
    oldCount, writes, i : uint32;
    err : TError;
    context : TTestContext;

    procedure FileRoundTrip(name: pchar);
    var
        fs, sourceFS: PFilesystem;
        handle: TFileHandle;
        error: TError;
        data: puint8;
        j: uint32;
        matches: boolean;
    begin
        sourceFS := find_filesystem_by_name(name);
        test.harness.Assert(@context, sourceFS <> nil, 'round-trip filesystem registered');
        if sourceFS = nil then exit;
        fs := PFilesystem(kalloc(sizeof(TFilesystem)));
        test.harness.Assert(@context, fs <> nil, 'round-trip filesystem descriptor');
        if fs = nil then exit;
        memcpy(PtrUInt(sourceFS), PtrUInt(fs), sizeof(TFilesystem));
        { Early boot has no scheduler yet. Exercise the synchronous hooks on
          a private descriptor; scheduled runs retain the normal async hooks. }
        if not scheduled then begin
            fs^.readOffsetAsyncCallback := nil;
            fs^.writeOffsetAsyncCallback := nil;
        end;
        FAT32ReleaseVolumeCtx(volume);
        memset(PtrUInt(volume), 0, sizeof(TStorage_Volume));
        volume^.device := device;
        volume^.sectorSize := 512;
        volume^.sectorCount := 4096;
        memset(PtrUInt(mock^.Data), 0, 4096 * 512);
        volume^.filesystem := fs;
        params.Flags := FS_FORMAT_PARAM_CLUSTER_SIZE;
        params.ClusterSize := 2;
        error := fs^.createCallback(volume, 4096, 0, @params);
        test.harness.Assert(@context, error = eNone, 'round-trip format');
        if error <> eNone then begin
            kfree(void(fs));
            exit;
        end;
        test.harness.Assert(@context, fs^.identifyCallback(volume), 'round-trip identify');
        if mountVolume('/__storage_roundtrip__', volume) <> pvRegistered then begin
            test.harness.Assert(@context, false, 'round-trip mount');
            InvalidateVolume(volume);
            kfree(void(fs));
            exit;
        end;
        data := puint8(kalloc(8192));
        test.harness.Assert(@context, data <> nil, 'round-trip buffer');
        if data <> nil then begin
            for j := 0 to 8191 do data[j] := (j * 17 + 3) and $FF;
            handle := OpenFile('/__storage_roundtrip__/ROUND.BIN', omCreate, @error);
            test.harness.Assert(@context, error = eNone, 'round-trip create');
            if error = eNone then begin
                test.harness.Assert(@context, WriteFile(handle, 0, data, 8192) = 8192, 'write across filesystem blocks');
                test.harness.Assert(@context, CloseFile(handle) = eNone, 'close written file');
                handle := OpenFile('/__storage_roundtrip__/ROUND.BIN', omRead, @error);
                test.harness.Assert(@context, error = eNone, 'reopen written file');
                if error = eNone then begin
                    memset(PtrUInt(data), 0, 8192);
                    test.harness.Assert(@context, ReadFile(handle, 37, data, 4096) = 4096, 'unaligned cross-block read');
                    matches := true;
                    for j := 0 to 4095 do
                        if data[j] <> (((j + 37) * 17 + 3) and $FF) then matches := false;
                    test.harness.Assert(@context, matches, 'read-back bytes match written pattern');
                    test.harness.Assert(@context, FileSizeFromHandle(handle) = 8192, 'reopened file size persists');
                    test.harness.Assert(@context, CloseFile(handle) = eNone, 'close read file');
                end;
            end;
            kfree(void(data));
        end;
        if stringEquals(name, 'EXT2') then begin
            test.harness.Assert(@context, InvalidateVolume(volume),
                                'quiesce EXT2 volume before rename');
            test.harness.Assert(@context, volume^.fsPrivate = nil,
                                'unmount releases EXT2 filesystem state');
            writes := mock^.Writes;
            mock^.FailRead := true;
            error := fs^.setLabelCallback(volume, 'NOT WRITTEN');
            mock^.FailRead := false;
            test.harness.Assert(@context, error = eDeviceNotReady,
                                'EXT2 label reload reports an unavailable filesystem');
            test.harness.Assert(@context, (volume^.fsPrivate = nil) and (mock^.Writes = writes),
                                'failed EXT2 reload leaves state detached and issues no writes');
            test.harness.Assert(@context, fs^.setLabelCallback(volume, 'NEW EXT2') = eNone,
                                'rename quiesced EXT2 volume');
        end;
        test.harness.Assert(@context, InvalidateVolume(volume), 'round-trip volume released');
        if stringEquals(name, 'EXT2') then begin
            test.harness.Assert(@context, fs^.identifyCallback(volume), 'reload renamed EXT2');
            test.harness.Assert(@context, stringEquals(@volume^.labelText[0], 'NEW EXT2'),
                                'EXT2 label persists after filesystem state is released');
            fs^.releaseVolumeCallback(volume);
        end;
        RemoveVirtualTree('/__storage_roundtrip__');
        volume^.filesystem := nil;
        kfree(void(fs));
        io.syslog.logln('STORMETA round-trip', name);
    end;
begin
    test.harness.Start(@context, 'driver.storage.metatest');
    device := PStorage_Device(kalloc(sizeof(TStorage_Device)));
    volume := PStorage_Volume(kalloc(sizeof(TStorage_Volume)));
    mock := PMock(kalloc(sizeof(TMock)));
    br := PBootRecord(kalloc(sizeof(TBootRecord)));
    if (device = nil) or (volume = nil) or (mock = nil) or (br = nil) then begin
        if device <> nil then kfree(void(device));
        if volume <> nil then kfree(void(volume));
        if mock <> nil then kfree(void(mock));
        if br <> nil then kfree(void(br));
        test.harness.Assert(@context, false, 'test allocation');
        test.harness.Finish(@context);
        exit;
    end;
    memset(PtrUInt(device),0,sizeof(TStorage_Device));
    memset(PtrUInt(volume),0,sizeof(TStorage_Volume));
    memset(PtrUInt(mock),0,sizeof(TMock)); memset(PtrUInt(br),0,sizeof(TBootRecord));
    mock^.Data := puint8(kalloc(256*512));
    memset(PtrUInt(mock^.Data),$CC,256*512);
    device^.controllerId0 := PtrUInt(mock); device^.sectorSize := 512;
    device^.maxSectorCount := 256; device^.writable := true; device^.maxActive := 1;
    device^.dispatchRead := @dispatch; device^.dispatchWrite := @dispatch;
    device^.requestQueue := CFIFO_New(sizeof(Pointer),8);
    device^.maxActive := 0; mock^.FailRead := true;
    for i := 1 to 4 do
        test.harness.Assert(@context, storage_read_async(device,0,1,puint32(mock^.Data),@completion,mock)=eNone,'queued fault request accepted');
    test.harness.Assert(@context, mock^.Callbacks=0,'queued requests wait for dispatch');
    device^.maxActive := 1;
    test.harness.Assert(@context, storage_read_async(device,0,1,puint32(mock^.Data),@completion,mock)=eNone,'fault queue drain accepted');
    test.harness.Assert(@context, (mock^.Callbacks=5) and (mock^.Error=eIOError),'every queued error completes once');
    test.harness.Assert(@context, (mock^.MaxDepth=1) and (device^.activeCount=0) and (CFIFO_Size(device^.requestQueue)=0),
           'inline failures drain without recursive driver dispatch');
    mock^.FailRead := false; mock^.Callbacks := 0;
    device^.cachedMBR := kalloc(512);
    mbr := PMaster_Boot_Record(device^.cachedMBR);
    memset(PtrUInt(mbr),0,512); mbr^.boot_sector := $AA55; mbr^.signature := $12345678;
    test.harness.Assert(@context, write_mbr(device,mbr) = eNone,'aliased MBR write succeeds');
    test.harness.Assert(@context, PMaster_Boot_Record(mock^.Data)^.signature = $12345678,'aliased MBR bytes preserved');
    before := PMaster_Boot_Record(device^.cachedMBR);
    mock^.FailWrite := mock^.Writes+1;
    test.harness.Assert(@context, write_mbr(device,before) = eIOError,'write failure propagated');
    test.harness.Assert(@context, device^.cachedMBR = before,'failed write retains cache');
    mock^.FailWrite := 0; mock^.Callbacks := 0;
    write_mbr_async(device,PMaster_Boot_Record(device^.cachedMBR),@completion,mock);
    test.harness.Assert(@context, (mock^.Callbacks = 1) and (mock^.Error = eNone),'async MBR callback once');
    test.harness.Assert(@context, PMaster_Boot_Record(mock^.Data)^.signature = $12345678,'async alias preserved');
    before := PMaster_Boot_Record(device^.cachedMBR); mock^.Callbacks := 0;
    mock^.FailWrite := mock^.Writes+1;
    write_mbr_async(device,before,@completion,mock);
    test.harness.Assert(@context, (mock^.Callbacks = 1) and (mock^.Error = eIOError),'async failure callback once');
    test.harness.Assert(@context, device^.cachedMBR = before,'async failure retains cache');
    mock^.FailWrite := 0;
    volume^.device := device; volume^.sectorStart := 64; volume^.sectorCount := 128; volume^.sectorSize := 512;
    memset(PtrUInt(@params),0,sizeof(params)); params.Version := 1;
    params.Flags := FS_FORMAT_PARAM_CLUSTER_SIZE; params.ClusterSize := 1;
    test.harness.Assert(@context, validate_format(volume,128,64,@params) = eNone,'valid format geometry');
    params.ClusterSize := 3;
    test.harness.Assert(@context, validate_format(volume,128,64,@params) = eInvalidArgument,'reject non-power-of-two clusters');
    params.ClusterSize := 1; volume^.sectorCount := 33; writes := mock^.Writes;
    test.harness.Assert(@context, create_volume(volume,33,64,@params) = eInvalidArgument,'reject tiny partition');
    test.harness.Assert(@context, mock^.Writes = writes,'rejected format does not write');
    volume^.sectorCount := 128;
    for i := 1 to 6 do begin
        mock^.FailWrite := mock^.Writes+i;
        test.harness.Assert(@context, create_volume(volume,128,64,@params) = eIOError,'each failed format write propagated');
    end;
    mock^.FailWrite := 0;
    test.harness.Assert(@context, create_volume(volume,128,64,@params) = eNone,'format completes');
    test.harness.Assert(@context, not mock^.OutOfBounds,'all writes within device');
    test.harness.Assert(@context, (mock^.Data[63*512] = $CC) and (mock^.Data[192*512] = $CC),'neighbor partitions untouched');
    memcpy(PtrUInt(mock^.Data)+64*512,PtrUInt(br),sizeof(TBootRecord));
    test.harness.Assert(@context, FAT32ClusterLimit(br) = 97,'cluster bound excludes FAT padding');
    test.harness.Assert(@context, identify_volume(volume),'fresh format identified');
    test.harness.Assert(@context, volume^.freeSectors = 93,'free space excludes metadata and allocated directories');
    mock^.FailRead := true;
    test.harness.Assert(@context, not identify_volume(volume),'failed probe read cannot report success');
    mock^.FailRead := false;
    test.harness.Assert(@context, normalize_label(' projects ',labelValue) = eNone,'label accepts spaces');
    test.harness.Assert(@context, stringEquals(@labelValue[0],'PROJECTS'),'label trims and uppercases');
    test.harness.Assert(@context, normalize_label('ABCDEFGHIJKL',labelValue) = eInvalidArgument,'reject long label');
    test.harness.Assert(@context, normalize_label('BAD/NAME',labelValue) = eInvalidArgument,'reject invalid label character');
    writes := mock^.Writes;
    test.harness.Assert(@context, write_label(volume,'BAD/NAME') = eInvalidArgument,'invalid rename rejected');
    test.harness.Assert(@context, mock^.Writes = writes,'invalid label does not write');
    test.harness.Assert(@context, write_label(volume,'Projects') = eNone,'write volume label');
    volume^.labelText[0] := #0;
    test.harness.Assert(@context, read_label(volume) = eNone,'reload label from disk');
    test.harness.Assert(@context, stringEquals(@volume^.labelText[0],'PROJECTS'),'label survives cache reset');
    test.harness.Assert(@context, PDirectory(PtrUInt(mock^.Data)+97*512)^.fileName[0] = 'S','rename preserves SYSTEM directory');
    { Add a valid backup boot sector and verify all three metadata writes. }
    PBootRecord(PtrUInt(mock^.Data)+64*512)^.backupCluster := 6;
    memcpy(PtrUInt(mock^.Data)+64*512,PtrUInt(mock^.Data)+70*512,512);
    for i := 1 to 3 do begin
        mock^.FailWrite := mock^.Writes+i;
        test.harness.Assert(@context, write_label(volume,'NEW NAME') = eIOError,'label write failure propagated');
        mock^.FailWrite := 0;
        test.harness.Assert(@context, read_label(volume) = eNone,'label readable after failed rename');
        test.harness.Assert(@context, stringEquals(@volume^.labelText[0],'PROJECTS'),'failed rename retains previous label');
    end;
    test.harness.Assert(@context, write_label(volume,'ABCDEFGHIJK') = eNone,'maximum length label');
    test.harness.Assert(@context, PBootRecord(PtrUInt(mock^.Data)+70*512)^.volumeLabel[10] = ord('K'),'backup label updated');
    test.harness.Assert(@context, write_label(volume,'') = eNone,'clear label');
    volume^.labelText[0] := 'X';
    test.harness.Assert(@context, read_label(volume) = eNone,'reload cleared label');
    test.harness.Assert(@context, volume^.labelText[0] = #0,'blank label persists');
    params.Flags := params.Flags or FS_FORMAT_PARAM_LABEL;
    memcpy(PtrUInt(pchar('MY DATA')),PtrUInt(@params.LabelText[0]),8);
    test.harness.Assert(@context, create_volume(volume,128,64,@params) = eNone,'format with label');
    test.harness.Assert(@context, read_label(volume) = eNone,'read format label');
    test.harness.Assert(@context, stringEquals(@volume^.labelText[0],'MY DATA'),'format label persists');
    test.harness.Assert(@context, PDirectory(PtrUInt(mock^.Data)+97*512)^.attributes = $08,'format creates root volume label entry');
    test.harness.Assert(@context, not mock^.OutOfBounds,'label operations stay inside volume');
    oldCount := get_volume_count();
    memset(PtrUInt(@part),0,sizeof(part)); part.LBA_start := 64; part.sector_count := 128;
    mock^.FailWrite := mock^.Writes+1;
    test.harness.Assert(@context, add_partition(device,0,part) = eIOError,'failed partition creation reported');
    test.harness.Assert(@context, get_volume_count() = oldCount,'failed create publishes no volume');
    test.harness.Assert(@context, PMaster_Boot_Record(device^.cachedMBR)^.partition[0].sector_count = 0,'failed create leaves MBR cache');
    mock^.FailWrite := 0;
    test.harness.Assert(@context, add_partition(device,0,part) = eNone,'partition creation committed');
    added := get_volume(get_volume_count()-1);
    added^.lifecycleFlags := STORAGE_VOLUME_FLAG_FORMATTING;
    writes := mock^.Writes;
    test.harness.Assert(@context, remove_partition(device,0) = eFileInUse,'delete rejects formatting volume');
    test.harness.Assert(@context, mock^.Writes = writes,'busy delete leaves disk untouched');
    mock^.Callbacks := 0;
    test.harness.Assert(@context, not format_volume_async(device,get_volume_count()-1,'FAT32',@params,@completion,mock),'busy format rejected');
    test.harness.Assert(@context, mock^.Callbacks = 0,'false submission never calls callback');
    added^.lifecycleFlags := 0;
    mock^.FailWrite := mock^.Writes+1;
    test.harness.Assert(@context, remove_partition(device,0) = eIOError,'delete propagates failed MBR write');
    test.harness.Assert(@context, get_volume_count() = oldCount+1,'failed delete retains volume');
    mock^.FailWrite := 0;
    test.harness.Assert(@context, remove_partition(device,0) = eNone,'delete commits');
    test.harness.Assert(@context, get_volume_count() = oldCount,'delete detaches volume after write');
    { More than eight FAT sectors, with a partial final batch and FAT padding. }
    kfree(void(mock^.Data));
    mock^.Data := puint8(kalloc(4096*512));
    if mock^.Data <> nil then begin
        memset(PtrUInt(mock^.Data),0,1500*512);
        device^.maxSectorCount := 1500;
        volume^.sectorStart := 0; volume^.sectorCount := 1500;
        test.harness.Assert(@context, create_volume(volume,1500,0,@params) = eNone,'format multi-batch FAT fixture');
        mock^.MaxReadSectors := 0;
        test.harness.Assert(@context, identify_volume(volume),'identify multi-batch FAT');
        test.harness.Assert(@context, volume^.freeSectors = 1454,'batched count excludes padding and allocated clusters');
        test.harness.Assert(@context, mock^.MaxReadSectors = 8,'FAT scan batches eight sectors');
        mock^.FailReadLBA := 40;
        test.harness.Assert(@context, not identify_volume(volume),'failure in final FAT batch rejects probe');
        mock^.FailReadLBA := 0;
        test.harness.Assert(@context, not mock^.OutOfBounds,'batched scan stays within device');
        device^.maxSectorCount := 4096; volume^.sectorCount := 4096;
        test.harness.Assert(@context, create_volume(volume,4096,0,@params) = eNone,'format large FAT fixture');
        mock^.FailReadLBA := 32; mock^.MaxReadSectors := 0;
        test.harness.Assert(@context, identify_volume(volume),'large FAT mounts without reading allocation table');
        test.harness.Assert(@context, (volume^.lifecycleFlags and STORAGE_VOLUME_FLAG_FREE_UNKNOWN) <> 0,'missing FSInfo reports unknown free space');
        test.harness.Assert(@context, mock^.MaxReadSectors = 1,'large volume discovery uses only metadata sector reads');
        PBootRecord(mock^.Data)^.FSInfoCluster := 1;
        puint32(PtrUInt(mock^.Data)+512)^ := $41615252;
        puint32(PtrUInt(mock^.Data)+512+484)^ := $61417272;
        puint32(PtrUInt(mock^.Data)+512+488)^ := 100;
        puint32(PtrUInt(mock^.Data)+512+508)^ := $AA550000;
        test.harness.Assert(@context, identify_volume(volume),'valid FSInfo avoids FAT scan');
        test.harness.Assert(@context, (volume^.freeSectors = 100) and
               ((volume^.lifecycleFlags and STORAGE_VOLUME_FLAG_FREE_UNKNOWN) = 0),'FSInfo count displayed');
        puint32(PtrUInt(mock^.Data)+512+488)^ := $FFFFFFFF;
        test.harness.Assert(@context, identify_volume(volume),'unknown FSInfo count does not prevent mount');
        test.harness.Assert(@context, (volume^.lifecycleFlags and STORAGE_VOLUME_FLAG_FREE_UNKNOWN) <> 0,'unknown FSInfo count stays unknown');
        puint32(PtrUInt(mock^.Data)+512+488)^ := 4096;
        test.harness.Assert(@context, identify_volume(volume),'out-of-range FSInfo count does not prevent mount');
        test.harness.Assert(@context, (volume^.lifecycleFlags and STORAGE_VOLUME_FLAG_FREE_UNKNOWN) <> 0,'out-of-range FSInfo count rejected');
        puint32(PtrUInt(mock^.Data)+512+488)^ := 0;
        test.harness.Assert(@context, identify_volume(volume),'full volume FSInfo accepted');
        test.harness.Assert(@context, (volume^.freeSectors = 0) and
               ((volume^.lifecycleFlags and STORAGE_VOLUME_FLAG_FREE_UNKNOWN) = 0),'known zero differs from unknown');
        puint32(PtrUInt(mock^.Data)+512+508)^ := 0;
        test.harness.Assert(@context, identify_volume(volume),'invalid FSInfo signature does not prevent mount');
        test.harness.Assert(@context, (volume^.lifecycleFlags and STORAGE_VOLUME_FLAG_FREE_UNKNOWN) <> 0,'invalid FSInfo signature rejected');
        mock^.FailReadLBA := 1;
        test.harness.Assert(@context, identify_volume(volume),'optional FSInfo read failure does not prevent mount');
        mock^.FailReadLBA := 0;
        FileRoundTrip('FAT32');
        FileRoundTrip('EXT2');
    end else test.harness.Assert(@context, false,'allocate multi-batch FAT fixture');
    kfree(device^.cachedMBR); CFIFO_Free(device^.requestQueue);
    kfree(void(mock^.Data)); kfree(void(mock)); kfree(void(volume)); kfree(void(device)); kfree(void(br));
    test.harness.Finish(@context);
end;

procedure UnitTest;
begin
    RunTests(false);
end;

procedure command(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin
    UnitTest;
    io.stdio.bufWriteStrLn(stdout_buf,'Storage metadata regression results written to serial log.');
end;

procedure init;
begin io.stdio.registerCommand('STORMETA',@command,'Run memory-backed storage metadata regression tests'); end;

end.
