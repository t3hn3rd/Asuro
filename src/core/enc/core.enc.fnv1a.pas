//  Copyright 2024 Aaron Hance
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
	FNV-1a - Fowler-Noll-Vo non-cryptographic hash, variant 1a.
	Fast, well-distributed hashing suitable for hash tables, bloom filters
	and checksums. XOR-then-multiply per byte over a prime basis.

	Variants:
	  Hash_FNV1a32  - 32-bit digest  (basis $811C9DC5, prime $01000193)
	  Hash_FNV1a64  - 64-bit digest  (basis $CBF29CE484222325, prime $00000100000001B3)

	@author(Aaron Hance <ah@aaronhance.me>)
}
unit core.enc.fnv1a;

interface

  {** FNV-1a 32-bit hash.
    @param Data    Pointer to the data to hash.
    @param DataLen Length in bytes of the data.
    @returns 32-bit FNV-1a digest.
  **}
  function Hash_FNV1a32(Data : void; DataLen : uint32) : uint32;

  {** FNV-1a 64-bit hash.
    @param Data    Pointer to the data to hash.
    @param DataLen Length in bytes of the data.
    @returns 64-bit FNV-1a digest.
  **}
  function Hash_FNV1a64(Data : void; DataLen : uint32) : uint64;

  {** Runs FNV-1a unit tests and logs results via syslog. **}
  procedure UnitTest;

implementation

uses
  io.syslog,
  memory.heap,
  core.strings;

function Hash_FNV1a32(Data : void; DataLen : uint32) : uint32;
var
  i : uint32;
  p : puint8;
  h : uint32;
begin
  h := $811C9DC5;
  p := puint8(uint32(Data));
  if DataLen > 0 then
    for i := 0 to DataLen - 1 do
    begin
      h := h xor uint32(p^);
      h := h * $01000193;
      p := puint8(uint32(p) + 1);
    end;
  Hash_FNV1a32 := h;
end;

function Hash_FNV1a64(Data : void; DataLen : uint32) : uint64;
var
  i : uint32;
  p : puint8;
  h : uint64;
begin
  h := uint64($CBF29CE484222325);
  p := puint8(uint32(Data));
  if DataLen > 0 then
    for i := 0 to DataLen - 1 do
    begin
      h := h xor uint64(p^);
      h := h * uint64($00000100000001B3);
      p := puint8(uint32(p) + 1);
    end;
  Hash_FNV1a64 := h;
end;

procedure UnitTest;
var
  passed, failed       : uint32;
  buf1, buf2           : array[0..4] of byte;
  h32a                 : uint32;
  h64a                 : uint64;

  procedure Assert(condition : boolean; testName : pchar);
  var
    msg : pchar;
  begin
    if condition then
      inc(passed)
    else begin
      inc(failed);
      msg := stringConcat('FAIL: ', testName);
      io.syslog.logln('FNV1A', msg);
      kfree(void(msg));
    end;
  end;

  procedure PrintSummary;
  var
    pStr, fStr, msg, tmp : pchar;
  begin
    pStr := intToString(passed);
    fStr := intToString(failed);
    msg  := stringConcat(pStr, ' passed, ');
    tmp  := stringConcat(msg, fStr);
    kfree(void(msg));
    msg  := stringConcat(tmp, ' failed.');
    kfree(void(tmp));
    io.syslog.logln('FNV1A', msg);
    kfree(void(msg));
    kfree(void(pStr));
    kfree(void(fStr));
  end;

begin
  passed := 0;
  failed := 0;
  io.syslog.logln('FNV1A', 'Unit tests starting...');

  { Two distinct 5-byte inputs }
  buf1[0] := ord('h'); buf1[1] := ord('e'); buf1[2] := ord('l'); buf1[3] := ord('l'); buf1[4] := ord('o');
  buf2[0] := ord('w'); buf2[1] := ord('o'); buf2[2] := ord('r'); buf2[3] := ord('l'); buf2[4] := ord('d');

  { === Known basis value: zero-length input returns initial h === }
  Assert(Hash_FNV1a32(void(@buf1[0]), 0) = $811C9DC5, 'FNV1a32 empty = basis $811C9DC5');
  Assert(Hash_FNV1a64(void(@buf1[0]), 0) = uint64($CBF29CE484222325), 'FNV1a64 empty = basis');

  { === Determinism === }
  Assert(Hash_FNV1a32(void(@buf1[0]), 5) = Hash_FNV1a32(void(@buf1[0]), 5), 'FNV1a32 deterministic');
  Assert(Hash_FNV1a64(void(@buf1[0]), 5) = Hash_FNV1a64(void(@buf1[0]), 5), 'FNV1a64 deterministic');

  { === Distinct inputs produce distinct hashes === }
  Assert(Hash_FNV1a32(void(@buf1[0]), 5) <> Hash_FNV1a32(void(@buf2[0]), 5), 'FNV1a32 hello <> world');
  Assert(Hash_FNV1a64(void(@buf1[0]), 5) <> Hash_FNV1a64(void(@buf2[0]), 5), 'FNV1a64 hello <> world');

  { === Length sensitivity === }
  Assert(Hash_FNV1a32(void(@buf1[0]), 5) <> Hash_FNV1a32(void(@buf1[0]), 4), 'FNV1a32 length-sensitive');
  Assert(Hash_FNV1a64(void(@buf1[0]), 5) <> Hash_FNV1a64(void(@buf1[0]), 4), 'FNV1a64 length-sensitive');

  { === 32-bit and 64-bit produce independent outputs === }
  h32a := Hash_FNV1a32(void(@buf1[0]), 5);
  h64a := Hash_FNV1a64(void(@buf1[0]), 5);
  Assert(uint32(h64a) <> h32a, 'FNV1a32 != low32(FNV1a64)');

  PrintSummary;
end;

end.
