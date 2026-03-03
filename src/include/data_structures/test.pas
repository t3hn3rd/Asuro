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
	Data Structure Tests - Exercises every data structure type and logs results via syslog.

	Call test_RunAll to execute every test. Each test logs PASS or FAIL
	for individual assertions and a summary at the end.

	@author(Aaron Hance <ah@aaronhance.me>)
}
unit test;

interface

uses
    lmemorymanager,
    cfifo,
    cfifols,
    circ,
    fifo,
    bheap,
    lifo,
    maxh,
    minh,
    prio,
    dstypes,
    syslog,
    util;

{** Runs all queue tests. Logs results to syslog. **}
procedure test_RunAll;

implementation

const
  TAG = 'DS_TEST';

var
  TotalPass : uint32;
  TotalFail : uint32;

{ ---------------------------------------------------------------------------- }
{  Test helpers                                                                }
{ ---------------------------------------------------------------------------- }

procedure Assert(condition : boolean; name : pchar);
begin
  if condition then
  begin
    syslog.log(TAG, '  PASS: ');
    syslog.writestringln(name);
    TotalPass := TotalPass + 1;
  end
  else
  begin
    syslog.log(TAG, '  FAIL: ');
    syslog.writestringln(name);
    TotalFail := TotalFail + 1;
  end;
end;

procedure AssertEq(actual, expected : uint32; name : pchar);
begin
  if actual = expected then
  begin
    syslog.log(TAG, '  PASS: ');
    syslog.writestringln(name);
    TotalPass := TotalPass + 1;
  end
  else
  begin
    syslog.log(TAG, '  FAIL: ');
    syslog.writestring(name);
    syslog.writestring(' (expected ');
    syslog.writeint(integer(expected));
    syslog.writestring(', got ');
    syslog.writeint(integer(actual));
    syslog.writestringln(')');
    TotalFail := TotalFail + 1;
  end;
end;

procedure Section(name : pchar);
begin
  syslog.logln(TAG, name);
end;

{ ---------------------------------------------------------------------------- }
{  FIFO Tests                                                                  }
{ ---------------------------------------------------------------------------- }

procedure Test_FIFO;
var
  q    : PFIFOQueue;
  v, r : uint32;
  ok   : boolean;
  p    : void;
begin
  Section('--- FIFO ---');

  q := FIFO_New(sizeof(uint32));
  Assert(q <> nil, 'FIFO: New returns non-nil');
  Assert(FIFO_IsEmpty(q), 'FIFO: Initially empty');
  AssertEq(FIFO_Size(q), 0, 'FIFO: Initial size is 0');

  { Enqueue 10, 20, 30 }
  v := 10; FIFO_Enqueue(q, @v);
  v := 20; FIFO_Enqueue(q, @v);
  v := 30; FIFO_Enqueue(q, @v);
  AssertEq(FIFO_Size(q), 3, 'FIFO: Size after 3 enqueues');
  Assert(not FIFO_IsEmpty(q), 'FIFO: Not empty after enqueue');

  { Peek should return 10 }
  p := FIFO_Peek(q);
  Assert(p <> nil, 'FIFO: Peek non-nil');
  AssertEq(p^, 10, 'FIFO: Peek returns first enqueued');

  { Dequeue should return 10, 20, 30 in order }
  ok := FIFO_Dequeue(q, @r);
  Assert(ok, 'FIFO: Dequeue 1 succeeds');
  AssertEq(r, 10, 'FIFO: Dequeue 1 value');

  ok := FIFO_Dequeue(q, @r);
  Assert(ok, 'FIFO: Dequeue 2 succeeds');
  AssertEq(r, 20, 'FIFO: Dequeue 2 value');

  ok := FIFO_Dequeue(q, @r);
  Assert(ok, 'FIFO: Dequeue 3 succeeds');
  AssertEq(r, 30, 'FIFO: Dequeue 3 value');

  Assert(FIFO_IsEmpty(q), 'FIFO: Empty after all dequeued');

  { Dequeue on empty should return false }
  ok := FIFO_Dequeue(q, @r);
  Assert(not ok, 'FIFO: Dequeue on empty returns false');

  { Peek on empty should return nil }
  p := FIFO_Peek(q);
  Assert(p = nil, 'FIFO: Peek on empty returns nil');

  FIFO_Free(q);
  Section('--- FIFO done ---');
end;

{ ---------------------------------------------------------------------------- }
{  Contiguous FIFO Tests                                                       }
{ ---------------------------------------------------------------------------- }

