unit driver.storage.fs.ext2.format;

interface
uses driver.storage.types;
function ValidateFormat(volume : PStorage_Volume; sectors, start : uint32; config : PFSFormatParams) : TError;
function FormatVolume(volume : PStorage_Volume; sectors, start : uint32; config : PFSFormatParams) : TError;
function ValidateLabel(text : pchar; var normalized : TVolumeLabel) : TError;
function SetLabel(volume : PStorage_Volume; text : pchar) : TError;

implementation
uses driver.storage.fs.ext2.types, driver.storage.fs.ext2.core,
     driver.storage.mgr, memory.heap, core.util, core.rand;

function ValidateLabel(text : pchar; var normalized : TVolumeLabel) : TError;
var i : uint32;
begin
    memset(PtrUInt(@normalized),0,sizeof(normalized));
    ValidateLabel:=eInvalidArgument; if text=nil then exit;
    i:=0;
    while (i<16) and (text[i]<>char(0)) do begin
        if ord(text[i])<32 then exit;
        normalized[i]:=text[i]; Inc(i);
    end;
    if text[i]<>char(0) then begin ValidateLabel:=eFilenameTooLong; exit; end;
    ValidateLabel:=eNone;
end;

function Geometry(volume : PStorage_Volume; sectors, start : uint32; config : PFSFormatParams; var v : TExt2Volume) : TError;
var g, count, minimum, perBlock, tables, reserve : uint32; labelText : TVolumeLabel;
begin
    Geometry:=eInvalidArgument;
    memset(PtrUInt(@v),0,sizeof(v));
    if volume=nil then exit;
    if volume^.device=nil then exit;
    if not volume^.device^.writable then begin Geometry:=eReadOnly; exit; end;
    if (volume^.device^.sectorSize<>512) or (sectors<>volume^.sectorCount) or
       (start<>volume^.sectorStart) or (start>=volume^.device^.maxSectorCount) then exit;
    if sectors>volume^.device^.maxSectorCount-start then exit;
    v.Volume:=volume; v.SectorsPerBlock:=8;
    if config<>nil then begin
        if (config^.Version<>FS_FORMAT_PARAMS_VERSION_1) or
           ((config^.Flags and not uint16(FS_FORMAT_PARAM_CLUSTER_SIZE or FS_FORMAT_PARAM_FILE_COUNT or FS_FORMAT_PARAM_LABEL))<>0) then exit;
        if (config^.Flags and FS_FORMAT_PARAM_CLUSTER_SIZE)<>0 then v.SectorsPerBlock:=config^.ClusterSize;
        if (config^.Flags and FS_FORMAT_PARAM_LABEL)<>0 then begin
            { The shared format structure carries at most eleven label bytes. }
            if config^.LabelText[11]<>char(0) then exit;
            Geometry:=ValidateLabel(@config^.LabelText[0],labelText);
            if Geometry<>eNone then exit;
            Geometry:=eInvalidArgument;
        end;
    end;
    if (v.SectorsPerBlock<>2) and (v.SectorsPerBlock<>4) and (v.SectorsPerBlock<>8) then exit;
    v.BlockSize:=v.SectorsPerBlock*512; v.BlockCount:=sectors div v.SectorsPerBlock;
    v.FirstBlock:=ord(v.BlockSize=1024); v.BlocksPerGroup:=v.BlockSize*8; v.InodeSize:=128;
    if v.BlockCount<64 then exit;
    v.GroupCount:=(v.BlockCount-v.FirstBlock-1) div v.BlocksPerGroup+1;
    v.GDTBlocks:=(v.GroupCount-1) div (v.BlockSize div 32)+1;
    minimum:=v.BlocksPerGroup;
    for g:=0 to v.GroupCount-1 do begin
        count:=v.BlockCount-v.FirstBlock-g*v.BlocksPerGroup;
        if count>v.BlocksPerGroup then count:=v.BlocksPerGroup;
        if count<minimum then minimum:=count;
    end;
    perBlock:=v.BlockSize div 128;
    v.InodesPerGroup:=(minimum div 4 div perBlock)*perBlock;
    if v.InodesPerGroup<perBlock*2 then v.InodesPerGroup:=perBlock*2;
    if config<>nil then if (config^.Flags and FS_FORMAT_PARAM_FILE_COUNT)<>0 then begin
        if config^.FileCount<11 then exit;
        v.InodesPerGroup:=(config^.FileCount-1) div v.GroupCount+1;
        if v.InodesPerGroup>v.BlockSize*8 then exit;
        v.InodesPerGroup:=((v.InodesPerGroup+perBlock-1) div perBlock)*perBlock;
    end;
    if (v.InodesPerGroup<16) or (v.InodesPerGroup>v.BlockSize*8) then exit;
    v.InodeCount:=v.InodesPerGroup*v.GroupCount;
    tables:=v.InodesPerGroup div perBlock;
    for g:=0 to v.GroupCount-1 do begin
        count:=v.BlockCount-v.FirstBlock-g*v.BlocksPerGroup;
        if count>v.BlocksPerGroup then count:=v.BlocksPerGroup;
        reserve:=2+tables;
        if HasSuper(g,1) then Inc(reserve,1+v.GDTBlocks);
        if g=0 then Inc(reserve); { root directory }
        if reserve>=count then exit;
    end;
    Geometry:=eNone;
