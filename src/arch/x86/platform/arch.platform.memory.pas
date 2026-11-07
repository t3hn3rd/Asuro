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

{ Mapping policy extracted from memory.heap (Kieron Morris). }
unit arch.platform.memory;
interface
const MAX_HEAP_REGIONS = 256;
{$i ../../common/platform.memory.inc}
implementation
uses arch.x86.memory.virtual, arch.x86.memory.physical, arch.platform.diagnostics;
function allocateHeapPage: PtrUInt;
var i: uint32;
begin
    allocateHeapPage := 0;
    i := KERNEL_PAGE_NUMBER + 4;
    while i < 1024 do begin
        if arch.x86.memory.virtual.new_page(i) then begin
            allocateHeapPage := i shl 22; exit;
        end;
        inc(i);
    end;
end;
function allocateLarge(pages: uint32): PtrUInt;
var curr_page, i: uint16; miss: boolean;
begin
    allocateLarge := 0;
    if (pages = 0) or (pages > MAX_HEAP_REGIONS) then exit;
    curr_page := 5;
    while uint32(curr_page) + pages - 1 < KERNEL_PAGE_NUMBER do begin
        miss := false;
        for i := 0 to pages - 1 do begin
            if not page_mappable(curr_page + i) then begin
                miss := true; curr_page := curr_page + i; break;
            end;
        end;
        if not miss then begin
            i := 0;
            while i < pages do begin
                if not arch.x86.memory.virtual.new_page(curr_page + i) then begin
                    while i > 0 do begin
                        dec(i); arch.x86.memory.virtual.free_page(curr_page + i);
                    end;
                    exit;
                end;
                inc(i);
            end;
            allocateLarge := uint32(curr_page) shl 22;
            exit;
        end;
        inc(curr_page);
    end;
end;
procedure release(address: PtrUInt; pages: uint32);
var i: uint32; page_num: uint16;
begin
    if (pages = 0) or (pages > MAX_HEAP_REGIONS) then begin
        fatal('LMM', 'Invalid heap region release'); exit;
    end;
    page_num := address shr 22;
    for i := 0 to pages - 1 do arch.x86.memory.virtual.free_page(page_num + uint16(i));
end;
function identityReserve(address: PtrUInt): pointer;
var block: uint16;
begin
    block := address shr 22;
    force_alloc_block(block, 0);
    map_page(block, block);
    identityReserve := pointer(uint32(block) shl 22);
end;
function freeBacking: uint64;
begin freeBacking := pmm_free_blocks; end;
end.