procedure Test_CFIFO;
var
  q    : PCFIFOQueue;
  v, r : uint32;
  ok   : boolean;
  p    : void;
  i    : uint32;
begin
  Section('--- CFIFO ---');

  q := CFIFO_New(sizeof(uint32), 4);
  Assert(q <> nil, 'CFIFO: New returns non-nil');
  Assert(CFIFO_IsEmpty(q), 'CFIFO: Initially empty');
  AssertEq(CFIFO_Size(q), 0, 'CFIFO: Initial size is 0');
  AssertEq(CFIFO_Capacity(q), 4, 'CFIFO: Initial capacity is 4');

  { Enqueue 1..4 (fill initial capacity) }
  for i := 1 to 4 do
  begin
    v := i * 10;
    CFIFO_Enqueue(q, @v);
  end;
  AssertEq(CFIFO_Size(q), 4, 'CFIFO: Size after 4 enqueues');

  { Dequeue first two to advance Head }
  ok := CFIFO_Dequeue(q, @r);
  Assert(ok, 'CFIFO: Dequeue 1 succeeds');
  AssertEq(r, 10, 'CFIFO: Dequeue 1 value');

  ok := CFIFO_Dequeue(q, @r);
  Assert(ok, 'CFIFO: Dequeue 2 succeeds');
  AssertEq(r, 20, 'CFIFO: Dequeue 2 value');

  AssertEq(CFIFO_Size(q), 2, 'CFIFO: Size after 2 dequeues');

  { Enqueue more to trigger compaction and/or growth }
  for i := 5 to 8 do
  begin
    v := i * 10;
    CFIFO_Enqueue(q, @v);
  end;
  AssertEq(CFIFO_Size(q), 6, 'CFIFO: Size after grow');

  { Verify FIFO order of remaining: 30, 40, 50, 60, 70, 80 }
  ok := CFIFO_Dequeue(q, @r); AssertEq(r, 30, 'CFIFO: Order 30');
  ok := CFIFO_Dequeue(q, @r); AssertEq(r, 40, 'CFIFO: Order 40');
  ok := CFIFO_Dequeue(q, @r); AssertEq(r, 50, 'CFIFO: Order 50');
  ok := CFIFO_Dequeue(q, @r); AssertEq(r, 60, 'CFIFO: Order 60');
  ok := CFIFO_Dequeue(q, @r); AssertEq(r, 70, 'CFIFO: Order 70');
  ok := CFIFO_Dequeue(q, @r); AssertEq(r, 80, 'CFIFO: Order 80');

  Assert(CFIFO_IsEmpty(q), 'CFIFO: Empty after drain');

  { Peek on empty }
  p := CFIFO_Peek(q);
  Assert(p = nil, 'CFIFO: Peek on empty returns nil');

  { Dequeue on empty }
  ok := CFIFO_Dequeue(q, @r);
  Assert(not ok, 'CFIFO: Dequeue on empty returns false');

  CFIFO_Free(q);
  Section('--- CFIFO done ---');
end;

{ ---------------------------------------------------------------------------- }
{  Contiguous FIFO List Tests                                                  }
{ ---------------------------------------------------------------------------- }

procedure Test_CFIFOLS;
var
  ls   : PCFIFOList;
  q1   : PCFIFOQueue;
  q2   : PCFIFOQueue;
  q3   : PCFIFOQueue;
  got  : PCFIFOQueue;
  ok   : boolean;
