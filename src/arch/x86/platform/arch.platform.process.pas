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

{ Build-selected x86 adapter. }
unit arch.platform.process;

interface
{$i ../../common/platform.process.inc}

implementation
uses arch.x86.proc.context, arch.x86.bda;

function prepare(stack: pointer; bytes: SizeUInt; entry: pointer): PtrUInt;
begin
    prepare := arch.x86.proc.context.prepare(stack, bytes, entry);
end;

function timerTicks: uint32;
begin
    timerTicks := PUInt32(@Counters.c32)^;
end;
end.
