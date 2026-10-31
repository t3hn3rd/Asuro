unit driver.storage.fs.ext2;

interface
uses driver.storage.types;
procedure init;
procedure ReleaseVolume(volume : PStorage_Volume);

implementation
uses boot.mgr, driver.storage.fs.mgr, driver.storage.vol.mgr,
     driver.storage.fs.ext2.types, driver.storage.fs.ext2.core,
     driver.storage.fs.ext2.format, memory.heap, core.util, core.strings,
     proc.mgr, proc.types;

type
    PWork = ^TWork;
    TWork = record
        Next : PWork;
        Volume : PStorage_Volume;
        FileCtx : PExt2File;
        Directory, Name : pchar;
        Offset, Count : uint32;
        Buffer, Completed : puint32;
        Writing : boolean;
        Callback : TIOCallback;
        CallbackData : pointer;
    end;
var
    filesystem : TFilesystem;
    worker : PProcessContext = nil;
    head, tail : PWork;
    queued : uint32;

procedure ReleaseVolume(volume : PStorage_Volume);
begin driver.storage.fs.ext2.core.ReleaseVolume(volume); end;

function DoTransfer(volume : PStorage_Volume; directory, name : pchar; offset : uint32;
                    buffer : puint32; count : uint32; ctx : pointer; writing : boolean; var error : TError) : uint32;
var f : PExt2File; size : uint32; owned : boolean;
begin
    f:=PExt2File(ctx); owned:=f=nil;
    if owned then f:=PExt2File(OpenFile(volume,directory,name,writing,size));
    if f=nil then begin DoTransfer:=0; error:=eFileDoesNotExist; exit; end;
    DoTransfer:=Transfer(volume,f,offset,buffer,count,writing,error);
    if owned then CloseFile(f);
end;

function ReadOffset(volume : PStorage_Volume; directory, name : pchar; offset : uint32;
                    buffer : puint32; count : uint32; ctx : pointer) : uint32;
var error : TError;
begin ReadOffset:=DoTransfer(volume,directory,name,offset,buffer,count,ctx,false,error); end;

function WriteOffset(volume : PStorage_Volume; directory, name : pchar; offset : uint32;
                     buffer : puint32; count : uint32; ctx : pointer) : uint32;
var error : TError;
begin WriteOffset:=DoTransfer(volume,directory,name,offset,buffer,count,ctx,true,error); end;

procedure FreeWork(work : PWork);
begin
    if work^.Directory<>nil then kfree(void(work^.Directory));
    if work^.Name<>nil then kfree(void(work^.Name));
    kfree(void(work));
end;

procedure WorkLoop(pctx : PProcessContext);
var work : PWork; done : uint32; error : TError; callback : TIOCallback; data : pointer;
begin
    while true do begin
        asm pushf; cli end;
        work:=head;
        if work<>nil then begin
            head:=work^.Next; if head=nil then tail:=nil; Dec(queued);
        end else pctx^.State:=psAwaiting;
        asm popf end;
        if work=nil then begin
            { Queue publication wakes the worker under the same CLI section.
              No per-I/O process, IRQ continuation, or volatile spin is needed. }
            proc.mgr.proc_yield;
            continue;
        end;
        done:=DoTransfer(work^.Volume,work^.Directory,work^.Name,work^.Offset,
                         work^.Buffer,work^.Count,work^.FileCtx,work^.Writing,error);
        if work^.Completed<>nil then work^.Completed^:=done;
        callback:=work^.Callback; data:=work^.CallbackData;
        FreeWork(work);
        if callback<>nil then callback(error,data);
    end;
end;

procedure StartWorker;
begin worker:=proc.mgr.create('ext2.io',@WorkLoop,nil,1); end;

procedure QueueTransfer(volume : PStorage_Volume; directory, name : pchar; offset : uint32;
    buffer : puint32; count : uint32; ctx : pointer; completed : puint32;
    callback : TIOCallback; data : pointer; writing : boolean);
var work : PWork; error : TError;
begin
    if completed<>nil then completed^:=0;
    error:=eNone;
    if (volume=nil) or ((buffer=nil) and (count<>0)) or (count>$FFFFFFFF-offset) then error:=eInvalidArgument
    else if worker=nil then error:=eDeviceNotReady;
    if error<>eNone then begin if callback<>nil then callback(error,data); exit; end;
    work:=PWork(kalloc(sizeof(TWork)));
    if work=nil then begin if callback<>nil then callback(eOutOfMemory,data); exit; end;
    memset(uint32(work),0,sizeof(TWork));
    if ctx=nil then begin
        if (directory=nil) or (name=nil) then error:=eInvalidArgument else begin
            work^.Directory:=stringCopy(directory); work^.Name:=stringCopy(name);
            if (work^.Directory=nil) or (work^.Name=nil) then error:=eOutOfMemory;
        end;
    end;
    if error<>eNone then begin FreeWork(work); if callback<>nil then callback(error,data); exit; end;
    work^.Volume:=volume; work^.FileCtx:=PExt2File(ctx); work^.Offset:=offset;
    work^.Buffer:=buffer; work^.Count:=count; work^.Completed:=completed;
    work^.Writing:=writing; work^.Callback:=callback; work^.CallbackData:=data;
    asm pushf; cli end;
    if queued>=64 then error:=eQueueFull else begin
        if tail=nil then head:=work else tail^.Next:=work;
        tail:=work; Inc(queued);
        if worker^.State=psAwaiting then worker^.State:=psReady;
    end;
    asm popf end;
    if error<>eNone then begin FreeWork(work); if callback<>nil then callback(error,data); end;
