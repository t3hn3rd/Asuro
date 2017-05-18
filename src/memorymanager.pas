unit memorymanager;

interface

uses
    util;

const
    ALLOC_SPACE = 8; //64-Bit Allocations 
    MAX_ENTRIES = $FFFF;

procedure init;
function kalloc(size : uint32) : void;
procedure kfree(area : void);

implementation

var
    Memory_Start   : uint32;
    Memory_Manager : bitpacked array[1..MAX_ENTRIES] of Boolean;

procedure init;
begin
    Memory_Start:= uint32(@util.endptr);
end;

function kalloc(size : uint32) : void;
begin
    kalloc:= void(0);
end;

procedure kfree(area : void);
begin

end;

end.