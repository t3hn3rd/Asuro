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
	Min-Heap - Lowest priority value extracted first.

	@author(Aaron Hance <ah@aaronhance.me>)
}
unit minh;

interface

uses
    dstypes,
    bheap;

{ ============================================================================ }
{                       Min-Heap — minh_* API                                }
{ ============================================================================ }

  {**
    @abstract Creates a new min-heap.
    @param ElementSize     Size (in bytes) of each data element.
    @param InitialCapacity Starting number of slots (will grow as needed).
    @returns Pointer to the new heap.
  **}
  function minh_New(ElementSize : uint32; InitialCapacity : uint32) : PBinaryHeap;

  {**
    @abstract Inserts an element into the min-heap.
    @param Heap     Pointer to the heap.
    @param Priority Priority value (lower = higher priority).
    @param Data     Pointer to the element data to copy in.
  **}
  procedure minh_Insert(Heap : PBinaryHeap; Priority : uint32; Data : void);

  {**
    @abstract Extracts the minimum-priority element from the heap.
    @param Heap Pointer to the heap.
    @param Data Pointer to a buffer that receives the extracted element.
    @returns True if an element was extracted, false if the heap was empty.
  **}
  function minh_ExtractMin(Heap : PBinaryHeap; Data : void) : boolean;

  {**
    @abstract Peeks at the minimum-priority element without removing it.
    @param Heap Pointer to the heap.
    @returns Pointer to the element data, or nil if empty.
  **}
  function minh_PeekMin(Heap : PBinaryHeap) : void;

  {**
    @abstract Returns the number of elements in the min-heap.
    @param Heap Pointer to the heap.
    @returns Element count.
  **}
  function minh_Size(Heap : PBinaryHeap) : uint32;

  {**
    @abstract Checks whether the min-heap is empty.
    @param Heap Pointer to the heap.
    @returns True if empty.
  **}
  function minh_IsEmpty(Heap : PBinaryHeap) : boolean;

  {**
    @abstract Frees the min-heap and all its elements.
    @param Heap Pointer to the heap.
  **}
  procedure minh_Free(Heap : PBinaryHeap);

  {** Runs unit tests for the min-heap. **}
  procedure UnitTest;

implementation

uses
    syslog, strings, lmemorymanager;

function minh_New(ElementSize : uint32; InitialCapacity : uint32) : PBinaryHeap;
begin
  minh_New := BHeap_New(ElementSize, InitialCapacity, true);
end;

procedure minh_Insert(Heap : PBinaryHeap; Priority : uint32; Data : void);
begin
  BHeap_Insert(Heap, Priority, Data);
end;

function minh_ExtractMin(Heap : PBinaryHeap; Data : void) : boolean;
begin
  minh_ExtractMin := BHeap_ExtractRoot(Heap, Data);
end;

function minh_PeekMin(Heap : PBinaryHeap) : void;
begin
  minh_PeekMin := BHeap_PeekRoot(Heap);
end;

function minh_Size(Heap : PBinaryHeap) : uint32;
begin
  minh_Size := Heap^.Count;
end;

function minh_IsEmpty(Heap : PBinaryHeap) : boolean;
begin
  minh_IsEmpty := (Heap^.Count = 0);
end;

procedure minh_Free(Heap : PBinaryHeap);
begin
  BHeap_Free(Heap);
end;

procedure UnitTest;
var
    h    : PBinaryHeap;
    v, r : uint32;
    ok   : boolean;
    p    : void;
    i    : uint32;
    good : boolean;
    passed, failed : uint32;

    procedure Assert(condition : boolean; testName : pchar);
    var
        msg : pchar;
    begin
        if condition then begin
            inc(passed);
        end else begin
            inc(failed);
            msg := stringConcat('FAIL: ', testName);
            syslog.logln('MINH', msg);
            kfree(void(msg));
        end;
    end;

    procedure PrintSummary;
    var
        pStr, fStr, msg, tmp : pchar;
    begin
        pStr := intToString(passed);
        fStr := intToString(failed);
        msg := stringConcat(pStr, ' passed, ');
        tmp := stringConcat(msg, fStr);
        kfree(void(msg));
        msg := stringConcat(tmp, ' failed.');
        kfree(void(tmp));
        syslog.logln('MINH', msg);
        kfree(void(msg));
        kfree(void(pStr));
        kfree(void(fStr));
    end;

begin
    passed := 0;
    failed := 0;
    syslog.logln('MINH', 'Unit tests starting...');

    { === New / Empty / Size === }
    h := minh_New(sizeof(uint32), 4);
    Assert(h <> nil, 'New returns non-nil');
    Assert(minh_IsEmpty(h), 'Initially empty');
    Assert(minh_Size(h) = 0, 'Initial size is 0');

    { === Insert out of order === }
    v := 30; minh_Insert(h, 30, @v);
    v := 10; minh_Insert(h, 10, @v);
    v := 50; minh_Insert(h, 50, @v);
    v := 20; minh_Insert(h, 20, @v);
    v := 40; minh_Insert(h, 40, @v);
    Assert(minh_Size(h) = 5, 'Size after 5 inserts');

    { === PeekMin === }
    p := minh_PeekMin(h);
    Assert(p <> nil, 'PeekMin non-nil');
    Assert(uint32(p^) = 10, 'PeekMin returns 10');

    { === ExtractMin in ascending order === }
    ok := minh_ExtractMin(h, @r); Assert(ok, 'Extract 1 ok'); Assert(r = 10, 'Extract 10');
    ok := minh_ExtractMin(h, @r); Assert(ok, 'Extract 2 ok'); Assert(r = 20, 'Extract 20');
    ok := minh_ExtractMin(h, @r); Assert(ok, 'Extract 3 ok'); Assert(r = 30, 'Extract 30');
    ok := minh_ExtractMin(h, @r); Assert(ok, 'Extract 4 ok'); Assert(r = 40, 'Extract 40');
    ok := minh_ExtractMin(h, @r); Assert(ok, 'Extract 5 ok'); Assert(r = 50, 'Extract 50');
    Assert(minh_IsEmpty(h), 'Empty after all extracted');

    { === Edge: extract/peek on empty === }
    ok := minh_ExtractMin(h, @r);
    Assert(not ok, 'Extract on empty returns false');
    p := minh_PeekMin(h);
    Assert(p = nil, 'PeekMin on empty returns nil');

    minh_Free(h);

    { === Stress: 50 elements reverse insert === }
    h := minh_New(sizeof(uint32), 4);
    for i := 50 downto 1 do
    begin
        v := i;
        minh_Insert(h, i, @v);
    end;
    Assert(minh_Size(h) = 50, 'Stress: 50 inserted');
    good := true;
    for i := 1 to 50 do
    begin
        ok := minh_ExtractMin(h, @r);
        if (not ok) or (r <> i) then good := false;
    end;
    Assert(good, 'Stress: 50 extracted in ascending order');
    minh_Free(h);

    PrintSummary;
end;

end.