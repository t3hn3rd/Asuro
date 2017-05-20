unit pmemorymanager;

interface

uses
    util,
    console,
    multiboot;

type
    TPhysicalMemoryEntry = packed record
        Scanned   : Boolean;
        Present   : Boolean;
        Allocated : Boolean;
        MappedTo  : uint32; 
    end;
    TPhysicalMemory = array[0..1023] of TPhysicalMemoryEntry;

procedure init;
function alloc_block(block : uint16; caller : uint32) : boolean;
function new_block(caller : uint32) : uint16;
procedure free_block(block : uint16; caller : uint32);

implementation

var
    PhysicalMemory : TPhysicalMemory;
    nPresent       : uint32;

procedure set_memory_area_present(base : uint64; length : uint64; present : boolean);
var
   FirstBlock : uint32;
   LastBlock  : uint32;
   i          : uint32;

begin
    FirstBlock:= base SHR 22;
    LastBlock:= (base+length) SHR 22;
    console.writewordln(FirstBlock);
    console.writewordln(LastBlock);
    if (FirstBlock > 1023) then exit;
    while LastBlock > 1023 do begin
        LastBlock:= LastBlock-1;
    end;
    for i:=FirstBlock to LastBlock do begin
        if not present then begin
            PhysicalMemory[i].Scanned:= True;
            PhysicalMemory[i].Present:= present;
        end else begin
            If not PhysicalMemory[i].Scanned then begin
                PhysicalMemory[i].Scanned:= True;
                PhysicalMemory[i].Present:= present;
            end;
        end;
    end;
end;

procedure walk_memory_map;
var
  mmap    : Pmemory_map_t;
  address : uint32;
  length  : uint32;
  i       : uint16;

begin
    address:= multibootinfo^.mmap_addr + KERNEL_VIRTUAL_BASE;
    length:= multibootinfo^.mmap_length;
    mmap:= Pmemory_map_t(address);
    for i:=0 to 1023 do begin
        PhysicalMemory[i].Present:= False;
        PhysicalMemory[i].Allocated:= False;
        PhysicalMemory[i].Scanned:= False;
        PhysicalMemory[i].MappedTo:= 0;
    end;
	while uint32(mmap) < (address + length) do begin
        console.writehexln(mmap^.base_addr);
        console.writehexln(mmap^.length);
        console.writehexln(mmap^.mtype);
        console.writestringln('');
        if mmap^.mtype <> $01 then begin
            set_memory_area_present(mmap^.base_addr, mmap^.length, False);
        end else begin
            set_memory_area_present(mmap^.base_addr, mmap^.length, True);
        end;
        mmap:= Pmemory_map_t(uint32(mmap)+mmap^.size+sizeof(mmap^.size));
    end;
    nPresent:= 0;
    for i:=0 to 1023 do begin
        if PhysicalMemory[i].Present then nPresent:= nPresent + 1;
    end;
end;

procedure force_alloc_block(block : uint16; caller : uint32);
begin
    PhysicalMemory[block].Allocated:= True;
    PhysicalMemory[block].MappedTo:= caller;
    console.writestring('PMM: 4MiB Block Force Allocated @ ');
    console.writeword(block);
    console.writestring(' [');
    console.writehex(block SHL 22);
    console.writestring(' - ');
    console.writehex(((block+1) SHL 22));
    console.writestringln(']');
end;

procedure init;
begin
    console.writestringln('PMM: INIT BEGIN.');
    walk_memory_map;
    force_alloc_block(0, 0);
    force_alloc_block(1, 0);
    alloc_block(2, 0); //First 12MiB reserved for Kernel/BIOS.
    console.writestring('PMM: ');
    console.writeword(nPresent);
    console.writestringln('/1024 Block Available for Allocation.');
    console.writestringln('PMM: INIT END.');
end;

function alloc_block(block : uint16; caller : uint32) : boolean;
begin
    alloc_block:= false;
    if (PhysicalMemory[block].Present) then begin
        if PhysicalMemory[block].Allocated then begin
            alloc_block:= false;
        end else begin
            PhysicalMemory[block].Allocated:= True;
            PhysicalMemory[block].MappedTo:= caller;
            console.writestring('PMM: 4MiB Block Allocated @ ');
            console.writeword(block);
            console.writestring(' [');
            console.writehex(block SHL 22);
            console.writestring(' - ');
            console.writehex(((block+1) SHL 22));
            console.writestringln(']');
            alloc_block:= true;
        end;
    end else begin
        GPF;
        alloc_block:= false;
    end;
end;

function new_block(caller : uint32) : uint16;
var
    i : uint16;

begin
    new_block:= 0;
    for i:=2 to 1023 do begin
        if PhysicalMemory[i].Present then begin
            if not PhysicalMemory[i].Allocated then begin
                if alloc_block(i, caller) then begin
                    new_block:= i;
                    exit;
                end;
            end;
        end;
    end; 
end;

procedure free_block(block : uint16; caller : uint32);
begin
    if block > 1023 then begin
        GPF;
        exit;
    end;
    if block < 2 then begin
        GPF;
        exit;
    end;
    if not PhysicalMemory[block].Present then begin
        GPF;
        exit;
    end;
    if PhysicalMemory[block].MappedTo <> caller then begin
        GPF;
        exit;
    end;
    PhysicalMemory[block].Allocated:= false;
end;

end.