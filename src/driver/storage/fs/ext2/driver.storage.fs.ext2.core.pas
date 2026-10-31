unit driver.storage.fs.ext2.core;

interface
uses driver.storage.types, driver.storage.fs.ext2.types, core.ds.lists;

function Get16(p : pointer; offset : uint32) : uint16;
function Get32(p : pointer; offset : uint32) : uint32;
procedure Put16(p : pointer; offset : uint32; value : uint16);
procedure Put32(p : pointer; offset, value : uint32);
function HasSuper(group, features : uint32) : boolean;
function Identify(volume : PStorage_Volume) : boolean;
procedure ReleaseVolume(volume : PStorage_Volume);
function BeginOp(volume : PStorage_Volume) : PExt2Op;
procedure EndOp(op : PExt2Op);
function BeginMutation(op : PExt2Op) : boolean;
function FinishMutation(op : PExt2Op) : boolean;
function ReadBlock(op : PExt2Op; block : uint32; dest : pointer) : boolean;
function WriteBlock(op : PExt2Op; block : uint32; src : pointer) : boolean;
function ReadInode(op : PExt2Op; number : uint32; var inode : TExt2Inode) : boolean;
function WriteInode(op : PExt2Op; number : uint32; var inode : TExt2Inode) : boolean;
function MapBlock(op : PExt2Op; number : uint32; var inode : TExt2Inode;
                  logical : uint32; createBlocks : boolean; var block : uint32) : boolean;
function Resolve(op : PExt2Op; path : pchar; var number : uint32; var inode : TExt2Inode) : boolean;
function Lookup(op : PExt2Op; var dir : TExt2Inode; name : pchar; length : uint32;
                var number, block, offset : uint32) : boolean;
function CreateNode(op : PExt2Op; parent : uint32; name : pchar; isDir : boolean;
                    var number : uint32) : boolean;
function RemoveNode(op : PExt2Op; path : pchar; isDir : boolean) : boolean;
function RenameNode(op : PExt2Op; path, newName : pchar) : boolean;
function ReadDirectory(volume : PStorage_Volume; directory : pchar; status : puint32) : PLinkedListBase;
function Transfer(volume : PStorage_Volume; fileCtx : PExt2File; offset : uint32;
                  buffer : puint32; count : uint32; writing : boolean; var error : TError) : uint32;
function OpenFile(volume : PStorage_Volume; directory, name : pchar;
                  allowCreate : boolean; var size : uint32) : pointer;
procedure CloseFile(ctx : pointer);
procedure FreeEntries(entries : PLinkedListBase);

implementation
uses memory.heap, core.util, core.strings, driver.storage.mgr;

function Get16(p : pointer; offset : uint32) : uint16;
begin Get16 := puint16(uint32(p)+offset)^; end;
function Get32(p : pointer; offset : uint32) : uint32;
begin Get32 := puint32(uint32(p)+offset)^; end;
procedure Put16(p : pointer; offset : uint32; value : uint16);
begin puint16(uint32(p)+offset)^ := value; end;
procedure Put32(p : pointer; offset, value : uint32);
begin puint32(uint32(p)+offset)^ := value; end;

function PowerOf(value, base : uint32) : boolean;
begin
    while (value > 1) and (value mod base = 0) do value := value div base;
    PowerOf := value = 1;
end;

function HasSuper(group, features : uint32) : boolean;
begin
    HasSuper := ((features and 1) = 0) or (group <= 1) or
                PowerOf(group,3) or PowerOf(group,5) or PowerOf(group,7);
end;

function GroupDesc(v : PExt2Volume; group : uint32) : PExt2Group;
begin GroupDesc := PExt2Group(uint32(v^.Groups)+group*32); end;

function GroupBlocks(v : PExt2Volume; group : uint32) : uint32;
var first, count : uint32;
begin
    first := v^.FirstBlock+group*v^.BlocksPerGroup;
    count := v^.BlockCount-first;
    if count > v^.BlocksPerGroup then count := v^.BlocksPerGroup;
    GroupBlocks := count;
end;

function DataBlock(v : PExt2Volume; block : uint32) : boolean;
var g, first, tables, reserve : uint32; d : PExt2Group;
begin
    DataBlock := false;
    if (block <= v^.FirstBlock) or (block >= v^.BlockCount) then exit;
    g := (block-v^.FirstBlock) div v^.BlocksPerGroup;
    d := GroupDesc(v,g);
    if (block = d^.BlockBitmap) or (block = d^.InodeBitmap) then exit;
    tables := v^.InodesPerGroup div (v^.BlockSize div v^.InodeSize);
    if (block >= d^.InodeTable) and (block-d^.InodeTable < tables) then exit;
    first := v^.FirstBlock+g*v^.BlocksPerGroup;
    reserve := 1+v^.GDTBlocks+Get16(v^.Super,206);
    if HasSuper(g,Get32(v^.Super,100)) and (block-first < reserve) then exit;
    DataBlock := true;
end;

function ReadBlock(op : PExt2Op; block : uint32; dest : pointer) : boolean;
begin
    ReadBlock := false;
    if op^.Error <> eNone then exit;
    if block >= op^.V^.BlockCount then begin op^.Error := eCorruptFilesystem; exit; end;
    op^.Error := storage_read(op^.V^.Volume^.device,
        op^.V^.Volume^.sectorStart+block*op^.V^.SectorsPerBlock,
        op^.V^.SectorsPerBlock,puint32(dest));
    ReadBlock := op^.Error = eNone;
end;

function WriteBlock(op : PExt2Op; block : uint32; src : pointer) : boolean;
begin
    WriteBlock := false;
    if op^.Error <> eNone then exit;
    if block >= op^.V^.BlockCount then begin op^.Error := eCorruptFilesystem; exit; end;
    op^.Error := storage_write(op^.V^.Volume^.device,
        op^.V^.Volume^.sectorStart+block*op^.V^.SectorsPerBlock,
        op^.V^.SectorsPerBlock,puint32(src));
    WriteBlock := op^.Error = eNone;
end;

function SaveSuper(op : PExt2Op) : boolean;
begin
    op^.Error := storage_write(op^.V^.Volume^.device,op^.V^.Volume^.sectorStart+2,
                               2,puint32(op^.V^.Super));
    SaveSuper := op^.Error = eNone;
