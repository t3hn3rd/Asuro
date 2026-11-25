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

unit driver.dma;

interface
type
    TDMAReach = (dmaInvalid, dmaDirect, dmaHigh);
function reach32(address: PtrUInt; bytes: uint32): TDMAReach;
function allocate(bytes, alignment: uint32; lowOnly: boolean): pointer;
function allocateBounce(bytes: uint32): pointer;
procedure release(buffer: pointer);

implementation
uses memory.heap, arch.platform.memory, core.util
    {$ifdef CPUX86_64}, arch.x86_64.memory.physical{$endif};
type
    POwner = ^TOwner;
    TOwner = record
        raw: PtrUInt;
        pages: uint32;
    end;

function reach32(address: PtrUInt; bytes: uint32): TDMAReach;
var physical: uint64;
    chunk: uint32;
begin
    reach32 := dmaInvalid;
    if bytes > High(PtrUInt) - address then exit;
    reach32 := dmaDirect;
    while bytes > 0 do begin
        physical := arch.platform.memory.physicalAddress(address);
        if physical = 0 then begin
            reach32 := dmaInvalid;
            exit;
        end;
        if physical > $FFFFFFFF then reach32 := dmaHigh;
        chunk := 4096 - (address and 4095);
        if chunk > bytes then chunk := bytes;
        inc(address, chunk);
        dec(bytes, chunk);
    end;
end;

{$ifdef CPUX86_64}
function allocateLowPages(bytes, alignment: uint32): pointer;
var raw, aligned: PtrUInt;
    pages: uint32;
    owner: POwner;
begin
    allocateLowPages := nil;
    pages := (PtrUInt(bytes) + alignment - 1 + sizeof(TOwner) + 4095) div 4096;
    raw := PtrUInt(alloc_low_run(pages));
    if raw = 0 then exit;
    aligned := (raw + sizeof(TOwner) + alignment - 1) and not PtrUInt(alignment - 1);
    owner := POwner(aligned - sizeof(TOwner));
    owner^.raw := raw;
    owner^.pages := pages;
    memset(aligned, 0, bytes);
    allocateLowPages := pointer(aligned);
end;
{$endif}

function allocate(bytes, alignment: uint32; lowOnly: boolean): pointer;
var raw, aligned, total: PtrUInt;
    owner: POwner;
begin
    allocate := nil;
    if (bytes = 0) or (alignment = 0) or (alignment > 4096) or
       ((alignment and (alignment - 1)) <> 0) then exit;
    if alignment < sizeof(PtrUInt) then alignment := sizeof(PtrUInt);
    total := PtrUInt(bytes) + PtrUInt(alignment - 1) + PtrUInt(sizeof(TOwner));
    if total < PtrUInt(bytes) then exit;
    raw := PtrUInt(tryAlloc(total));
    if raw <> 0 then begin
        aligned := (raw + sizeof(TOwner) + alignment - 1) and not PtrUInt(alignment - 1);
        if not lowOnly or (reach32(aligned, bytes) = dmaDirect) then begin
            owner := POwner(aligned - sizeof(TOwner));
            owner^.raw := raw;
            owner^.pages := 0;
            allocate := pointer(aligned);
            exit;
        end;
        kfree(void(raw));
    end;
    {$ifdef CPUX86_64}
    if lowOnly then allocate := allocateLowPages(bytes, alignment);
    {$endif}
end;

function allocateBounce(bytes: uint32): pointer;
begin
    allocateBounce := nil;
    if bytes = 0 then exit;
    {$ifdef CPUX86_64}
    allocateBounce := allocateLowPages(bytes, 16);
    {$endif}
end;

procedure release(buffer: pointer);
var owner: POwner;
    {$ifdef CPUX86_64}raw: PtrUInt; i, pages: uint32;{$endif}
begin
    if buffer = nil then exit;
    owner := POwner(PtrUInt(buffer) - sizeof(TOwner));
    {$ifdef CPUX86_64}
    pages := owner^.pages;
    if pages <> 0 then begin
        raw := owner^.raw;
        for i := 0 to pages - 1 do free_page(raw + PtrUInt(i) * 4096);
        exit;
    end;
    {$endif}
    kfree(void(owner^.raw));
end;

end.