begin
  Section('--- CFIFOLS ---');

  ls := CFIFOLS_New(2);
  Assert(ls <> nil, 'CFIFOLS: New returns non-nil');
  Assert(CFIFOLS_IsEmpty(ls), 'CFIFOLS: Initially empty');
  AssertEq(CFIFOLS_Count(ls), 0, 'CFIFOLS: Initial count is 0');

  q1 := CFIFO_New(sizeof(uint32), 4);
  q2 := CFIFO_New(sizeof(uint32), 4);
  q3 := CFIFO_New(sizeof(uint32), 4);

  CFIFOLS_Add(ls, q1);
  CFIFOLS_Add(ls, q2);
  CFIFOLS_Add(ls, q3);
  AssertEq(CFIFOLS_Count(ls), 3, 'CFIFOLS: Count after 3 adds');

  got := CFIFOLS_Get(ls, 0);
  Assert(got = q1, 'CFIFOLS: Get(0) returns q1');
  got := CFIFOLS_Get(ls, 1);
  Assert(got = q2, 'CFIFOLS: Get(1) returns q2');
  got := CFIFOLS_Get(ls, 2);
  Assert(got = q3, 'CFIFOLS: Get(2) returns q3');

  { Out-of-bounds }
  got := CFIFOLS_Get(ls, 99);
  Assert(got = nil, 'CFIFOLS: Get out-of-bounds returns nil');

  { Remove middle }
  ok := CFIFOLS_Remove(ls, 1);
  Assert(ok, 'CFIFOLS: Remove(1) succeeds');
  AssertEq(CFIFOLS_Count(ls), 2, 'CFIFOLS: Count after remove');
  got := CFIFOLS_Get(ls, 0);
  Assert(got = q1, 'CFIFOLS: After remove, Get(0) still q1');
  got := CFIFOLS_Get(ls, 1);
  Assert(got = q3, 'CFIFOLS: After remove, Get(1) is now q3');

  { Remove out-of-bounds }
  ok := CFIFOLS_Remove(ls, 99);
  Assert(not ok, 'CFIFOLS: Remove out-of-bounds returns false');

  { Free list only (not the queues) }
  CFIFOLS_Free(ls);

  { Free queues we still own }
  CFIFO_Free(q1);
  CFIFO_Free(q2);
  CFIFO_Free(q3);

  { Test FreeAll path }
  ls := CFIFOLS_New(2);
  CFIFOLS_Add(ls, CFIFO_New(sizeof(uint32), 4));
  CFIFOLS_Add(ls, CFIFO_New(sizeof(uint32), 4));
  CFIFOLS_FreeAll(ls);
  Section('--- CFIFOLS done ---');
end;

{ ---------------------------------------------------------------------------- }
{  LIFO Tests                                                                  }
{ ---------------------------------------------------------------------------- }

procedure Test_LIFO;
var
  s    : PLIFOStack;
  v, r : uint32;
  ok   : boolean;
  p    : void;
begin
  Section('--- LIFO ---');

  s := stk_lifo_New(sizeof(uint32));
  Assert(s <> nil, 'LIFO: New returns non-nil');
  Assert(stk_lifo_IsEmpty(s), 'LIFO: Initially empty');
  AssertEq(stk_lifo_Size(s), 0, 'LIFO: Initial size is 0');

  { Push 10, 20, 30 }
  v := 10; stk_lifo_Push(s, @v);
  v := 20; stk_lifo_Push(s, @v);
  v := 30; stk_lifo_Push(s, @v);
  AssertEq(stk_lifo_Size(s), 3, 'LIFO: Size after 3 pushes');

  { Peek should return 30 (last pushed) }
  p := stk_lifo_Peek(s);
  Assert(p <> nil, 'LIFO: Peek non-nil');
  AssertEq(p^, 30, 'LIFO: Peek returns last pushed');

  { Pop should return 30, 20, 10 (reverse order) }
  ok := stk_lifo_Pop(s, @r);
  Assert(ok, 'LIFO: Pop 1 succeeds');
  AssertEq(r, 30, 'LIFO: Pop 1 value');

  ok := stk_lifo_Pop(s, @r);
  Assert(ok, 'LIFO: Pop 2 succeeds');
  AssertEq(r, 20, 'LIFO: Pop 2 value');

  ok := stk_lifo_Pop(s, @r);
  Assert(ok, 'LIFO: Pop 3 succeeds');
  AssertEq(r, 10, 'LIFO: Pop 3 value');

  Assert(stk_lifo_IsEmpty(s), 'LIFO: Empty after all popped');

  ok := stk_lifo_Pop(s, @r);
  Assert(not ok, 'LIFO: Pop on empty returns false');

  p := stk_lifo_Peek(s);
  Assert(p = nil, 'LIFO: Peek on empty returns nil');

  stk_lifo_Free(s);
  Section('--- LIFO done ---');
end;

{ ---------------------------------------------------------------------------- }
{  Circular Queue Tests                                                        }
{ ---------------------------------------------------------------------------- }

procedure Test_CIRC;
var
  q    : PCircularQueue;
  v, r : uint32;
  ok   : boolean;
  p    : void;
  i    : uint32;
