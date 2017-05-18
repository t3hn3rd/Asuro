unit memorymanager;

interface

uses
    util,
    console;

const
    ALLOC_SPACE = 8; //64-Bit Allocations 
    MAX_ENTRIES = $FFFF;

procedure init;
function kalloc(size : uint32) : void;
procedure kfree(area : void);

implementation

var
    Memory_Start   : uint32;
    Memory_Manager : packed array[1..MAX_ENTRIES] of Boolean;

procedure init;
var
    i : uint32;

begin
    For i:=0 to MAX_ENTRIES-1 do begin
        Memory_Manager[i]:= false;
    end;
    Memory_Start:= uint32(@util.endptr);
end;

function kalloc(size : uint32) : void;
var
    blocks : uint32;
    rem    : uint32;
    i,j    : uint32;
    miss   : boolean;

begin
    blocks:= size div 8;
    rem:= size - (blocks * 8);
    if rem > 0 then blocks:= blocks + 1;
    kalloc:= nil;
    for i:=0 to MAX_ENTRIES-1 do begin
        miss:= false;
        for j:=0 to blocks-1 do begin
            if Memory_Manager[i+j] then miss:= true;
        end;
        if not miss then begin
            kalloc:= void(Memory_Start+(i * 8));
            for j:=0 to blocks-1 do begin
                Memory_Manager[i+j]:= true;
            end;
            console.writestring('Allocated ');
            console.writeint(blocks);
            console.writestringln(' Block(s).');
            break;
        end;
    end;
end;

procedure kfree(area : void);
begin

end;

end.