end;

function BeginOp(volume : PStorage_Volume) : PExt2Op;
var op : PExt2Op; v : PExt2Volume;
begin
    BeginOp := nil;
    if volume = nil then exit;
    v := PExt2Volume(volume^.fsPrivate);
    if v = nil then exit;
    op := PExt2Op(kalloc(sizeof(TExt2Op)));
    if op = nil then exit;
    memset(uint32(op),0,sizeof(TExt2Op));
    op^.V := v;
    op^.Scratch := puint8(kalloc(v^.BlockSize*2));
    if op^.Scratch = nil then begin kfree(void(op)); exit; end;
    op^.Data := puint8(uint32(op^.Scratch)+v^.BlockSize);
    while true do begin
        asm pushf; cli end;
        if not v^.Busy then begin
            v^.Busy := true;
            asm popf end;
            break;
        end;
        asm popf end;
        asm hlt end;
    end;
    BeginOp := op;
end;

procedure EndOp(op : PExt2Op);
begin
    if op = nil then exit;
    { An interrupted metadata transaction remains dirty and cannot be written
      again until repaired offline. Never publish a clean superblock on error. }
    if op^.Mutating then op^.V^.Poisoned := true;
    op^.V^.Busy := false;
    kfree(void(op^.Scratch)); kfree(void(op));
end;

function BeginMutation(op : PExt2Op) : boolean;
begin
    BeginMutation := false;
    if op^.Error <> eNone then exit;
    if not op^.V^.Writable or op^.V^.Poisoned then begin op^.Error := eReadOnly; exit; end;
    if op^.Mutating then begin BeginMutation := true; exit; end;
    op^.Mutating := true;
    Put16(op^.V^.Super,58,0);
    BeginMutation := SaveSuper(op);
end;

function FinishMutation(op : PExt2Op) : boolean;
begin
    FinishMutation := false;
    if op^.Error <> eNone then exit;
    if op^.Mutating then begin
        Put16(op^.V^.Super,58,1);
        if not SaveSuper(op) then begin Put16(op^.V^.Super,58,0); exit; end;
        op^.Mutating := false;
        op^.V^.Volume^.freeSectors := Get32(op^.V^.Super,12)*op^.V^.SectorsPerBlock;
    end;
    FinishMutation := true;
end;

function InodeLocation(op : PExt2Op; number : uint32; var block, offset : uint32) : boolean;
var group, index : uint32;
begin
    InodeLocation := false;
    if (number = 0) or (number > op^.V^.InodeCount) then begin op^.Error := eCorruptFilesystem; exit; end;
    group := (number-1) div op^.V^.InodesPerGroup;
    index := (number-1) mod op^.V^.InodesPerGroup;
    block := GroupDesc(op^.V,group)^.InodeTable+index div (op^.V^.BlockSize div op^.V^.InodeSize);
    offset := (index mod (op^.V^.BlockSize div op^.V^.InodeSize))*op^.V^.InodeSize;
    InodeLocation := true;
end;

function ReadInode(op : PExt2Op; number : uint32; var inode : TExt2Inode) : boolean;
var block, offset : uint32;
begin
    ReadInode := false;
    if not InodeLocation(op,number,block,offset) then exit;
    if not ReadBlock(op,block,op^.Scratch) then exit;
    memcpy(uint32(op^.Scratch)+offset,uint32(@inode),128);
    if (inode.Links = 0) or (inode.DTime <> 0) then begin op^.Error := eCorruptFilesystem; exit; end;
    { Compression, extents and inline data are not ext2 block maps. }
    if (inode.Flags and ($4 or $200 or $800 or $80000 or $10000000)) <> 0 then begin op^.Error := eNotSupported; exit; end;
    if ((inode.Mode and $F000) = EXT2_FILE) and (inode.SizeHigh <> 0) then begin op^.Error := eNotSupported; exit; end;
    ReadInode := true;
end;

function WriteInode(op : PExt2Op; number : uint32; var inode : TExt2Inode) : boolean;
var block, offset : uint32;
begin
    WriteInode := false;
    if not InodeLocation(op,number,block,offset) then exit;
    if not ReadBlock(op,block,op^.Scratch) then exit;
    memcpy(uint32(@inode),uint32(op^.Scratch)+offset,128);
    WriteInode := WriteBlock(op,block,op^.Scratch);
end;

procedure FreeVolume(v : PExt2Volume);
begin
    if v^.Groups <> nil then kfree(void(v^.Groups));
    if v^.Super <> nil then kfree(void(v^.Super));
    kfree(void(v));
end;

function LoadVolume(v : PExt2Volume) : boolean;
var s : puint8; g, first, count, tables, reserve, i : uint32; d : PExt2Group;
    op : TExt2Op; inode : TExt2Inode;