begin
  Section('--- CIRC ---');

  q := circ_New(4, sizeof(uint32));
  Assert(q <> nil, 'CIRC: New returns non-nil');
  Assert(circ_IsEmpty(q), 'CIRC: Initially empty');
  Assert(not circ_IsFull(q), 'CIRC: Initially not full');
  AssertEq(circ_Size(q), 0, 'CIRC: Initial size is 0');

  { Fill to capacity }
  for i := 1 to 4 do
  begin
    v := i * 100;
    ok := circ_Enqueue(q, @v);
    Assert(ok, 'CIRC: Enqueue succeeds while not full');
  end;
  Assert(circ_IsFull(q), 'CIRC: Full after 4 enqueues');
  AssertEq(circ_Size(q), 4, 'CIRC: Size is 4 when full');

  { Enqueue when full should fail }
  v := 999;
  ok := circ_Enqueue(q, @v);
  Assert(not ok, 'CIRC: Enqueue on full returns false');

  { Peek }
  p := circ_Peek(q);
  Assert(p <> nil, 'CIRC: Peek non-nil');
  AssertEq(p^, 100, 'CIRC: Peek returns first enqueued');

  { Dequeue all — FIFO order }
  ok := circ_Dequeue(q, @r); AssertEq(r, 100, 'CIRC: Dequeue 1 value');
  ok := circ_Dequeue(q, @r); AssertEq(r, 200, 'CIRC: Dequeue 2 value');
  ok := circ_Dequeue(q, @r); AssertEq(r, 300, 'CIRC: Dequeue 3 value');
  ok := circ_Dequeue(q, @r); AssertEq(r, 400, 'CIRC: Dequeue 4 value');

  Assert(circ_IsEmpty(q), 'CIRC: Empty after all dequeued');

  ok := circ_Dequeue(q, @r);
  Assert(not ok, 'CIRC: Dequeue on empty returns false');

  p := circ_Peek(q);
  Assert(p = nil, 'CIRC: Peek on empty returns nil');

  { Wrap-around: enqueue 2, dequeue 1, repeat — exercises ring buffer }
  v := 1; circ_Enqueue(q, @v);
  v := 2; circ_Enqueue(q, @v);
  circ_Dequeue(q, @r);                  { dequeue 1 }
  v := 3; circ_Enqueue(q, @v);
  v := 4; circ_Enqueue(q, @v);
  circ_Dequeue(q, @r); AssertEq(r, 2, 'CIRC: Wraparound order 2');
  circ_Dequeue(q, @r); AssertEq(r, 3, 'CIRC: Wraparound order 3');
  circ_Dequeue(q, @r); AssertEq(r, 4, 'CIRC: Wraparound order 4');
  Assert(circ_IsEmpty(q), 'CIRC: Empty after wraparound');

  circ_Free(q);
  Section('--- CIRC done ---');
end;

{ ---------------------------------------------------------------------------- }
{  Min-Heap Tests                                                              }
{ ---------------------------------------------------------------------------- }

procedure Test_MINH;
var
  h    : PBinaryHeap;
  v, r : uint32;
  ok   : boolean;
  p    : void;
begin
  Section('--- MINH ---');

  h := h_minh_New(sizeof(uint32), 4);
  Assert(h <> nil, 'MINH: New returns non-nil');
  Assert(h_minh_IsEmpty(h), 'MINH: Initially empty');
  AssertEq(h_minh_Size(h), 0, 'MINH: Initial size is 0');

  { Insert out of order }
  v := 30; h_minh_Insert(h, 30, @v);
  v := 10; h_minh_Insert(h, 10, @v);
  v := 50; h_minh_Insert(h, 50, @v);
  v := 20; h_minh_Insert(h, 20, @v);
  v := 40; h_minh_Insert(h, 40, @v);
  AssertEq(h_minh_Size(h), 5, 'MINH: Size after 5 inserts');

  { Peek should return min (10) }
  p := h_minh_PeekMin(h);
  Assert(p <> nil, 'MINH: PeekMin non-nil');
  AssertEq(p^, 10, 'MINH: PeekMin returns 10');

  { Extract all — should come out in ascending order }
  ok := h_minh_ExtractMin(h, @r); Assert(ok, 'MINH: Extract 1 ok'); AssertEq(r, 10, 'MINH: Extract 10');
  ok := h_minh_ExtractMin(h, @r); Assert(ok, 'MINH: Extract 2 ok'); AssertEq(r, 20, 'MINH: Extract 20');
  ok := h_minh_ExtractMin(h, @r); Assert(ok, 'MINH: Extract 3 ok'); AssertEq(r, 30, 'MINH: Extract 30');
  ok := h_minh_ExtractMin(h, @r); Assert(ok, 'MINH: Extract 4 ok'); AssertEq(r, 40, 'MINH: Extract 40');
  ok := h_minh_ExtractMin(h, @r); Assert(ok, 'MINH: Extract 5 ok'); AssertEq(r, 50, 'MINH: Extract 50');

  Assert(h_minh_IsEmpty(h), 'MINH: Empty after all extracted');

  ok := h_minh_ExtractMin(h, @r);
  Assert(not ok, 'MINH: Extract on empty returns false');

  p := h_minh_PeekMin(h);
  Assert(p = nil, 'MINH: PeekMin on empty returns nil');

  h_minh_Free(h);
  Section('--- MINH done ---');