end;

function ValidateFormat(volume : PStorage_Volume; sectors, start : uint32; config : PFSFormatParams) : TError;
var v : TExt2Volume;
begin ValidateFormat:=Geometry(volume,sectors,start,config,v); end;

function FormatVolume(volume : PStorage_Volume; sectors, start : uint32; config : PFSFormatParams) : TError;
var v : PExt2Volume; op : PExt2Op; d : PExt2Group; inode : PExt2Inode;
    err : TError; g, first, count, reserve, tables, used, i, bit, rootBlock, freeBlocks : uint32;
begin
    FormatVolume:=eOutOfMemory;
    v:=PExt2Volume(kalloc(sizeof(TExt2Volume))); if v=nil then exit;
    err:=Geometry(volume,sectors,start,config,v^);
    if err<>eNone then begin kfree(void(v)); FormatVolume:=err; exit; end;
    op:=PExt2Op(kalloc(sizeof(TExt2Op)));
    if op=nil then begin kfree(void(v)); exit; end;
    memset(PtrUInt(op),0,sizeof(TExt2Op)); op^.V:=v;
    v^.Super:=puint8(kalloc(1024)); v^.Groups:=puint8(kalloc(v^.GDTBlocks*v^.BlockSize));
    op^.Scratch:=puint8(kalloc(v^.BlockSize));
    if (v^.Super=nil) or (v^.Groups=nil) or (op^.Scratch=nil) then begin
        if v^.Super<>nil then kfree(void(v^.Super)); if v^.Groups<>nil then kfree(void(v^.Groups));
        if op^.Scratch<>nil then kfree(void(op^.Scratch));
        kfree(void(op)); kfree(void(v)); exit;
    end;
    memset(PtrUInt(v^.Super),0,1024); memset(PtrUInt(v^.Groups),0,v^.GDTBlocks*v^.BlockSize);
    Put32(v^.Super,0,v^.InodeCount); Put32(v^.Super,4,v^.BlockCount);
    Put32(v^.Super,16,v^.InodeCount-10); Put32(v^.Super,20,v^.FirstBlock);
    i:=0; if v^.BlockSize=2048 then i:=1 else if v^.BlockSize=4096 then i:=2;
    Put32(v^.Super,24,i); Put32(v^.Super,28,i);
    Put32(v^.Super,32,v^.BlocksPerGroup); Put32(v^.Super,36,v^.BlocksPerGroup);
    Put32(v^.Super,40,v^.InodesPerGroup); Put16(v^.Super,54,$FFFF);
    Put16(v^.Super,56,EXT2_MAGIC); Put16(v^.Super,58,1); Put16(v^.Super,60,1);
    Put32(v^.Super,76,1); Put32(v^.Super,84,11); Put16(v^.Super,88,128);
    Put32(v^.Super,96,2); Put32(v^.Super,100,3); { file types, sparse super, large file }
    for i:=0 to 3 do Put32(v^.Super,104+i*4,core.rand.rand32);
    v^.Super[110]:=(v^.Super[110] and $0F) or $40;
    v^.Super[112]:=(v^.Super[112] and $3F) or $80;
    if config<>nil then if (config^.Flags and FS_FORMAT_PARAM_LABEL)<>0 then
        memcpy(PtrUInt(@config^.LabelText[0]),PtrUInt(v^.Super)+120,11);
    tables:=v^.InodesPerGroup div (v^.BlockSize div 128); freeBlocks:=0; rootBlock:=0;
    for g:=0 to v^.GroupCount-1 do begin
        first:=v^.FirstBlock+g*v^.BlocksPerGroup; count:=v^.BlockCount-first;
        if count>v^.BlocksPerGroup then count:=v^.BlocksPerGroup;
        reserve:=0; if HasSuper(g,1) then reserve:=1+v^.GDTBlocks;
        d:=PExt2Group(PtrUInt(v^.Groups)+g*32);
        d^.BlockBitmap:=first+reserve; d^.InodeBitmap:=first+reserve+1; d^.InodeTable:=first+reserve+2;
        used:=reserve+2+tables;
        d^.FreeInodes:=v^.InodesPerGroup;
        if g=0 then begin rootBlock:=first+used; Inc(used); Dec(d^.FreeInodes,10); d^.Directories:=1; end;
        d^.FreeBlocks:=count-used; Inc(freeBlocks,d^.FreeBlocks);
    end;
    Put32(v^.Super,12,freeBlocks);
    { Invalidate the primary signature before writing metadata. Publish it last. }
    memset(PtrUInt(op^.Scratch),0,v^.BlockSize);
    op^.Error:=storage_write(volume^.device,start+2,2,puint32(op^.Scratch));
    g:=0;
    while (g<v^.GroupCount) and (op^.Error=eNone) do begin
        first:=v^.FirstBlock+g*v^.BlocksPerGroup; count:=v^.BlockCount-first;
        if count>v^.BlocksPerGroup then count:=v^.BlocksPerGroup;
        d:=PExt2Group(PtrUInt(v^.Groups)+g*32); used:=count-d^.FreeBlocks;
        memset(PtrUInt(op^.Scratch),$FF,v^.BlockSize);
        for bit:=used to count-1 do op^.Scratch[bit div 8]:=op^.Scratch[bit div 8] and not (1 shl (bit mod 8));
        WriteBlock(op,d^.BlockBitmap,op^.Scratch);
        memset(PtrUInt(op^.Scratch),$FF,v^.BlockSize);
        used:=0; if g=0 then used:=10;
        for bit:=used to v^.InodesPerGroup-1 do op^.Scratch[bit div 8]:=op^.Scratch[bit div 8] and not (1 shl (bit mod 8));
        WriteBlock(op,d^.InodeBitmap,op^.Scratch);
        memset(PtrUInt(op^.Scratch),0,v^.BlockSize);
        for i:=0 to tables-1 do begin
            if not WriteBlock(op,d^.InodeTable+i,op^.Scratch) then break;
        end;
        if HasSuper(g,1) then begin
            for i:=0 to v^.GDTBlocks-1 do
                if not WriteBlock(op,first+1+i,pointer(PtrUInt(v^.Groups)+i*v^.BlockSize)) then break;
            if g<>0 then begin
                memset(PtrUInt(op^.Scratch),0,v^.BlockSize);
                memcpy(PtrUInt(v^.Super),PtrUInt(op^.Scratch),1024); Put16(op^.Scratch,90,g);
                WriteBlock(op,first,op^.Scratch);
            end;
        end;
        Inc(g);
    end;
    if op^.Error=eNone then begin
        memset(PtrUInt(op^.Scratch),0,v^.BlockSize);
        inode:=PExt2Inode(PtrUInt(op^.Scratch)+128);
        inode^.Mode:=EXT2_DIR or $1ED; inode^.Size:=v^.BlockSize; inode^.Links:=2;
        inode^.Sectors:=v^.SectorsPerBlock; inode^.Blocks[0]:=rootBlock;
        WriteBlock(op,PExt2Group(v^.Groups)^.InodeTable,op^.Scratch);
        memset(PtrUInt(op^.Scratch),0,v^.BlockSize);
        Put32(op^.Scratch,0,2); Put16(op^.Scratch,4,12); op^.Scratch[6]:=1; op^.Scratch[7]:=2; op^.Scratch[8]:=ord('.');
        Put32(op^.Scratch,12,2); Put16(op^.Scratch,16,v^.BlockSize-12); op^.Scratch[18]:=2; op^.Scratch[19]:=2;
        op^.Scratch[20]:=ord('.'); op^.Scratch[21]:=ord('.');
        WriteBlock(op,rootBlock,op^.Scratch);
        if op^.Error=eNone then op^.Error:=storage_write(volume^.device,start+2,2,puint32(v^.Super));
    end;
    err:=op^.Error;
    kfree(void(op^.Scratch)); kfree(void(v^.Super)); kfree(void(v^.Groups)); kfree(void(op)); kfree(void(v));
    FormatVolume:=err;
end;

function SetLabel(volume : PStorage_Volume; text : pchar) : TError;
var op : PExt2Op; labelText : TVolumeLabel; g, first : uint32;
begin
    SetLabel:=ValidateLabel(text,labelText); if SetLabel<>eNone then exit;
    op:=BeginOp(volume); if op=nil then begin SetLabel:=eOutOfMemory; exit; end;
    if BeginMutation(op) then begin
        memcpy(PtrUInt(@labelText),PtrUInt(op^.V^.Super)+120,16);
        for g:=1 to op^.V^.GroupCount-1 do if HasSuper(g,Get32(op^.V^.Super,100)) then begin
            first:=op^.V^.FirstBlock+g*op^.V^.BlocksPerGroup;
            if not ReadBlock(op,first,op^.Scratch) then break;
            memcpy(PtrUInt(@labelText),PtrUInt(op^.Scratch)+120,16);
            if not WriteBlock(op,first,op^.Scratch) then break;
        end;
        if FinishMutation(op) then memcpy(PtrUInt(@labelText),PtrUInt(@volume^.labelText),sizeof(labelText));
    end;
    SetLabel:=op^.Error; EndOp(op);
end;

end.