begin
    LoadVolume := false; s := v^.Super;
    if (Get16(s,56) <> EXT2_MAGIC) or (Get32(s,24) > 2) or (Get32(s,76) > 1) then exit;
    if Get32(s,28) <> Get32(s,24) then exit; { fragments unsupported }
    { Accept classic ext2 only; never claim ext3/ext4 volumes. }
    if (Get32(s,76) <> 0) and
       (((Get32(s,92) and not uint32($38)) <> 0) or
        ((Get32(s,96) and not uint32(2)) <> 0) or
        ((Get32(s,100) and not uint32(3)) <> 0)) then exit;
    v^.BlockSize := 1024 shl Get32(s,24); v^.SectorsPerBlock := v^.BlockSize div 512;
    v^.BlockCount := Get32(s,4); v^.InodeCount := Get32(s,0);
    v^.FirstBlock := Get32(s,20); v^.BlocksPerGroup := Get32(s,32); v^.InodesPerGroup := Get32(s,40);
    v^.InodeSize := 128;
    if Get32(s,76) <> 0 then v^.InodeSize := Get16(s,88);
    if (v^.BlockCount <= v^.FirstBlock) or (v^.InodeCount < 11) or
       (v^.BlockCount > v^.Volume^.sectorCount div v^.SectorsPerBlock) or
       (v^.FirstBlock <> uint32(ord(v^.BlockSize=1024))) or
       (v^.BlocksPerGroup = 0) or (v^.BlocksPerGroup > v^.BlockSize*8) or
       (v^.InodesPerGroup = 0) or (v^.InodesPerGroup > v^.BlockSize*8) or
       (v^.InodeSize < 128) or (v^.InodeSize > v^.BlockSize) then exit;
    if (v^.InodeSize and (v^.InodeSize-1)) <> 0 then exit;
    if v^.InodesPerGroup mod (v^.BlockSize div v^.InodeSize) <> 0 then exit;
    v^.GroupCount := (v^.BlockCount-v^.FirstBlock-1) div v^.BlocksPerGroup+1;
    if (v^.InodeCount-1) div v^.InodesPerGroup+1 <> v^.GroupCount then exit;
    if (Get32(s,12) > v^.BlockCount) or (Get32(s,16) > v^.InodeCount) then exit;
    v^.GDTBlocks := (v^.GroupCount-1) div (v^.BlockSize div 32)+1;
    if v^.GDTBlocks >= v^.BlockCount-v^.FirstBlock then exit;
    v^.Groups := puint8(kalloc(v^.GDTBlocks*v^.BlockSize));
    if v^.Groups = nil then exit;
    memset(uint32(@op),0,sizeof(op)); op.V := v;
    for i := 0 to v^.GDTBlocks-1 do
        if not ReadBlock(@op,v^.FirstBlock+1+i,pointer(uint32(v^.Groups)+i*v^.BlockSize)) then exit;
    tables := v^.InodesPerGroup div (v^.BlockSize div v^.InodeSize);
    for g := 0 to v^.GroupCount-1 do begin
        d := GroupDesc(v,g); first := v^.FirstBlock+g*v^.BlocksPerGroup; count := GroupBlocks(v,g);
        reserve := 0;
        if HasSuper(g,Get32(s,100)) then reserve := 1+v^.GDTBlocks+Get16(s,206);
        if (reserve >= count) or (tables >= count-reserve) then exit;
        if (d^.BlockBitmap < first+reserve) or (d^.BlockBitmap >= first+count) or
           (d^.InodeBitmap < first+reserve) or (d^.InodeBitmap >= first+count) or
           (d^.BlockBitmap = d^.InodeBitmap) or
           (d^.InodeTable < first+reserve) or (d^.InodeTable > first+count-tables) or
           (d^.FreeBlocks > count) or (d^.FreeInodes > v^.InodesPerGroup) then exit;
        if ((d^.BlockBitmap >= d^.InodeTable) and (d^.BlockBitmap-d^.InodeTable < tables)) or
           ((d^.InodeBitmap >= d^.InodeTable) and (d^.InodeBitmap-d^.InodeTable < tables)) then exit;
    end;
    op.Scratch := puint8(kalloc(v^.BlockSize));
    if op.Scratch = nil then exit;
    LoadVolume := ReadInode(@op,2,inode);
    if LoadVolume then LoadVolume := ((inode.Mode and $F000) = EXT2_DIR) and (inode.Size > 0);
    kfree(void(op.Scratch));
    v^.FileTypes := (Get32(s,76) <> 0) and ((Get32(s,96) and 2) <> 0);
    v^.Writable := v^.Volume^.device^.writable and (Get16(s,58)=1) and (Get32(s,232)=0);
end;

function Identify(volume : PStorage_Volume) : boolean;
var v : PExt2Volume; i : uint32;
begin
    Identify := false;
    if volume = nil then exit;
    if volume^.device = nil then exit;
    if (volume^.device^.sectorSize <> 512) or (volume^.sectorCount < 4) or
       (volume^.sectorStart >= volume^.device^.maxSectorCount) then exit;
    if volume^.sectorCount > volume^.device^.maxSectorCount-volume^.sectorStart then exit;
    if volume^.fsPrivate <> nil then exit;
    v := PExt2Volume(kalloc(sizeof(TExt2Volume)));
    if v = nil then exit;
    memset(uint32(v),0,sizeof(TExt2Volume)); v^.Volume := volume;
    v^.Super := puint8(kalloc(1024));
    if v^.Super = nil then begin FreeVolume(v); exit; end;
    if storage_read(volume^.device,volume^.sectorStart+2,2,puint32(v^.Super)) <> eNone then begin FreeVolume(v); exit; end;
    if not LoadVolume(v) then begin FreeVolume(v); exit; end;
    volume^.fsPrivate := v; volume^.sectorSize := 512;
    volume^.freeSectors := Get32(v^.Super,12)*v^.SectorsPerBlock;
    memset(uint32(@volume^.labelText),0,sizeof(volume^.labelText));
    for i := 0 to 15 do volume^.labelText[i] := char(v^.Super[120+i]);
    Identify := true;
end;

procedure ReleaseVolume(volume : PStorage_Volume);
var v : PExt2Volume;
begin
    if volume = nil then exit;
    v := PExt2Volume(volume^.fsPrivate);
    if v = nil then exit;
    volume^.fsPrivate := nil; FreeVolume(v);
end;

function SaveGroup(op : PExt2Op; group : uint32) : boolean;
var block : uint32;
begin
    block := group div (op^.V^.BlockSize div 32);
    SaveGroup := WriteBlock(op,op^.V^.FirstBlock+1+block,
                            pointer(uint32(op^.V^.Groups)+block*op^.V^.BlockSize));
end;

