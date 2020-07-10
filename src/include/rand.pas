unit rand;

interface

function rand32 : uint32;
function rand16 : uint16;
function rand8  : uint8;
procedure srand(seed : uint32);

implementation

var
    next : uint32 = 1;

function rand : uint32;
begin
    next:= next * 1103515245 + 12345;
    rand:= (next div 65536) mod 32768;    
end;

function rand32 : uint32;
begin
    rand32:= (rand SHL 16) AND rand;
end;

function rand16 : uint16;
begin
    rand16:= rand32 AND $FFFF;
end;

function rand8 : uint8;
begin
    rand8:= rand32 AND $FF;
end;

procedure srand(seed : uint32);
begin
    next:= seed;
end;

end.