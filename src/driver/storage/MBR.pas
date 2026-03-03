{
    Driver->Storage->MBR Master boot record 

    @author(Aaron Hance ah@aaronhance.me)
}
unit mbr;

interface

uses
    tracer;

type

    PMaster_Boot_Record = ^TMaster_Boot_Record;
    PPartition_table = ^TPartition_table;

    TPartition_table = bitpacked record 
        attributes     : uint8;
        CHS_start      : array[0..2] of uint8;
        system_id      : uint8;
        CHS_end        : array[0..2] of uint8;
        LBA_start      : uInt32;
        sector_count   : uInt32;
    end;

    TMaster_Boot_Record = bitpacked record 
        bootstrap   : array[0..439] of uint8;
        signature   : uint32;
        rsv         : uint16;
        partition   : array[0..3] of TPartition_table;
        boot_sector : uint16;
    end;

    T24bit = array[0..2] of uint8;

    function get_bootable(partition_table : PPartition_table) : boolean;
    procedure set_bootable(partition_table : PPartition_table);
    procedure setup_partition(partition_table : PPartition_table; address : uint32; sectorSize : uint32);

implementation

{ convert LBA address to CHS address}
function LBA_2_CHS(lba : uint32) : T24bit;
var
    dat : T24bit;
    cylinder, head, sector : uint16;
    sectors_per_track : uint16;
    heads_per_cylinder : uint16;
begin
    // Standard CHS geometry values
    sectors_per_track := 63;
    heads_per_cylinder := 255;
    
    // Calculate CHS values from LBA
    sector := (lba mod sectors_per_track) + 1;  // Sectors are 1-indexed
    head := (lba div sectors_per_track) mod heads_per_cylinder;
    cylinder := (lba div sectors_per_track) div heads_per_cylinder;
    
    // Pack into MBR CHS format (3 bytes):
    // Byte 0: Head (8 bits)
    // Byte 1: Sector (bits 0-5) | Cylinder high 2 bits (bits 6-7)
    // Byte 2: Cylinder low 8 bits
    dat[0] := head;
    dat[1] := (sector and $3F) or ((cylinder shr 8) shl 6);
    dat[2] := (cylinder and $FF);
    
    LBA_2_CHS := dat;
end;

{ Set a partition struct to be bootable}
procedure set_bootable(partition_table : PPartition_table);
begin
    push_trace('MBR.set_bootable');
    //set the bootble bit in attributes
    partition_table^.attributes := (partition_table^.attributes and $80);
end;

{ Check a partitions bootable bit }
function get_bootable(partition_table : PPartition_table) : boolean;
begin
    push_trace('MBR.get_bootable');
    //get the bootble bit in attributes
    get_bootable := (partition_table^.attributes and $80) = $80;
end;

{ Setup a partition table struct }
procedure setup_partition(partition_table : PPartition_table; address : uint32; sectorSize : uint32);
begin
    push_trace('MBR.setup_partition');
    //set values in both LBA and CHS addressing schemes
    partition_table^.LBA_start := address;
    partition_table^.sector_count := sectorSize;
    partition_table^.CHS_start := LBA_2_CHS(address);
    partition_table^.CHS_start := LBA_2_CHS(address + sectorSize);  
    push_trace('MBR.setup_partition.end');
end;


end.