end;

procedure ReadAsync(volume : PStorage_Volume; directory, name : pchar; offset : uint32;
    buffer : puint32; count : uint32; ctx : pointer; completed : puint32; callback : TIOCallback; data : pointer);
begin QueueTransfer(volume,directory,name,offset,buffer,count,ctx,completed,callback,data,false); end;

procedure WriteAsync(volume : PStorage_Volume; directory, name : pchar; offset : uint32;
    buffer : puint32; count : uint32; ctx : pointer; completed : puint32; callback : TIOCallback; data : pointer);
begin QueueTransfer(volume,directory,name,offset,buffer,count,ctx,completed,callback,data,true); end;

function FileSize(volume : PStorage_Volume; directory, name : pchar) : uint32;
var f : pointer; size : uint32;
begin
    f:=OpenFile(volume,directory,name,false,size); FileSize:=size;
    if f<>nil then CloseFile(f);
end;

procedure CreateDirectory(volume : PStorage_Volume; directory, name : pchar; attributes : uint32; status : puint32);
var op : PExt2Op; parent, number : uint32; inode : TExt2Inode;
begin
    if status<>nil then status^:=ord(eOutOfMemory);
    op:=BeginOp(volume); if op=nil then exit;
    if Resolve(op,directory,parent,inode) then
        if CreateNode(op,parent,name,true,number) then FinishMutation(op);
    if status<>nil then status^:=ord(op^.Error);
    EndOp(op);
end;

procedure DeleteFile(volume : PStorage_Volume; path : pchar; status : puint32);
var op : PExt2Op;
begin
    if status<>nil then status^:=ord(eOutOfMemory);
    op:=BeginOp(volume); if op=nil then exit;
    RemoveNode(op,path,false); if status<>nil then status^:=ord(op^.Error); EndOp(op);
end;

procedure DeleteDirectory(volume : PStorage_Volume; path : pchar; status : puint32);
var op : PExt2Op;
begin
    if status<>nil then status^:=ord(eOutOfMemory);
    op:=BeginOp(volume); if op=nil then exit;
    RemoveNode(op,path,true); if status<>nil then status^:=ord(op^.Error); EndOp(op);
end;

procedure RenameFile(volume : PStorage_Volume; path, newName : pchar; status : puint32);
var op : PExt2Op;
begin
    if status<>nil then status^:=ord(eOutOfMemory);
    op:=BeginOp(volume); if op=nil then exit;
    RenameNode(op,path,newName); if status<>nil then status^:=ord(op^.Error); EndOp(op);
end;

procedure Detect(device : PStorage_Device);
var volume : PStorage_Volume;
begin
    if device=nil then exit;
    volume:=PStorage_Volume(kalloc(sizeof(TStorage_Volume))); if volume=nil then exit;
    memset(uint32(volume),0,sizeof(TStorage_Volume));
    volume^.device:=device; volume^.sectorCount:=device^.maxSectorCount; volume^.sectorSize:=device^.sectorSize;
    if Identify(volume) then begin
        volume^.filesystem:=@filesystem;
        driver.storage.vol.mgr.register_volume(device,volume);
    end else kfree(void(volume));
end;

procedure init;
begin
    memset(uint32(@filesystem),0,sizeof(filesystem));
    filesystem.sName:='EXT2'; filesystem.system_id:=$83;
    filesystem.identifyCallback:=@Identify; filesystem.detectCallback:=@Detect;
    filesystem.validateFormat:=@ValidateFormat; filesystem.createCallback:=@FormatVolume;
    filesystem.formatParamFlags:=FS_FORMAT_PARAM_CLUSTER_SIZE or FS_FORMAT_PARAM_FILE_COUNT or FS_FORMAT_PARAM_LABEL;
    filesystem.validateLabelCallback:=@ValidateLabel; filesystem.setLabelCallback:=@SetLabel;
    filesystem.readDirCallback:=@ReadDirectory; filesystem.createDirCallback:=@CreateDirectory;
    filesystem.deleteFileCallback:=@DeleteFile; filesystem.deleteDirCallback:=@DeleteDirectory;
    filesystem.renameFileCallback:=@RenameFile;
    filesystem.openFileModeCallback:=@OpenFile; filesystem.closeFileCallback:=@CloseFile;
    filesystem.readOffsetCallback:=@ReadOffset; filesystem.writeOffsetCallback:=@WriteOffset;
    filesystem.readOffsetAsyncCallback:=@ReadAsync; filesystem.writeOffsetAsyncCallback:=@WriteAsync;
    filesystem.fileSizeCallback:=@FileSize;
    driver.storage.fs.mgr.register_filesystem(@filesystem);
end;

initialization
    boot.mgr.registerBoot('driver.storage.fs.ext2',@init,'Ext2 Filesystem','driver.storage.fs.mgr');
    boot.mgr.registerBoot('driver.storage.ext2.worker',@StartWorker,'Ext2 I/O Worker','proc.mgr');
end.
