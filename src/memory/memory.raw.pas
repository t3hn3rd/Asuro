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

{ Allocation-free scalar memory operations with native addresses. }
unit memory.raw;

interface
procedure fill(dest: pointer; value: uint8; bytes: SizeUInt);
procedure move(source, dest: pointer; bytes: SizeUInt);

implementation
type PNative = ^PtrUInt;

procedure fill(dest: pointer; value: uint8; bytes: SizeUInt);
var
    address, pattern: PtrUInt;
begin
    address := PtrUInt(dest);
    pattern := (High(PtrUInt) div 255) * value;
    while bytes >= sizeof(PtrUInt) do begin
        PNative(address)^ := pattern;
        inc(address, sizeof(PtrUInt));
        dec(bytes, sizeof(PtrUInt));
    end;
    while bytes <> 0 do begin
        PUInt8(address)^ := value;
        inc(address);
        dec(bytes);
    end;
end;

procedure move(source, dest: pointer; bytes: SizeUInt);
var
    src, dst: PtrUInt;
begin
    src := PtrUInt(source);
    dst := PtrUInt(dest);
    if (src = dst) or (bytes = 0) then exit;
    if (dst > src) and (dst - src < bytes) then begin
        while bytes <> 0 do begin
            dec(bytes);
            PUInt8(dst + bytes)^ := PUInt8(src + bytes)^;
        end;
    end else begin
        while bytes >= sizeof(PtrUInt) do begin
            PNative(dst)^ := PNative(src)^;
            inc(dst, sizeof(PtrUInt));
            inc(src, sizeof(PtrUInt));
            dec(bytes, sizeof(PtrUInt));
        end;
        while bytes <> 0 do begin
            PUInt8(dst)^ := PUInt8(src)^;
            inc(dst);
            inc(src);
            dec(bytes);
        end;
    end;
end;
end.