end;

{ ---------------------------------------------------------------------------- }
{  Max-Heap Tests                                                              }
{ ---------------------------------------------------------------------------- }

procedure Test_MAXH;
var
  h    : PBinaryHeap;
  v, r : uint32;
  ok   : boolean;
  p    : void;
begin
  Section('--- MAXH ---');

  h := h_maxh_New(sizeof(uint32), 4);
  Assert(h <> nil, 'MAXH: New returns non-nil');
  Assert(h_maxh_IsEmpty(h), 'MAXH: Initially empty');

  v := 30; h_maxh_Insert(h, 30, @v);
  v := 10; h_maxh_Insert(h, 10, @v);
  v := 50; h_maxh_Insert(h, 50, @v);
  v := 20; h_maxh_Insert(h, 20, @v);
  v := 40; h_maxh_Insert(h, 40, @v);
  AssertEq(h_maxh_Size(h), 5, 'MAXH: Size after 5 inserts');

  { Peek should return max (50) }
  p := h_maxh_PeekMax(h);
  Assert(p <> nil, 'MAXH: PeekMax non-nil');
  AssertEq(p^, 50, 'MAXH: PeekMax returns 50');

  { Extract all — should come out in descending order }
  ok := h_maxh_ExtractMax(h, @r); Assert(ok, 'MAXH: Extract 1 ok'); AssertEq(r, 50, 'MAXH: Extract 50');
  ok := h_maxh_ExtractMax(h, @r); Assert(ok, 'MAXH: Extract 2 ok'); AssertEq(r, 40, 'MAXH: Extract 40');
  ok := h_maxh_ExtractMax(h, @r); Assert(ok, 'MAXH: Extract 3 ok'); AssertEq(r, 30, 'MAXH: Extract 30');
  ok := h_maxh_ExtractMax(h, @r); Assert(ok, 'MAXH: Extract 4 ok'); AssertEq(r, 20, 'MAXH: Extract 20');
  ok := h_maxh_ExtractMax(h, @r); Assert(ok, 'MAXH: Extract 5 ok'); AssertEq(r, 10, 'MAXH: Extract 10');

  Assert(h_maxh_IsEmpty(h), 'MAXH: Empty after all extracted');

  ok := h_maxh_ExtractMax(h, @r);
  Assert(not ok, 'MAXH: Extract on empty returns false');

  p := h_maxh_PeekMax(h);
  Assert(p = nil, 'MAXH: PeekMax on empty returns nil');

  h_maxh_Free(h);
  Section('--- MAXH done ---');
end;

{ ---------------------------------------------------------------------------- }
{  Priority Queue Tests                                                        }
{ ---------------------------------------------------------------------------- }

procedure Test_PRIO;
var
  h    : PBinaryHeap;
  v, r : uint32;
  ok   : boolean;
  p    : void;
