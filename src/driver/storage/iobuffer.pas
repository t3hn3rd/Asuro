{
    Driver->Storage->IOBuffer - Safe IO buffer allocation helpers.

    Provides correct-size buffer allocation tied to a volume's sector
    geometry so that callers never have to compute sizes by hand.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit iobuffer;

interface

uses
    lmemorymanager,
    storagetypes,
    tracer;

{ Allocate a buffer of at least `size` bytes.
  Returns a pointer to the allocated buffer, or nil on failure. }
function AllocateIOBuffer(volume : PStorage_Volume; size : uint32) : puint32;

{ Free a buffer previously allocated by AllocateIOBuffer.
  Returns true if the buffer was freed successfully. }
function FreeIOBuffer(buf : puint32) : boolean;

implementation

function AllocateIOBuffer(volume : PStorage_Volume; size : uint32) : puint32;
var
    sectorSize  : uint32;
    alignedSize : uint32;
    buf         : puint32;
begin
    tracer.push_trace('iobuffer.AllocateIOBuffer');
    AllocateIOBuffer := nil;

    if volume = nil then exit;
    if size = 0 then exit;

    { Round up to a whole number of sectors so DMA / block I/O is safe }
    sectorSize := volume^.device^.sectorSize;
    if sectorSize = 0 then
        sectorSize := 512; 

    alignedSize := ((size + sectorSize - 1) div sectorSize) * sectorSize;

    buf := puint32(kalloc(alignedSize));
    if buf = nil then exit;

    AllocateIOBuffer := buf;
end;

function FreeIOBuffer(buf : puint32) : boolean;
begin
    tracer.push_trace('iobuffer.FreeIOBuffer');
    FreeIOBuffer := false;

    if buf = nil then exit;

    kfree(void(buf));
    FreeIOBuffer := true;
end;

end.