function Allocate(op : PExt2Op; inodeBit : boolean; var number : uint32) : boolean;
var v : PExt2Volume; d : PExt2Group; pass, g, limit, bit, b, mask, absolute : uint32;
begin
    Allocate := false; number := 0; v := op^.V;
    for pass := 0 to v^.GroupCount-1 do begin
        g := (v^.AllocGroup+pass) mod v^.GroupCount; d := GroupDesc(v,g);
        if inodeBit then begin
            if d^.FreeInodes = 0 then continue;
            b := d^.InodeBitmap; limit := v^.InodesPerGroup;
            if limit > v^.InodeCount-g*v^.InodesPerGroup then limit := v^.InodeCount-g*v^.InodesPerGroup;
        end else begin
            if d^.FreeBlocks = 0 then continue;
            b := d^.BlockBitmap; limit := GroupBlocks(v,g);
        end;
        if not ReadBlock(op,b,op^.Scratch) then exit;
        bit := 0;
        while bit < limit do begin
            { Skip whole allocated bitmap words on the allocation hot path. }
            if (bit mod 32 = 0) and (limit-bit >= 32) and (Get32(op^.Scratch,bit div 8)=$FFFFFFFF) then begin Inc(bit,32); continue; end;
            mask := 1 shl (bit mod 8);
            if (op^.Scratch[bit div 8] and mask) = 0 then begin
                if inodeBit then absolute := g*v^.InodesPerGroup+bit+1
                else absolute := v^.FirstBlock+g*v^.BlocksPerGroup+bit;
                if inodeBit then begin
                    if absolute < 11 then begin Inc(bit); continue; end;
                end else if not DataBlock(v,absolute) then begin op^.Error := eCorruptFilesystem; exit; end;
                op^.Scratch[bit div 8] := op^.Scratch[bit div 8] or mask;
                if not WriteBlock(op,b,op^.Scratch) then exit;
                if inodeBit then begin
                    if Get32(v^.Super,16)=0 then begin op^.Error:=eCorruptFilesystem; exit; end;
                    Dec(d^.FreeInodes); Put32(v^.Super,16,Get32(v^.Super,16)-1);
                end else begin
                    if Get32(v^.Super,12)=0 then begin op^.Error:=eCorruptFilesystem; exit; end;
                    Dec(d^.FreeBlocks); Put32(v^.Super,12,Get32(v^.Super,12)-1);
                end;
                if not SaveGroup(op,g) then exit;
                v^.AllocGroup := g; number := absolute;
                if not inodeBit then begin
                    memset(uint32(op^.Scratch),0,v^.BlockSize);
                    if not WriteBlock(op,number,op^.Scratch) then exit;
                end;
                Allocate := true; exit;
            end;
            Inc(bit);
        end;
    end;
    op^.Error := eDiskFull;
end;

function FreeNumber(op : PExt2Op; number : uint32; inodeBit : boolean) : boolean;
var v : PExt2Volume; d : PExt2Group; g, bit, b, mask : uint32;
begin
    FreeNumber := false; v := op^.V;
    if inodeBit then begin
        if (number < 11) or (number > v^.InodeCount) then begin op^.Error := eCorruptFilesystem; exit; end;
        g := (number-1) div v^.InodesPerGroup; bit := (number-1) mod v^.InodesPerGroup;
    end else begin
        if not DataBlock(v,number) then begin op^.Error := eCorruptFilesystem; exit; end;
        g := (number-v^.FirstBlock) div v^.BlocksPerGroup; bit := (number-v^.FirstBlock) mod v^.BlocksPerGroup;
    end;
    d := GroupDesc(v,g);
    if inodeBit then b := d^.InodeBitmap else b := d^.BlockBitmap;
    if not ReadBlock(op,b,op^.Scratch) then exit;
    mask := 1 shl (bit mod 8);
    if (op^.Scratch[bit div 8] and mask)=0 then begin op^.Error := eCorruptFilesystem; exit; end;
    op^.Scratch[bit div 8] := op^.Scratch[bit div 8] and not mask;
    if not WriteBlock(op,b,op^.Scratch) then exit;
    if inodeBit then begin Inc(d^.FreeInodes); Put32(v^.Super,16,Get32(v^.Super,16)+1); end
    else begin Inc(d^.FreeBlocks); Put32(v^.Super,12,Get32(v^.Super,12)+1); end;
    FreeNumber := SaveGroup(op,g);
end;

function MapBlock(op : PExt2Op; number : uint32; var inode : TExt2Inode;
                  logical : uint32; createBlocks : boolean; var block : uint32) : boolean;
var n, level, slot, span, index, parent, child, remaining : uint32;
begin
    MapBlock := false; block := 0; n := op^.V^.BlockSize div 4;
    level := 0; slot := logical; remaining := logical;
    if logical >= 12 then begin
        remaining := logical-12; slot := 12; level := 1; span := n;
        while (remaining >= span) and (level < 3) do begin
            Dec(remaining,span); Inc(level); Inc(slot); span := span*n;
        end;
        if remaining >= span then begin op^.Error := eNotSupported; exit; end;
    end;
    block := inode.Blocks[slot];
    if (block=0) and createBlocks then begin
        if not Allocate(op,false,block) then exit;
        inode.Blocks[slot] := block; Inc(inode.Sectors,op^.V^.SectorsPerBlock);
        if not WriteInode(op,number,inode) then exit;
    end;
    while (level > 0) and (block <> 0) do begin
        if not DataBlock(op^.V,block) then begin op^.Error:=eCorruptFilesystem; exit; end;
        if not ReadBlock(op,block,op^.Scratch) then exit;
        span := 1;
        if level=2 then span:=n else if level=3 then span:=n*n;
        index := remaining div span; remaining := remaining mod span;
        parent := block; child := Get32(op^.Scratch,index*4);
        if (child=0) and createBlocks then begin
            if not Allocate(op,false,child) then exit;
            if not ReadBlock(op,parent,op^.Scratch) then exit;
            Put32(op^.Scratch,index*4,child);
            if not WriteBlock(op,parent,op^.Scratch) then exit;
            Inc(inode.Sectors,op^.V^.SectorsPerBlock);
            if not WriteInode(op,number,inode) then exit;
        end;
        block := child; Dec(level);
    end;
    if (block <> 0) and not DataBlock(op^.V,block) then begin op^.Error:=eCorruptFilesystem; exit; end;
    MapBlock := true;
end;

function DirRecord(op : PExt2Op; offset, limit : uint32; var d : PExt2Dirent) : boolean;
var i, length : uint32;
begin
    DirRecord := false;
    if limit-offset < 8 then begin op^.Error:=eCorruptFilesystem; exit; end;
    d := PExt2Dirent(uint32(op^.Data)+offset);
    length := d^.NameLength;
    if not op^.V^.FileTypes and (d^.FileType <> 0) then begin op^.Error:=eCorruptFilesystem; exit; end;
    if (d^.Length < 8) or (d^.Length mod 4 <> 0) or (d^.Length > limit-offset) or
       (length > d^.Length-8) or (d^.Inode > op^.V^.InodeCount) then begin op^.Error:=eCorruptFilesystem; exit; end;
    if d^.Inode <> 0 then begin
        if length=0 then begin op^.Error:=eCorruptFilesystem; exit; end;
        for i:=0 to length-1 do
            if (op^.Data[offset+8+i]=0) or (op^.Data[offset+8+i]=ord('/')) then begin op^.Error:=eCorruptFilesystem; exit; end;
    end;
    DirRecord := true;
