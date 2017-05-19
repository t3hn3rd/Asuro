unit pmemorymanager;

interface

uses
    util,
    console;

type
    TPhysicalMemoryEntry = packed record
        Present  : Boolean;
        MappedTo : uint32; 
    end;
    TPhysicalMemory = array[0..1023] of TPhysicalMemoryEntry;

procedure init;
function newblock(caller : uint32) : uint16;
procedure freeblock(block : uint16; caller : uint32);

implementation

var
    PhysicalMemory: TPhysicalMemory;

procedure init;
begin
    with PhysicalMemory[0] do begin
        Present:= True;
        MappedTo:= 0;
    end;
    with PhysicalMemory[1] do begin
        Present:= True;
        MappedTo:= 0;
    end;
end;

function newblock(caller : uint32) : uint16;
var
    i : uint16;

begin
    newblock:= 0;
    for i:=2 to 1023 do begin
        if not PhysicalMemory[i].Present then begin
            PhysicalMemory[i].Present:= True;
            PhysicalMemory[i].MappedTo:= caller;
            newblock:= i;
            exit;
        end;
    end; 
end;

procedure freeblock(block : uint16; caller : uint32);
begin
    if block > 1023 then begin
        GPF;
        exit;
    end;
    if block < 2 then begin
        GPF;
        exit;
    end;
    if PhysicalMemory[block].caller <> caller then begin
        GPF;
        exit;
    end;
    PhysicalMemory[block].Present:= false;
end;

end.