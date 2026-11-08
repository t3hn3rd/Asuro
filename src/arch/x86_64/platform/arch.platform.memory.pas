// Copyright 2026 Aaron Hance
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

unit arch.platform.memory;

interface
uses arch.x86_64.memory.virtual;
const MAX_HEAP_REGIONS = arch.x86_64.memory.virtual.ARENA_COUNT;
{$i ../../common/platform.memory.inc}

implementation
uses arch.x86_64.memory.physical, arch.platform.diagnostics;

function allocateHeapPage: PtrUInt;
begin
    allocateHeapPage := allocate_region(1);
end;

function allocateLarge(pages: uint32): PtrUInt;
begin
    allocateLarge := allocate_region(pages);
end;

procedure release(address: PtrUInt; pages: uint32);
begin
    if not release_region(address, pages) then fatal('LMM', 'Invalid heap region release');
end;

function identityReserve(address: PtrUInt): pointer;
begin
    identityReserve := nil;
    if address < uint64($100000000) then begin
        address := (address shr 22) shl 22;
        if reserve_range(address, $400000) then identityReserve := pointer(address);
    end;
end;

function freePhysicalBytes: uint64;
begin
    freePhysicalBytes := free_count * FRAME_SIZE;
end;

function totalPhysicalBytes: uint64;
begin
    totalPhysicalBytes := total_count * FRAME_SIZE;
end;
function physicalAddress(address: PtrUInt): uint64;
begin
    physicalAddress := arch.x86_64.memory.virtual.translate(address);
end;

function mapDevice(address: uint64; bytes: SizeUInt): pointer;
begin
    mapDevice := arch.x86_64.memory.virtual.mapDevice(address, bytes);
end;

end.
