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

{ Allocation-free diagnostics. The architecture supplies the character sink;
  formatting remains independent of UARTs, graphics, heaps, and interrupts. }
unit debug.early;
interface
type
    TCharWriter = procedure(ch: char);
procedure setWriter(writer: TCharWriter);
procedure puts(message: pchar);
procedure hex(value: uint64);
procedure field(name: pchar; value: uint64);
implementation
var
    sink: TCharWriter;
procedure setWriter(writer: TCharWriter);
begin
    sink := writer;
end;
procedure puts(message: pchar);
begin
    if sink = nil then exit;
    while message^ <> #0 do begin
        sink(message^);
        inc(message);
    end;
end;
procedure hex(value: uint64);
const
    digits: array[0..15] of char = '0123456789ABCDEF';
var
    shift: sint32;
begin
    if sink = nil then exit;
    for shift := 15 downto 0 do
        sink(digits[(value shr (shift * 4)) and $F]);
end;
procedure field(name: pchar; value: uint64);
begin
    puts(name);
    puts('=');
    hex(value);
    puts(#13#10);
end;
end.
