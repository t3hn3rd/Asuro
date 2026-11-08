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

{ i386 initial frame, extracted from proc.mgr (Kieron Morris). }
unit arch.x86.proc.context;

interface
function prepare(stack: pointer; bytes: SizeUInt; entry: pointer): PtrUInt;

implementation
uses memory.raw;

function prepare(stack: pointer; bytes: SizeUInt; entry: pointer): PtrUInt;
var
    top, frame: PtrUInt;
    i: uint32;
begin
    prepare := 0;
    if (stack = nil) or (entry = nil) or (bytes < 64) or
       (PtrUInt(stack) > High(PtrUInt) - bytes) then exit;
    top := PtrUInt(stack) + bytes;
    frame := top - 60;
    memory.raw.fill(pointer(frame), 0, 60);
    { GS, FS, ES, DS; PUSHAD; EIP, CS, EFLAGS. }
    for i := 0 to 3 do PUInt32(frame + i * 4)^ := $10;
    PUInt32(top - 12)^ := PtrUInt(entry);
    PUInt32(top - 8)^ := $08;
    PUInt32(top - 4)^ := $0202;
    prepare := frame;
end;
end.