end;

function SameName(raw : pchar; name : pchar; length : uint32) : boolean;
var i : uint32;
begin
    SameName := false;
    if length=0 then exit;
    for i:=0 to length-1 do if raw[i]<>name[i] then exit;
    SameName := true;
end;

function Lookup(op : PExt2Op; var dir : TExt2Inode; name : pchar; length : uint32;
                var number, block, offset : uint32) : boolean;
var logical, count : uint32; d : PExt2Dirent;
begin
    Lookup := false; number:=0;
    if (dir.Mode and $F000)<>EXT2_DIR then begin op^.Error:=eNotADirectory; exit; end;
    if (dir.Size=0) or (dir.Size mod op^.V^.BlockSize<>0) then begin op^.Error:=eCorruptFilesystem; exit; end;
    count:=dir.Size div op^.V^.BlockSize;
    if count>op^.V^.BlockCount then begin op^.Error:=eCorruptFilesystem; exit; end;
    for logical:=0 to count-1 do begin
        if not MapBlock(op,0,dir,logical,false,block) then exit;
        if block=0 then begin op^.Error:=eCorruptFilesystem; exit; end;
        if not ReadBlock(op,block,op^.Data) then exit;
        offset:=0;
        while offset<op^.V^.BlockSize do begin
            if not DirRecord(op,offset,op^.V^.BlockSize,d) then exit;
            if (d^.Inode<>0) and (d^.NameLength=length) then
                if SameName(pchar(uint32(d)+8),name,length) then begin number:=d^.Inode; Lookup:=true; exit; end;
            Inc(offset,d^.Length);
        end;
    end;
    op^.Error:=eFileDoesNotExist;
end;

function Resolve(op : PExt2Op; path : pchar; var number : uint32; var inode : TExt2Inode) : boolean;
var pos, start, block, offset, next : uint32;
begin
    Resolve:=false; number:=2;
    if not ReadInode(op,number,inode) then exit;
    if path=nil then begin op^.Error:=eInvalidPath; exit; end;
    pos:=0;
    while path[pos]<>char(0) do begin
        if pos>=4096 then begin op^.Error:=eInvalidPath; exit; end;
        if path[pos]='/' then begin Inc(pos); continue; end;
        start:=pos;
        while (path[pos]<>char(0)) and (path[pos]<>'/') and (pos-start<=255) do Inc(pos);
        if pos-start>255 then begin op^.Error:=eFilenameTooLong; exit; end;
        if not Lookup(op,inode,pchar(uint32(path)+start),pos-start,next,block,offset) then exit;
        number:=next;
        if not ReadInode(op,number,inode) then exit;
    end;
    Resolve:=true;
end;

function ValidName(op : PExt2Op; name : pchar; var length : uint32) : boolean;
begin
    ValidName:=false; length:=0;
    if name=nil then begin op^.Error:=eInvalidFileName; exit; end;
    while (length<=255) and (name[length]<>char(0)) do begin
        if name[length]='/' then begin op^.Error:=eInvalidFileName; exit; end;
        Inc(length);
    end;
    if length>255 then begin op^.Error:=eFilenameTooLong; exit; end;
    if (length=0) or ((length=1) and (name[0]='.')) or
       ((length=2) and (name[0]='.') and (name[1]='.')) then begin op^.Error:=eInvalidFileName; exit; end;
    ValidName:=true;
end;

function CanModify(op : PExt2Op; var inode : TExt2Inode) : boolean;
begin
    CanModify:=false;
    if (inode.Flags and ($10 or $20))<>0 then begin op^.Error:=ePermissionDenied; exit; end;
    CanModify:=true;
end;

procedure SetDirent(op : PExt2Op; offset, length, number : uint32; name : pchar; nameLength : uint32; isDir : boolean);
var d : PExt2Dirent;
begin
    d:=PExt2Dirent(uint32(op^.Data)+offset);
    memset(uint32(d),0,length);
    d^.Inode:=number; d^.Length:=length; d^.NameLength:=nameLength;
    if op^.V^.FileTypes then begin if isDir then d^.FileType:=2 else d^.FileType:=1; end;
    memcpy(uint32(name),uint32(d)+8,nameLength);
end;

function AddEntry(op : PExt2Op; parent : uint32; var dir : TExt2Inode; name : pchar; number : uint32; isDir : boolean) : boolean;
var logical, count, block, offset, used, need, length, space : uint32; d : PExt2Dirent;
begin
    AddEntry:=false;
    if not ValidName(op,name,length) then exit;
    need:=(8+length+3) and not uint32(3); count:=dir.Size div op^.V^.BlockSize;
    { Indexed directories can be read linearly. Drop INDEX before modifying the
      linear representation; old htree records remain unused directory space. }
    if (dir.Flags and $1000)<>0 then begin dir.Flags:=dir.Flags and not uint32($1000); if not WriteInode(op,parent,dir) then exit; end;
    logical:=0;
    while logical<count do begin
        if not MapBlock(op,parent,dir,logical,false,block) then exit;
        if block=0 then begin op^.Error:=eCorruptFilesystem; exit; end;
        if not ReadBlock(op,block,op^.Data) then exit;
        offset:=0;
        while offset<op^.V^.BlockSize do begin
            if not DirRecord(op,offset,op^.V^.BlockSize,d) then exit;
            if d^.Inode=0 then used:=0 else used:=(8+uint32(d^.NameLength)+3) and not uint32(3);
            space:=d^.Length-used;
            if space>=need then begin
                if used<>0 then d^.Length:=used;
                SetDirent(op,offset+used,space,number,name,length,isDir);
                AddEntry:=WriteBlock(op,block,op^.Data); exit;
            end;
            Inc(offset,d^.Length);
        end;
        Inc(logical);
    end;
    if dir.Size>$FFFFFFFF-op^.V^.BlockSize then begin op^.Error:=eDiskFull; exit; end;
    if not MapBlock(op,parent,dir,count,true,block) then exit;
    SetDirent(op,0,op^.V^.BlockSize,number,name,length,isDir);
    if not WriteBlock(op,block,op^.Data) then exit;
    Inc(dir.Size,op^.V^.BlockSize);
    AddEntry:=WriteInode(op,parent,dir);