begin
  Section('--- PRIO ---');

  h := prio_New(sizeof(uint32), 4);
  Assert(h <> nil, 'PRIO: New returns non-nil');
  Assert(prio_IsEmpty(h), 'PRIO: Initially empty');

  { Enqueue with varying priorities (lower value = higher priority) }
  v := 300; prio_Enqueue(h, 3, @v);
  v := 100; prio_Enqueue(h, 1, @v);
  v := 500; prio_Enqueue(h, 5, @v);
  v := 200; prio_Enqueue(h, 2, @v);
  v := 400; prio_Enqueue(h, 4, @v);
  AssertEq(prio_Size(h), 5, 'PRIO: Size after 5 enqueues');

  { Peek should return highest priority (lowest value = 1 -> data 100) }
  p := prio_Peek(h);
  Assert(p <> nil, 'PRIO: Peek non-nil');
  AssertEq(p^, 100, 'PRIO: Peek returns data with priority 1');

  { Dequeue all — should come out by priority 1, 2, 3, 4, 5 }
  ok := prio_Dequeue(h, @r); Assert(ok, 'PRIO: Dequeue 1 ok'); AssertEq(r, 100, 'PRIO: Dequeue pri=1');
  ok := prio_Dequeue(h, @r); Assert(ok, 'PRIO: Dequeue 2 ok'); AssertEq(r, 200, 'PRIO: Dequeue pri=2');
  ok := prio_Dequeue(h, @r); Assert(ok, 'PRIO: Dequeue 3 ok'); AssertEq(r, 300, 'PRIO: Dequeue pri=3');
  ok := prio_Dequeue(h, @r); Assert(ok, 'PRIO: Dequeue 4 ok'); AssertEq(r, 400, 'PRIO: Dequeue pri=4');
  ok := prio_Dequeue(h, @r); Assert(ok, 'PRIO: Dequeue 5 ok'); AssertEq(r, 500, 'PRIO: Dequeue pri=5');

  Assert(prio_IsEmpty(h), 'PRIO: Empty after all dequeued');

  ok := prio_Dequeue(h, @r);
  Assert(not ok, 'PRIO: Dequeue on empty returns false');

  p := prio_Peek(h);
  Assert(p = nil, 'PRIO: Peek on empty returns nil');

  prio_Free(h);
  Section('--- PRIO done ---');
end;

{ ---------------------------------------------------------------------------- }
{  Stress / Growth Tests                                                       }
{ ---------------------------------------------------------------------------- }

procedure Test_Stress;
var
  q    : PFIFOQueue;
  cq   : PCFIFOQueue;
  h    : PBinaryHeap;
  v, r : uint32;
  ok   : boolean;
  i    : uint32;
  good : boolean;
begin
  Section('--- STRESS ---');

  { FIFO: 100 elements }
  q := FIFO_New(sizeof(uint32));
  for i := 0 to 99 do
  begin
    v := i;
    FIFO_Enqueue(q, @v);
  end;
  AssertEq(FIFO_Size(q), 100, 'STRESS: FIFO 100 enqueued');

  good := true;
  for i := 0 to 99 do
  begin
    ok := FIFO_Dequeue(q, @r);
    if (not ok) or (r <> i) then good := false;
  end;
  Assert(good, 'STRESS: FIFO 100 dequeued in order');
  FIFO_Free(q);

  { CFIFO: 100 elements starting from capacity 2 (forces multiple grows) }
  cq := CFIFO_New(sizeof(uint32), 2);
  for i := 0 to 99 do
  begin
    v := i;
    CFIFO_Enqueue(cq, @v);
  end;
  AssertEq(CFIFO_Size(cq), 100, 'STRESS: CFIFO 100 enqueued');

  good := true;
  for i := 0 to 99 do
  begin
    ok := CFIFO_Dequeue(cq, @r);
    if (not ok) or (r <> i) then good := false;
  end;
  Assert(good, 'STRESS: CFIFO 100 dequeued in order');
  CFIFO_Free(cq);

  { Min-Heap: 50 elements inserted in reverse, extracted in order }
  h := h_minh_New(sizeof(uint32), 4);
  for i := 50 downto 1 do
  begin
    v := i;
    h_minh_Insert(h, i, @v);
  end;
  AssertEq(h_minh_Size(h), 50, 'STRESS: MINH 50 inserted');

  good := true;
  for i := 1 to 50 do
  begin
    ok := h_minh_ExtractMin(h, @r);
    if (not ok) or (r <> i) then good := false;
  end;
  Assert(good, 'STRESS: MINH 50 extracted in ascending order');
  h_minh_Free(h);

  Section('--- STRESS done ---');
end;

{ ---------------------------------------------------------------------------- }
{  Public entry point                                                          }
{ ---------------------------------------------------------------------------- }

procedure test_RunAll;
begin
  TotalPass := 0;
  TotalFail := 0;

  syslog.logln(TAG, '========== Queue Tests Begin ==========');

  Test_FIFO;
  Test_CFIFO;
  Test_CFIFOLS;
  Test_LIFO;
  Test_CIRC;
  Test_MINH;
  Test_MAXH;
  Test_PRIO;
  Test_Stress;

  syslog.logln(TAG, '========== Queue Tests End ==========');
  syslog.log(TAG, '  Total PASS: ');
  syslog.writeintln(integer(TotalPass));
  syslog.log(TAG, '  Total FAIL: ');
  syslog.writeintln(integer(TotalFail));
end;

end.
