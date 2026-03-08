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
	Bloom Filter - A probabilistic data structure for set membership testing.
	Offers space-efficient membership queries with a configurable false positive
	rate. Provides O(k) time complexity for insertions and membership checks,
	where k is the number of hash functions. Uses double hashing (FNV-1a + DJB2)
	to derive k independent bit positions without storing k separate hash
	functions.

	False positives are possible; false negatives are not.

	@author(Aaron Hance <ah@aaronhance.me>)
}

unit core.ds.bloom;

interface

uses
  core.ds.types,
  memory.heap,
  core.util,
  core.enc.fnv1a,
  core.enc.djb2,
  io.syslog,
  core.strings;

  {** Creates a new Bloom filter.
    @param BitCount   Total number of bits in the filter (m). Larger values
                      reduce the false-positive rate. A common guideline is
                      m = -n*ln(p) / (ln(2)^2) for n expected elements and
                      target false-positive rate p.
    @param HashCount  Number of hash functions to apply per element (k).
                      Optimal k = (m/n) * ln(2).
    @returns Pointer to the new filter, or nil on allocation failure.
  **}
  function Bloom_New(BitCount : uint32; HashCount : uint32) : PBloomFilter;

  {** Inserts an element into the filter.
    @param Filter  The filter to insert into.
    @param Data    Pointer to the element data.
    @param DataLen Length in bytes of the element data.
  **}
  procedure Bloom_Add(Filter : PBloomFilter; Data : void; DataLen : uint32);

  {** Tests whether an element is (probably) in the filter.
    @param Filter  The filter to query.
    @param Data    Pointer to the element data.
    @param DataLen Length in bytes of the element data.
    @returns True if the element was probably inserted; false if definitely not.
  **}
  function Bloom_Test(Filter : PBloomFilter; Data : void; DataLen : uint32) : boolean;

  {** Resets all bits to zero without freeing the filter.
    @param Filter The filter to clear.
  **}
  procedure Bloom_Clear(Filter : PBloomFilter);

  {** Frees the filter and its bit buffer.
    @param Filter The filter to free.
  **}
  procedure Bloom_Free(Filter : PBloomFilter);

  {** Runs Bloom filter unit tests and logs results via syslog. **}
  procedure UnitTest;

implementation

{ ---------------------------------------------------------------------------- }
{  Internal helpers — bit access                                               }
{ ---------------------------------------------------------------------------- }

