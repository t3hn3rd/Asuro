// Copyright 2021 Kieron Morris & Aaron Hance
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

{ Shared bitmap operations extracted from memory.heap. }
unit memory.bitmap;
interface
function find_free_run(bmp: PuInt32; start, count, total: uint32): sint32;
procedure bitmap_set_range(bmp: PuInt32; start, count: uint32);
procedure bitmap_clear_range(bmp: PuInt32; start, count: uint32);
function bitmap_all_set(bmp: PuInt32; start, count: uint32): boolean;
implementation
function find_free_run(bmp: PuInt32; start, count, total: uint32): sInt32;
var
    idx, run_len, dw_idx: uint32;
    dw: uint32;
begin
    find_free_run := -1;
    if (count = 0) or (count > total) then exit;
    idx := start;
    while idx <= total - count do begin
        dw_idx := idx shr 5;
        dw := bmp[dw_idx];

        { Fast skip: entire dword fully allocated }
        if dw = $FFFFFFFF then begin
            idx := (dw_idx + 1) shl 5;
            continue;
        end;

        { Check if bit at idx is free (0) }
        if (dw and (uint32(1) shl (idx and 31))) <> 0 then begin
            inc(idx);
            continue;
        end;

        { Free bit at idx - verify contiguous run of 'count' }
        run_len := 0;
        while run_len < count do begin
            if idx + run_len >= total then break;
            if (bmp[(idx + run_len) shr 5] and
                (uint32(1) shl ((idx + run_len) and 31))) <> 0 then
                break;
            inc(run_len);
        end;

        if run_len >= count then begin
            find_free_run := sInt32(idx);
            exit;
        end;

        { Skip past the used bit that broke the run }
        idx := idx + run_len + 1;
    end;
end;

procedure bitmap_set_range(bmp: PuInt32; start, count: uint32);
var
    i: uint32;
begin
    if count = 0 then exit;
    for i := start to start + count - 1 do
        bmp[i shr 5] := bmp[i shr 5] or (uint32(1) shl (i and 31));
end;

procedure bitmap_clear_range(bmp: PuInt32; start, count: uint32);
var
    i: uint32;
begin
    if count = 0 then exit;
    for i := start to start + count - 1 do
        bmp[i shr 5] := bmp[i shr 5] and not (uint32(1) shl (i and 31));
end;

{ Check that all bits in a range are set (for double-free detection). }
function bitmap_all_set(bmp: PuInt32; start, count: uint32): boolean;
var
    i: uint32;
begin
    bitmap_all_set := true;
    if count = 0 then exit;
    for i := start to start + count - 1 do begin
        if (bmp[i shr 5] and (uint32(1) shl (i and 31))) = 0 then begin
            bitmap_all_set := false;
            exit;
        end;
    end;
end;

end.
