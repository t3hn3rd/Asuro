//  Copyright 2021 Aaron Hance
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
{
    Driver->Storage->IOBuffer - Safe IO buffer allocation helpers.

    Provides correct-size buffer allocation tied to a volume's sector
    geometry so that callers never have to compute sizes by hand.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit driver.storage.iobuffer;

interface

uses
    memory.heap,
    driver.storage.types,
    debug.tracer;

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
    debug.tracer.push_trace('driver.storage.iobuffer.AllocateIOBuffer');
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
    debug.tracer.push_trace('driver.storage.iobuffer.FreeIOBuffer');
    FreeIOBuffer := false;

    if buf = nil then exit;

    kfree(void(buf));
    FreeIOBuffer := true;
end;

end.