{** Sets bit index BitIdx in the filter's bit array. **}
procedure Bloom_SetBit(Filter : PBloomFilter; BitIdx : uint32); inline;
var
  b : puint8;
begin
  b  := puint8(uint32(Filter^.Bits) + (BitIdx div 8));
  b^ := b^ or byte(1 shl (BitIdx mod 8));
end;

{** Returns true if bit index BitIdx is set in the filter's bit array. **}
function Bloom_GetBit(Filter : PBloomFilter; BitIdx : uint32) : boolean; inline;
var
  b : puint8;
begin
  b            := puint8(uint32(Filter^.Bits) + (BitIdx div 8));
  Bloom_GetBit := (b^ and byte(1 shl (BitIdx mod 8))) <> 0;
end;

{ ---------------------------------------------------------------------------- }
{  Public API                                                                  }
{ ---------------------------------------------------------------------------- }

function Bloom_New(BitCount : uint32; HashCount : uint32) : PBloomFilter;
var
  F         : PBloomFilter;
  ByteCount : uint32;
begin
  F := PBloomFilter(kalloc(sizeof(TBloomFilter)));
  if F = nil then
  begin
    Bloom_New := nil;
    exit;
  end;

  ByteCount := (BitCount + 7) div 8;

  F^.Bits      := kalloc(ByteCount);
  F^.BitCount  := BitCount;
  F^.HashCount := HashCount;
  F^.Count     := 0;
  memset(uint32(F^.Bits), 0, ByteCount);

  Bloom_New := F;
end;

procedure Bloom_Add(Filter : PBloomFilter; Data : void; DataLen : uint32);
var
  h1, h2 : uint32;
  i, bit  : uint32;
begin
  h1 := Hash_FNV1a32(Data, DataLen);
  h2 := Hash_DJB2_32(Data, DataLen);

  { Ensure h2 is odd to guarantee full period coverage of the bit array }
  h2 := h2 or 1;

  if Filter^.HashCount > 0 then
    for i := 0 to Filter^.HashCount - 1 do
    begin
      bit := (h1 + i * h2) mod Filter^.BitCount;
      Bloom_SetBit(Filter, bit);
    end;

  Filter^.Count := Filter^.Count + 1;
end;

function Bloom_Test(Filter : PBloomFilter; Data : void; DataLen : uint32) : boolean;
var
  h1, h2 : uint32;
  i, bit  : uint32;
begin
  h1 := Hash_FNV1a32(Data, DataLen);
  h2 := Hash_DJB2_32(Data, DataLen);
  h2 := h2 or 1;

  Bloom_Test := true;
  if Filter^.HashCount > 0 then
    for i := 0 to Filter^.HashCount - 1 do
    begin
      bit := (h1 + i * h2) mod Filter^.BitCount;
      if not Bloom_GetBit(Filter, bit) then
      begin
        Bloom_Test := false;
        exit;
      end;
    end;
end;

procedure Bloom_Clear(Filter : PBloomFilter);
var
  ByteCount : uint32;
begin
  if Filter = nil then exit;
  ByteCount := (Filter^.BitCount + 7) div 8;
  memset(uint32(Filter^.Bits), 0, ByteCount);
  Filter^.Count := 0;
end;

procedure Bloom_Free(Filter : PBloomFilter);
begin
  if Filter = nil then exit;
  kfree(Filter^.Bits);
  kfree(void(Filter));
end;

procedure UnitTest;
var
  passed, failed : uint32;
  f              : PBloomFilter;
  buf1, buf2     : array[0..4] of byte;

  procedure Assert(condition : boolean; testName : pchar);
  var
    msg : pchar;
  begin
    if condition then
      inc(passed)
    else begin
      inc(failed);
      msg := stringConcat('FAIL: ', testName);
      io.syslog.logln('BLOOM', msg);
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
    io.syslog.logln('BLOOM', msg);
    kfree(void(msg));
    kfree(void(pStr));
    kfree(void(fStr));
  end;

begin
  passed := 0;
  failed := 0;
  io.syslog.logln('BLOOM', 'Unit tests starting...');

  { Two distinct 5-byte inputs: "hello" and "world" }
  buf1[0] := ord('h'); buf1[1] := ord('e'); buf1[2] := ord('l'); buf1[3] := ord('l'); buf1[4] := ord('o');
  buf2[0] := ord('w'); buf2[1] := ord('o'); buf2[2] := ord('r'); buf2[3] := ord('l'); buf2[4] := ord('d');

  { === New === }
  f := Bloom_New(1024, 7);
  Assert(f <> nil, 'Bloom_New returns non-nil');
  Assert(f^.BitCount  = 1024, 'BitCount = 1024');
  Assert(f^.HashCount = 7,    'HashCount = 7');
  Assert(f^.Count     = 0,    'Initial Count = 0');

  { === Empty filter: Test returns false === }
  Assert(not Bloom_Test(f, void(@buf1[0]), 5), 'Test(hello) before Add = false');
  Assert(not Bloom_Test(f, void(@buf2[0]), 5), 'Test(world) before Add = false');

  { === Add then Test: should return true === }
  Bloom_Add(f, void(@buf1[0]), 5);
  Assert(Bloom_Test(f, void(@buf1[0]), 5), 'Test(hello) after Add = true');
  Assert(f^.Count = 1, 'Count = 1 after one Add');

  { === Un-added element: should return false (1 of 1024 bits set per hash) === }
  Assert(not Bloom_Test(f, void(@buf2[0]), 5), 'Test(world) not added = false');

  { === Add second element === }
  Bloom_Add(f, void(@buf2[0]), 5);
  Assert(Bloom_Test(f, void(@buf2[0]), 5), 'Test(world) after Add = true');
  Assert(f^.Count = 2, 'Count = 2 after two Adds');

  { === Both elements still present === }
  Assert(Bloom_Test(f, void(@buf1[0]), 5), 'Test(hello) still true after second Add');

  { === Clear resets all bits and count === }
  Bloom_Clear(f);
  Assert(f^.Count = 0, 'Count = 0 after Clear');
  Assert(not Bloom_Test(f, void(@buf1[0]), 5), 'Test(hello) after Clear = false');
  Assert(not Bloom_Test(f, void(@buf2[0]), 5), 'Test(world) after Clear = false');

  { === Re-add after clear still works === }
  Bloom_Add(f, void(@buf1[0]), 5);
  Assert(Bloom_Test(f, void(@buf1[0]), 5), 'Test(hello) after re-Add = true');

  Bloom_Free(f);

  PrintSummary;
end;

end.