end;

function CreateNode(op : PExt2Op; parent : uint32; name : pchar; isDir : boolean; var number : uint32) : boolean;
var dir, inode : TExt2Inode; length, existing, block, offset, g : uint32; d : PExt2Group;
begin
    CreateNode:=false; number:=0;
    if not ValidName(op,name,length) then exit;
    if not ReadInode(op,parent,dir) then exit;
    if not CanModify(op,dir) then exit;
    if Lookup(op,dir,name,length,existing,block,offset) then begin op^.Error:=eAlreadyExists; exit; end;
    if op^.Error<>eFileDoesNotExist then exit;
    op^.Error:=eNone;
    if isDir and (dir.Links=$FFFF) then begin op^.Error:=eDirectoryFull; exit; end;
    if not BeginMutation(op) then exit;
    if not Allocate(op,true,number) then exit;
    { Clear the full inode slot, including any extended inode fields. }
    if not InodeLocation(op,number,block,offset) then exit;
    if not ReadBlock(op,block,op^.Scratch) then exit;
    memset(uint32(op^.Scratch)+offset,0,op^.V^.InodeSize);
    if not WriteBlock(op,block,op^.Scratch) then exit;
    memset(uint32(@inode),0,sizeof(inode));
    inode.Mode:=EXT2_FILE or $1A4; inode.Links:=1;
    if isDir then begin inode.Mode:=EXT2_DIR or $1ED; inode.Links:=2; end;
    if not WriteInode(op,number,inode) then exit;
    if isDir then begin
        if not MapBlock(op,number,inode,0,true,block) then exit;
        SetDirent(op,0,12,number,'.',1,true);
        SetDirent(op,12,op^.V^.BlockSize-12,parent,'..',2,true);
        if not WriteBlock(op,block,op^.Data) then exit;
        inode.Size:=op^.V^.BlockSize;
        if not WriteInode(op,number,inode) then exit;
        g:=(number-1) div op^.V^.InodesPerGroup; d:=GroupDesc(op^.V,g); Inc(d^.Directories);
        if not SaveGroup(op,g) then exit;
        Inc(dir.Links);
        if not WriteInode(op,parent,dir) then exit;
    end;
    if not AddEntry(op,parent,dir,name,number,isDir) then exit;
    CreateNode:=true;
end;

function ParentPath(op : PExt2Op; path : pchar; var parent : uint32; var name : pchar; var inode : TExt2Inode) : boolean;
var length, split, i : uint32; copyPath : pchar;
begin
    ParentPath:=false; name:=nil;
    if path=nil then begin op^.Error:=eInvalidPath; exit; end;
    length:=0;
    while (length<4096) and (path[length]<>char(0)) do Inc(length);
    if (length=0) or (length=4096) then begin op^.Error:=eInvalidPath; exit; end;
    split:=0;
    for i:=0 to length-1 do if path[i]='/' then split:=i+1;
    name:=pchar(uint32(path)+split);
    if not ValidName(op,name,i) then exit;
    copyPath:=pchar(kalloc(split+1));
    if copyPath=nil then begin op^.Error:=eOutOfMemory; exit; end;
    memcpy(uint32(path),uint32(copyPath),split); copyPath[split]:=char(0);
    ParentPath:=Resolve(op,copyPath,parent,inode);
    kfree(void(copyPath));
end;

function FreeTree(op : PExt2Op; block, level : uint32; var budget : uint32) : boolean;
var data : puint32; i, child : uint32;
begin
    FreeTree:=false;
    if block=0 then begin FreeTree:=true; exit; end;
    if (budget=0) or not DataBlock(op^.V,block) then begin op^.Error:=eCorruptFilesystem; exit; end;
    Dec(budget);
    if level>0 then begin
        data:=puint32(kalloc(op^.V^.BlockSize));
        if data=nil then begin op^.Error:=eOutOfMemory; exit; end;
        if not ReadBlock(op,block,data) then begin kfree(data); exit; end;
        for i:=0 to op^.V^.BlockSize div 4-1 do begin
            child:=data[i];
            if not FreeTree(op,child,level-1,budget) then begin kfree(data); exit; end;
        end;
        kfree(data);
    end;
    FreeTree:=FreeNumber(op,block,false);
end;

function EmptyDirectory(op : PExt2Op; var inode : TExt2Inode) : boolean;
var logical, block, offset : uint32; d : PExt2Dirent; name : pchar;
begin
    EmptyDirectory:=false;
    if (inode.Size=0) or (inode.Size mod op^.V^.BlockSize<>0) or
       (inode.Size div op^.V^.BlockSize>op^.V^.BlockCount) then begin op^.Error:=eCorruptFilesystem; exit; end;
    for logical:=0 to inode.Size div op^.V^.BlockSize-1 do begin
        if not MapBlock(op,0,inode,logical,false,block) then exit;
        if block=0 then begin op^.Error:=eCorruptFilesystem; exit; end;
        if not ReadBlock(op,block,op^.Data) then exit;
        offset:=0;
        while offset<op^.V^.BlockSize do begin
            if not DirRecord(op,offset,op^.V^.BlockSize,d) then exit;
            name:=pchar(uint32(d)+8);
            if d^.Inode<>0 then
                if not (((d^.NameLength=1) and (name[0]='.')) or
                        ((d^.NameLength=2) and (name[0]='.') and (name[1]='.'))) then begin op^.Error:=eDirectoryNotEmpty; exit; end;
            Inc(offset,d^.Length);
        end;
    end;
    EmptyDirectory:=true;
end;

function RemoveNode(op : PExt2Op; path : pchar; isDir : boolean) : boolean;
var parent, number, block, offset, i, budget, g : uint32; name : pchar;
    dir, inode : TExt2Inode; f : PExt2File; d : PExt2Group;
