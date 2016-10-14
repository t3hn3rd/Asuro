unit util;

interface

function util_hi(b : byte) : byte;
function util_lo(b : byte) : byte;
function util_switchendian(b : byte) : byte;

implementation

function util_hi(b : byte) : byte; [public, alias: 'util_hi'];
begin
     util_hi:= (b AND $F0) SHR 4;
end;

function util_lo(b : byte) : byte; [public, alias: 'util_lo'];
begin
     util_lo:= b AND $0F;
end;

function util_switchendian(b : byte) : byte; [public, alias: 'util_switchendian'];
begin
     util_switchendian:= (util_lo(b) SHL 4) OR util_hi(b);
end;

end.
