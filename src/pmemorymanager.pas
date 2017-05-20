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
function new_block(caller : uint32) : uint16;
procedure free_block(block : uint16; caller : uint32);

implementation

var
    PhysicalMemory: TPhysicalMemory;

procedure init;
begin
    console.writestringln('PMM: INIT BEGIN.');
    with PhysicalMemory[0] do begin
        Present:= True;
        MappedTo:= 0;
    end;
    with PhysicalMemory[1] do begin
        Present:= True;
        MappedTo:= 0;
    end;
    with PhysicalMemory[2] do begin
        Present:= True;
        MappedTo:= 0;
    end;
    console.writestringln('PMM: INIT END.');
end;

function new_block(caller : uint32) : uint16;
var
    i : uint16;

begin
    new_block:= 0;
    for i:=2 to 1023 do begin
        if not PhysicalMemory[i].Present then begin
            PhysicalMemory[i].Present:= True;
            PhysicalMemory[i].MappedTo:= caller;
            new_block:= i;
            console.writestring('4MiB Block Added @ ');
            console.writeword(i);
            console.writestring(' [');
            console.writehex(i SHL 22);
            console.writestring(' - ');
            console.writehex(((i+1) SHL 22));
            console.writestringln(']');
            exit;
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
    if PhysicalMemory[block].MappedTo <> caller then begin
        GPF;
        exit;
    end;
    PhysicalMemory[block].Present:= false;
end;

end.