begin
    RemoveNode:=false;
    if not ParentPath(op,path,parent,name,dir) then exit;
    if not Lookup(op,dir,name,stringSize(name),number,block,offset) then exit;
    if number<11 then begin op^.Error:=ePermissionDenied; exit; end;
    if not ReadInode(op,number,inode) then exit;
    if isDir then begin
        if (inode.Mode and $F000)<>EXT2_DIR then begin op^.Error:=eNotADirectory; exit; end;
        if not EmptyDirectory(op,inode) then exit;
    end else if (inode.Mode and $F000)<>EXT2_FILE then begin op^.Error:=eNotSupported; exit; end;
    if (inode.ACL<>0) then begin op^.Error:=eNotSupported; exit; end;
    if not CanModify(op,dir) or not CanModify(op,inode) then exit;
    f:=op^.V^.Files;
    while f<>nil do begin
        if f^.Inode=number then begin op^.Error:=eFileInUse; exit; end;
        f:=f^.Next;
    end;
    if not BeginMutation(op) then exit;
    dir.Flags:=dir.Flags and not uint32($1000);
    if isDir then begin
        if dir.Links<2 then begin op^.Error:=eCorruptFilesystem; exit; end;
        Dec(dir.Links);
    end;
    if not WriteInode(op,parent,dir) then exit;
    if not ReadBlock(op,block,op^.Data) then exit;
    Put32(op^.Data,offset,0);
    if not WriteBlock(op,block,op^.Data) then exit;
    if isDir then inode.Links:=0 else Dec(inode.Links);
    if inode.Links=0 then begin
        budget:=op^.V^.BlockCount;
        for i:=0 to 14 do begin
            g:=0; if i>=12 then g:=i-11;
            if not FreeTree(op,inode.Blocks[i],g,budget) then exit;
            inode.Blocks[i]:=0;
        end;
        inode.Size:=0; inode.Sectors:=0; inode.DTime:=1;
        if not WriteInode(op,number,inode) then exit;
        if not FreeNumber(op,number,true) then exit;
        if isDir then begin
            g:=(number-1) div op^.V^.InodesPerGroup; d:=GroupDesc(op^.V,g);
            if d^.Directories=0 then begin op^.Error:=eCorruptFilesystem; exit; end;
            Dec(d^.Directories); if not SaveGroup(op,g) then exit;
        end;
    end else if not WriteInode(op,number,inode) then exit;
    RemoveNode:=FinishMutation(op);
end;

function RenameNode(op : PExt2Op; path, newName : pchar) : boolean;
var parent, number, oldBlock, oldOffset, other, block, offset, length : uint32;
    name : pchar; dir, inode : TExt2Inode;
begin
    RenameNode:=false;
    if not ValidName(op,newName,length) then exit;
    if not ParentPath(op,path,parent,name,dir) then exit;
    if not Lookup(op,dir,name,stringSize(name),number,oldBlock,oldOffset) then exit;
    if stringEquals(name,newName) then begin RenameNode:=true; exit; end;
    if Lookup(op,dir,newName,length,other,block,offset) then begin op^.Error:=eAlreadyExists; exit; end;
    if op^.Error<>eFileDoesNotExist then exit;
    op^.Error:=eNone;
    if not ReadInode(op,number,inode) then exit;
    if not CanModify(op,dir) or not CanModify(op,inode) then exit;
    if ((inode.Mode and $F000)<>EXT2_FILE) and ((inode.Mode and $F000)<>EXT2_DIR) then begin op^.Error:=eNotSupported; exit; end;
    if not BeginMutation(op) then exit;
    if not AddEntry(op,parent,dir,newName,number,(inode.Mode and $F000)=EXT2_DIR) then exit;
    if not ReadBlock(op,oldBlock,op^.Data) then exit;
    Put32(op^.Data,oldOffset,0);
    if not WriteBlock(op,oldBlock,op^.Data) then exit;
    RenameNode:=FinishMutation(op);
end;

procedure FreeEntries(entries : PLinkedListBase);
var node : PLinkedList; e : PDirectory_Entry;
begin
    if entries=nil then exit;
    node:=entries^.Head;
    while node<>nil do begin
        e:=PDirectory_Entry(node^.Data);
        if e^.fileName<>nil then kfree(void(e^.fileName));
        node:=node^.Next;
    end;
    LL_Free(entries);
end;

function ReadDirectory(volume : PStorage_Volume; directory : pchar; status : puint32) : PLinkedListBase;
var op : PExt2Op; list : PLinkedListBase; tail, node : PLinkedList;
    dir, inode : TExt2Inode; number, logical, block, offset, length : uint32;
    d : PExt2Dirent; e : PDirectory_Entry;
begin
    ReadDirectory:=nil; if status<>nil then status^:=ord(eOutOfMemory);
    op:=BeginOp(volume); if op=nil then exit;
    list:=nil; tail:=nil;
    if Resolve(op,directory,number,dir) then begin
        if (dir.Mode and $F000)<>EXT2_DIR then op^.Error:=eNotADirectory
        else if (dir.Size=0) or (dir.Size mod op^.V^.BlockSize<>0) or
                (dir.Size div op^.V^.BlockSize>op^.V^.BlockCount) then op^.Error:=eCorruptFilesystem
        else begin
            list:=PLinkedListBase(kalloc(sizeof(TLinkedListBase)));
            if list=nil then op^.Error:=eOutOfMemory else begin
                memset(uint32(list),0,sizeof(TLinkedListBase)); list^.ElementSize:=sizeof(TDirectory_Entry);
                for logical:=0 to dir.Size div op^.V^.BlockSize-1 do begin
                    if not MapBlock(op,number,dir,logical,false,block) then break;
                    if block=0 then begin op^.Error:=eCorruptFilesystem; break; end;
                    if not ReadBlock(op,block,op^.Data) then break;
                    offset:=0;
                    while offset<op^.V^.BlockSize do begin
                        if not DirRecord(op,offset,op^.V^.BlockSize,d) then break;
                        length:=d^.Length;
                        if d^.Inode<>0 then begin
                            if not ReadInode(op,d^.Inode,inode) then break;
                            if ((inode.Mode and $F000)=EXT2_FILE) or ((inode.Mode and $F000)=EXT2_DIR) then begin
                                node:=PLinkedList(kalloc(sizeof(TLinkedList)));
                                e:=PDirectory_Entry(kalloc(sizeof(TDirectory_Entry)));
                                if (node=nil) or (e=nil) then begin
                                    if node<>nil then kfree(void(node)); if e<>nil then kfree(void(e));
                                    op^.Error:=eOutOfMemory; break;
                                end;
                                memset(uint32(e),0,sizeof(TDirectory_Entry));
                                e^.fileName:=pchar(kalloc(uint32(d^.NameLength)+1));
                                if e^.fileName=nil then begin kfree(void(node)); kfree(void(e)); op^.Error:=eOutOfMemory; break; end;
                                memcpy(uint32(d)+8,uint32(e^.fileName),d^.NameLength); e^.fileName[d^.NameLength]:=char(0);
                                e^.fileSize:=inode.Size;
                                if (inode.Mode and $F000)=EXT2_DIR then e^.entryType:=directoryEntry else e^.entryType:=fileEntry;
                                node^.Data:=void(e); node^.Next:=nil; node^.Previous:=tail;
                                if tail=nil then list^.Head:=node else tail^.Next:=node;
                                tail:=node; Inc(list^.Count);
                            end;
                        end;
                        Inc(offset,length);
                    end;
                    if op^.Error<>eNone then break;
                end;
            end;
        end;
    end;
    if status<>nil then status^:=ord(op^.Error);
    if op^.Error=eNone then ReadDirectory:=list else FreeEntries(list);
    EndOp(op);
end;

function OpenFile(volume : PStorage_Volume; directory, name : pchar;
                  allowCreate : boolean; var size : uint32) : pointer;
var op : PExt2Op; inode : TExt2Inode; parent, number, block, offset, length : uint32; f : PExt2File;
begin
    OpenFile:=nil; size:=0; op:=BeginOp(volume); if op=nil then exit;
    if ValidName(op,name,length) and Resolve(op,directory,parent,inode) then begin
        if not Lookup(op,inode,name,length,number,block,offset) then begin
            if allowCreate and (op^.Error=eFileDoesNotExist) then begin
                op^.Error:=eNone;
                if CreateNode(op,parent,name,false,number) then FinishMutation(op);
            end;
        end;
        if op^.Error=eNone then
            if ReadInode(op,number,inode) then
                if (inode.Mode and $F000)=EXT2_FILE then begin
                    f:=PExt2File(kalloc(sizeof(TExt2File)));
                    if f<>nil then begin
                        f^.Volume:=op^.V; f^.Inode:=number; f^.Next:=op^.V^.Files; op^.V^.Files:=f;
                        size:=inode.Size; OpenFile:=f;
                    end;
                end;
    end;
    EndOp(op);
end;

procedure CloseFile(ctx : pointer);
var f, cur, prev : PExt2File; op : PExt2Op;
begin
    f:=PExt2File(ctx); if f=nil then exit;
    op:=BeginOp(f^.Volume^.Volume); if op=nil then exit;
    prev:=nil; cur:=op^.V^.Files;
    while cur<>nil do begin
        if cur=f then begin
            if prev=nil then op^.V^.Files:=cur^.Next else prev^.Next:=cur^.Next;
            kfree(void(cur)); break;
        end;
        prev:=cur; cur:=cur^.Next;
    end;
    EndOp(op);
end;

function Transfer(volume : PStorage_Volume; fileCtx : PExt2File; offset : uint32;
                  buffer : puint32; count : uint32; writing : boolean; var error : TError) : uint32;
var op : PExt2Op; inode : TExt2Inode; done, block, within, amount, limit, oldSize : uint32;
begin
    Transfer:=0; error:=eInvalidArgument;
    if (fileCtx=nil) or ((buffer=nil) and (count<>0)) then exit;
    if fileCtx^.Volume^.Volume<>volume then exit;
    if count>$FFFFFFFF-offset then exit;
    op:=BeginOp(volume); if op=nil then begin error:=eOutOfMemory; exit; end;
    done:=0;
    if ReadInode(op,fileCtx^.Inode,inode) then begin
        limit:=count; oldSize:=inode.Size;
        if writing then begin
            if not CanModify(op,inode) then limit:=0;
            if (limit>0) and not BeginMutation(op) then limit:=0;
            { Existing tail bytes must not become visible when a write leaves
              a sparse gap within the former last data block. }
            if (limit>0) and (offset>oldSize) and (oldSize mod op^.V^.BlockSize<>0) then begin
                if MapBlock(op,fileCtx^.Inode,inode,oldSize div op^.V^.BlockSize,false,block) then
                    if block<>0 then
                        if ReadBlock(op,block,op^.Data) then begin
                            within:=oldSize mod op^.V^.BlockSize;
                            memset(uint32(op^.Data)+within,0,op^.V^.BlockSize-within);
                            WriteBlock(op,block,op^.Data);
                        end;
            end;
        end else begin
            if offset>=inode.Size then limit:=0 else if limit>inode.Size-offset then limit:=inode.Size-offset;
        end;
        while (done<limit) and (op^.Error=eNone) do begin
            within:=(offset+done) mod op^.V^.BlockSize;
            amount:=op^.V^.BlockSize-within; if amount>limit-done then amount:=limit-done;
            if not MapBlock(op,fileCtx^.Inode,inode,(offset+done) div op^.V^.BlockSize,writing,block) then break;
            if block=0 then memset(uint32(op^.Data),0,op^.V^.BlockSize)
            else if (not writing) or (within<>0) or (amount<>op^.V^.BlockSize) then
                if not ReadBlock(op,block,op^.Data) then break;
            if writing then begin
                memcpy(uint32(buffer)+done,uint32(op^.Data)+within,amount);
                if not WriteBlock(op,block,op^.Data) then break;
                if offset+done+amount>inode.Size then inode.Size:=offset+done+amount;
                if not WriteInode(op,fileCtx^.Inode,inode) then break;
            end else memcpy(uint32(op^.Data)+within,uint32(buffer)+done,amount);
            Inc(done,amount);
        end;
        if writing and op^.Mutating and (op^.Error=eNone) then FinishMutation(op);
    end;
    error:=op^.Error; Transfer:=done; EndOp(op);
end;

end.
