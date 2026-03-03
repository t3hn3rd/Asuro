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
	Queue Tests - Exercises every queue type and logs results via syslog.

	Call Q_TEST_RunAll to execute every test. Each test logs PASS or FAIL
	for individual assertions and a summary at the end.

	@author(Aaron Hance <ah@aaronhance.me>)
}
unit q_test;

interface

uses
    lmemorymanager,
    q_cfifo,
    q_cfifols,
    q_circ,
    q_fifo,
    q_heap,
    q_lifo,
    q_maxh,
    q_minh,
    q_prio,
    q_types,
    syslog,
    util;

{** Runs all queue tests. Logs results to syslog. **}
procedure Q_TEST_RunAll;

implementation

const
  TAG = 'Q_TEST';

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

  q := Q_FIFO_New(sizeof(uint32));
  Assert(q <> nil, 'FIFO: New returns non-nil');
  Assert(Q_FIFO_IsEmpty(q), 'FIFO: Initially empty');
  AssertEq(Q_FIFO_Size(q), 0, 'FIFO: Initial size is 0');

  { Enqueue 10, 20, 30 }
  v := 10; Q_FIFO_Enqueue(q, @v);
  v := 20; Q_FIFO_Enqueue(q, @v);
  v := 30; Q_FIFO_Enqueue(q, @v);
  AssertEq(Q_FIFO_Size(q), 3, 'FIFO: Size after 3 enqueues');
  Assert(not Q_FIFO_IsEmpty(q), 'FIFO: Not empty after enqueue');

  { Peek should return 10 }
  p := Q_FIFO_Peek(q);
  Assert(p <> nil, 'FIFO: Peek non-nil');
  AssertEq(p^, 10, 'FIFO: Peek returns first enqueued');

  { Dequeue should return 10, 20, 30 in order }
  ok := Q_FIFO_Dequeue(q, @r);
  Assert(ok, 'FIFO: Dequeue 1 succeeds');
  AssertEq(r, 10, 'FIFO: Dequeue 1 value');

  ok := Q_FIFO_Dequeue(q, @r);
  Assert(ok, 'FIFO: Dequeue 2 succeeds');
  AssertEq(r, 20, 'FIFO: Dequeue 2 value');

  ok := Q_FIFO_Dequeue(q, @r);
  Assert(ok, 'FIFO: Dequeue 3 succeeds');
  AssertEq(r, 30, 'FIFO: Dequeue 3 value');

  Assert(Q_FIFO_IsEmpty(q), 'FIFO: Empty after all dequeued');

  { Dequeue on empty should return false }
  ok := Q_FIFO_Dequeue(q, @r);
  Assert(not ok, 'FIFO: Dequeue on empty returns false');

  { Peek on empty should return nil }
  p := Q_FIFO_Peek(q);
  Assert(p = nil, 'FIFO: Peek on empty returns nil');

  Q_FIFO_Free(q);
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

  q := Q_CFIFO_New(sizeof(uint32), 4);
  Assert(q <> nil, 'CFIFO: New returns non-nil');
  Assert(Q_CFIFO_IsEmpty(q), 'CFIFO: Initially empty');
  AssertEq(Q_CFIFO_Size(q), 0, 'CFIFO: Initial size is 0');
  AssertEq(Q_CFIFO_Capacity(q), 4, 'CFIFO: Initial capacity is 4');

  { Enqueue 1..4 (fill initial capacity) }
  for i := 1 to 4 do
  begin
    v := i * 10;
    Q_CFIFO_Enqueue(q, @v);
  end;
  AssertEq(Q_CFIFO_Size(q), 4, 'CFIFO: Size after 4 enqueues');

  { Dequeue first two to advance Head }
  ok := Q_CFIFO_Dequeue(q, @r);
  Assert(ok, 'CFIFO: Dequeue 1 succeeds');
  AssertEq(r, 10, 'CFIFO: Dequeue 1 value');

  ok := Q_CFIFO_Dequeue(q, @r);
  Assert(ok, 'CFIFO: Dequeue 2 succeeds');
  AssertEq(r, 20, 'CFIFO: Dequeue 2 value');

  AssertEq(Q_CFIFO_Size(q), 2, 'CFIFO: Size after 2 dequeues');

  { Enqueue more to trigger compaction and/or growth }
  for i := 5 to 8 do
  begin
    v := i * 10;
    Q_CFIFO_Enqueue(q, @v);
  end;
  AssertEq(Q_CFIFO_Size(q), 6, 'CFIFO: Size after grow');

  { Verify FIFO order of remaining: 30, 40, 50, 60, 70, 80 }
  ok := Q_CFIFO_Dequeue(q, @r); AssertEq(r, 30, 'CFIFO: Order 30');
  ok := Q_CFIFO_Dequeue(q, @r); AssertEq(r, 40, 'CFIFO: Order 40');
  ok := Q_CFIFO_Dequeue(q, @r); AssertEq(r, 50, 'CFIFO: Order 50');
  ok := Q_CFIFO_Dequeue(q, @r); AssertEq(r, 60, 'CFIFO: Order 60');
  ok := Q_CFIFO_Dequeue(q, @r); AssertEq(r, 70, 'CFIFO: Order 70');
  ok := Q_CFIFO_Dequeue(q, @r); AssertEq(r, 80, 'CFIFO: Order 80');

  Assert(Q_CFIFO_IsEmpty(q), 'CFIFO: Empty after drain');

  { Peek on empty }
  p := Q_CFIFO_Peek(q);
  Assert(p = nil, 'CFIFO: Peek on empty returns nil');

  { Dequeue on empty }
  ok := Q_CFIFO_Dequeue(q, @r);
  Assert(not ok, 'CFIFO: Dequeue on empty returns false');

  Q_CFIFO_Free(q);
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

  ls := Q_CFIFOLS_New(2);
  Assert(ls <> nil, 'CFIFOLS: New returns non-nil');
  Assert(Q_CFIFOLS_IsEmpty(ls), 'CFIFOLS: Initially empty');
  AssertEq(Q_CFIFOLS_Count(ls), 0, 'CFIFOLS: Initial count is 0');

  q1 := Q_CFIFO_New(sizeof(uint32), 4);
  q2 := Q_CFIFO_New(sizeof(uint32), 4);
  q3 := Q_CFIFO_New(sizeof(uint32), 4);

  Q_CFIFOLS_Add(ls, q1);
  Q_CFIFOLS_Add(ls, q2);
  Q_CFIFOLS_Add(ls, q3);
  AssertEq(Q_CFIFOLS_Count(ls), 3, 'CFIFOLS: Count after 3 adds');

  got := Q_CFIFOLS_Get(ls, 0);
  Assert(got = q1, 'CFIFOLS: Get(0) returns q1');
  got := Q_CFIFOLS_Get(ls, 1);
  Assert(got = q2, 'CFIFOLS: Get(1) returns q2');
  got := Q_CFIFOLS_Get(ls, 2);
  Assert(got = q3, 'CFIFOLS: Get(2) returns q3');

  { Out-of-bounds }
  got := Q_CFIFOLS_Get(ls, 99);
  Assert(got = nil, 'CFIFOLS: Get out-of-bounds returns nil');

  { Remove middle }
  ok := Q_CFIFOLS_Remove(ls, 1);
  Assert(ok, 'CFIFOLS: Remove(1) succeeds');
  AssertEq(Q_CFIFOLS_Count(ls), 2, 'CFIFOLS: Count after remove');
  got := Q_CFIFOLS_Get(ls, 0);
  Assert(got = q1, 'CFIFOLS: After remove, Get(0) still q1');
  got := Q_CFIFOLS_Get(ls, 1);
  Assert(got = q3, 'CFIFOLS: After remove, Get(1) is now q3');

  { Remove out-of-bounds }
  ok := Q_CFIFOLS_Remove(ls, 99);
  Assert(not ok, 'CFIFOLS: Remove out-of-bounds returns false');

  { Free list only (not the queues) }
  Q_CFIFOLS_Free(ls);

  { Free queues we still own }
  Q_CFIFO_Free(q1);
  Q_CFIFO_Free(q2);
  Q_CFIFO_Free(q3);

  { Test FreeAll path }
  ls := Q_CFIFOLS_New(2);
  Q_CFIFOLS_Add(ls, Q_CFIFO_New(sizeof(uint32), 4));
  Q_CFIFOLS_Add(ls, Q_CFIFO_New(sizeof(uint32), 4));
  Q_CFIFOLS_FreeAll(ls);
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

  s := Q_LIFO_New(sizeof(uint32));
  Assert(s <> nil, 'LIFO: New returns non-nil');
  Assert(Q_LIFO_IsEmpty(s), 'LIFO: Initially empty');
  AssertEq(Q_LIFO_Size(s), 0, 'LIFO: Initial size is 0');

  { Push 10, 20, 30 }
  v := 10; Q_LIFO_Push(s, @v);
  v := 20; Q_LIFO_Push(s, @v);
  v := 30; Q_LIFO_Push(s, @v);
  AssertEq(Q_LIFO_Size(s), 3, 'LIFO: Size after 3 pushes');

  { Peek should return 30 (last pushed) }
  p := Q_LIFO_Peek(s);
  Assert(p <> nil, 'LIFO: Peek non-nil');
  AssertEq(p^, 30, 'LIFO: Peek returns last pushed');

  { Pop should return 30, 20, 10 (reverse order) }
  ok := Q_LIFO_Pop(s, @r);
  Assert(ok, 'LIFO: Pop 1 succeeds');
  AssertEq(r, 30, 'LIFO: Pop 1 value');

  ok := Q_LIFO_Pop(s, @r);
  Assert(ok, 'LIFO: Pop 2 succeeds');
  AssertEq(r, 20, 'LIFO: Pop 2 value');

  ok := Q_LIFO_Pop(s, @r);
  Assert(ok, 'LIFO: Pop 3 succeeds');
  AssertEq(r, 10, 'LIFO: Pop 3 value');

  Assert(Q_LIFO_IsEmpty(s), 'LIFO: Empty after all popped');

  ok := Q_LIFO_Pop(s, @r);
  Assert(not ok, 'LIFO: Pop on empty returns false');

  p := Q_LIFO_Peek(s);
  Assert(p = nil, 'LIFO: Peek on empty returns nil');

  Q_LIFO_Free(s);
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

  q := Q_CIRC_New(4, sizeof(uint32));
  Assert(q <> nil, 'CIRC: New returns non-nil');
  Assert(Q_CIRC_IsEmpty(q), 'CIRC: Initially empty');
  Assert(not Q_CIRC_IsFull(q), 'CIRC: Initially not full');
  AssertEq(Q_CIRC_Size(q), 0, 'CIRC: Initial size is 0');

  { Fill to capacity }
  for i := 1 to 4 do
  begin
    v := i * 100;
    ok := Q_CIRC_Enqueue(q, @v);
    Assert(ok, 'CIRC: Enqueue succeeds while not full');
  end;
  Assert(Q_CIRC_IsFull(q), 'CIRC: Full after 4 enqueues');
  AssertEq(Q_CIRC_Size(q), 4, 'CIRC: Size is 4 when full');

  { Enqueue when full should fail }
  v := 999;
  ok := Q_CIRC_Enqueue(q, @v);
  Assert(not ok, 'CIRC: Enqueue on full returns false');

  { Peek }
  p := Q_CIRC_Peek(q);
  Assert(p <> nil, 'CIRC: Peek non-nil');
  AssertEq(p^, 100, 'CIRC: Peek returns first enqueued');

  { Dequeue all — FIFO order }
  ok := Q_CIRC_Dequeue(q, @r); AssertEq(r, 100, 'CIRC: Dequeue 1 value');
  ok := Q_CIRC_Dequeue(q, @r); AssertEq(r, 200, 'CIRC: Dequeue 2 value');
  ok := Q_CIRC_Dequeue(q, @r); AssertEq(r, 300, 'CIRC: Dequeue 3 value');
  ok := Q_CIRC_Dequeue(q, @r); AssertEq(r, 400, 'CIRC: Dequeue 4 value');

  Assert(Q_CIRC_IsEmpty(q), 'CIRC: Empty after all dequeued');

  ok := Q_CIRC_Dequeue(q, @r);
  Assert(not ok, 'CIRC: Dequeue on empty returns false');

  p := Q_CIRC_Peek(q);
  Assert(p = nil, 'CIRC: Peek on empty returns nil');

  { Wrap-around: enqueue 2, dequeue 1, repeat — exercises ring buffer }
  v := 1; Q_CIRC_Enqueue(q, @v);
  v := 2; Q_CIRC_Enqueue(q, @v);
  Q_CIRC_Dequeue(q, @r);                  { dequeue 1 }
  v := 3; Q_CIRC_Enqueue(q, @v);
  v := 4; Q_CIRC_Enqueue(q, @v);
  Q_CIRC_Dequeue(q, @r); AssertEq(r, 2, 'CIRC: Wraparound order 2');
  Q_CIRC_Dequeue(q, @r); AssertEq(r, 3, 'CIRC: Wraparound order 3');
  Q_CIRC_Dequeue(q, @r); AssertEq(r, 4, 'CIRC: Wraparound order 4');
  Assert(Q_CIRC_IsEmpty(q), 'CIRC: Empty after wraparound');

  Q_CIRC_Free(q);
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

  h := Q_MINH_New(sizeof(uint32), 4);
  Assert(h <> nil, 'MINH: New returns non-nil');
  Assert(Q_MINH_IsEmpty(h), 'MINH: Initially empty');
  AssertEq(Q_MINH_Size(h), 0, 'MINH: Initial size is 0');

  { Insert out of order }
  v := 30; Q_MINH_Insert(h, 30, @v);
  v := 10; Q_MINH_Insert(h, 10, @v);
  v := 50; Q_MINH_Insert(h, 50, @v);
  v := 20; Q_MINH_Insert(h, 20, @v);
  v := 40; Q_MINH_Insert(h, 40, @v);
  AssertEq(Q_MINH_Size(h), 5, 'MINH: Size after 5 inserts');

  { Peek should return min (10) }
  p := Q_MINH_PeekMin(h);
  Assert(p <> nil, 'MINH: PeekMin non-nil');
  AssertEq(p^, 10, 'MINH: PeekMin returns 10');

  { Extract all — should come out in ascending order }
  ok := Q_MINH_ExtractMin(h, @r); Assert(ok, 'MINH: Extract 1 ok'); AssertEq(r, 10, 'MINH: Extract 10');
  ok := Q_MINH_ExtractMin(h, @r); Assert(ok, 'MINH: Extract 2 ok'); AssertEq(r, 20, 'MINH: Extract 20');
  ok := Q_MINH_ExtractMin(h, @r); Assert(ok, 'MINH: Extract 3 ok'); AssertEq(r, 30, 'MINH: Extract 30');
  ok := Q_MINH_ExtractMin(h, @r); Assert(ok, 'MINH: Extract 4 ok'); AssertEq(r, 40, 'MINH: Extract 40');
  ok := Q_MINH_ExtractMin(h, @r); Assert(ok, 'MINH: Extract 5 ok'); AssertEq(r, 50, 'MINH: Extract 50');

  Assert(Q_MINH_IsEmpty(h), 'MINH: Empty after all extracted');

  ok := Q_MINH_ExtractMin(h, @r);
  Assert(not ok, 'MINH: Extract on empty returns false');

  p := Q_MINH_PeekMin(h);
  Assert(p = nil, 'MINH: PeekMin on empty returns nil');

  Q_MINH_Free(h);
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

  h := Q_MAXH_New(sizeof(uint32), 4);
  Assert(h <> nil, 'MAXH: New returns non-nil');
  Assert(Q_MAXH_IsEmpty(h), 'MAXH: Initially empty');

  v := 30; Q_MAXH_Insert(h, 30, @v);
  v := 10; Q_MAXH_Insert(h, 10, @v);
  v := 50; Q_MAXH_Insert(h, 50, @v);
  v := 20; Q_MAXH_Insert(h, 20, @v);
  v := 40; Q_MAXH_Insert(h, 40, @v);
  AssertEq(Q_MAXH_Size(h), 5, 'MAXH: Size after 5 inserts');

  { Peek should return max (50) }
  p := Q_MAXH_PeekMax(h);
  Assert(p <> nil, 'MAXH: PeekMax non-nil');
  AssertEq(p^, 50, 'MAXH: PeekMax returns 50');

  { Extract all — should come out in descending order }
  ok := Q_MAXH_ExtractMax(h, @r); Assert(ok, 'MAXH: Extract 1 ok'); AssertEq(r, 50, 'MAXH: Extract 50');
  ok := Q_MAXH_ExtractMax(h, @r); Assert(ok, 'MAXH: Extract 2 ok'); AssertEq(r, 40, 'MAXH: Extract 40');
  ok := Q_MAXH_ExtractMax(h, @r); Assert(ok, 'MAXH: Extract 3 ok'); AssertEq(r, 30, 'MAXH: Extract 30');
  ok := Q_MAXH_ExtractMax(h, @r); Assert(ok, 'MAXH: Extract 4 ok'); AssertEq(r, 20, 'MAXH: Extract 20');
  ok := Q_MAXH_ExtractMax(h, @r); Assert(ok, 'MAXH: Extract 5 ok'); AssertEq(r, 10, 'MAXH: Extract 10');

  Assert(Q_MAXH_IsEmpty(h), 'MAXH: Empty after all extracted');

  ok := Q_MAXH_ExtractMax(h, @r);
  Assert(not ok, 'MAXH: Extract on empty returns false');

  p := Q_MAXH_PeekMax(h);
  Assert(p = nil, 'MAXH: PeekMax on empty returns nil');

  Q_MAXH_Free(h);
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

  h := Q_PRIO_New(sizeof(uint32), 4);
  Assert(h <> nil, 'PRIO: New returns non-nil');
  Assert(Q_PRIO_IsEmpty(h), 'PRIO: Initially empty');

  { Enqueue with varying priorities (lower value = higher priority) }
  v := 300; Q_PRIO_Enqueue(h, 3, @v);
  v := 100; Q_PRIO_Enqueue(h, 1, @v);
  v := 500; Q_PRIO_Enqueue(h, 5, @v);
  v := 200; Q_PRIO_Enqueue(h, 2, @v);
  v := 400; Q_PRIO_Enqueue(h, 4, @v);
  AssertEq(Q_PRIO_Size(h), 5, 'PRIO: Size after 5 enqueues');

  { Peek should return highest priority (lowest value = 1 -> data 100) }
  p := Q_PRIO_Peek(h);
  Assert(p <> nil, 'PRIO: Peek non-nil');
  AssertEq(p^, 100, 'PRIO: Peek returns data with priority 1');

  { Dequeue all — should come out by priority 1, 2, 3, 4, 5 }
  ok := Q_PRIO_Dequeue(h, @r); Assert(ok, 'PRIO: Dequeue 1 ok'); AssertEq(r, 100, 'PRIO: Dequeue pri=1');
  ok := Q_PRIO_Dequeue(h, @r); Assert(ok, 'PRIO: Dequeue 2 ok'); AssertEq(r, 200, 'PRIO: Dequeue pri=2');
  ok := Q_PRIO_Dequeue(h, @r); Assert(ok, 'PRIO: Dequeue 3 ok'); AssertEq(r, 300, 'PRIO: Dequeue pri=3');
  ok := Q_PRIO_Dequeue(h, @r); Assert(ok, 'PRIO: Dequeue 4 ok'); AssertEq(r, 400, 'PRIO: Dequeue pri=4');
  ok := Q_PRIO_Dequeue(h, @r); Assert(ok, 'PRIO: Dequeue 5 ok'); AssertEq(r, 500, 'PRIO: Dequeue pri=5');

  Assert(Q_PRIO_IsEmpty(h), 'PRIO: Empty after all dequeued');

  ok := Q_PRIO_Dequeue(h, @r);
  Assert(not ok, 'PRIO: Dequeue on empty returns false');

  p := Q_PRIO_Peek(h);
  Assert(p = nil, 'PRIO: Peek on empty returns nil');

  Q_PRIO_Free(h);
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
  q := Q_FIFO_New(sizeof(uint32));
  for i := 0 to 99 do
  begin
    v := i;
    Q_FIFO_Enqueue(q, @v);
  end;
  AssertEq(Q_FIFO_Size(q), 100, 'STRESS: FIFO 100 enqueued');

  good := true;
  for i := 0 to 99 do
  begin
    ok := Q_FIFO_Dequeue(q, @r);
    if (not ok) or (r <> i) then good := false;
  end;
  Assert(good, 'STRESS: FIFO 100 dequeued in order');
  Q_FIFO_Free(q);

  { CFIFO: 100 elements starting from capacity 2 (forces multiple grows) }
  cq := Q_CFIFO_New(sizeof(uint32), 2);
  for i := 0 to 99 do
  begin
    v := i;
    Q_CFIFO_Enqueue(cq, @v);
  end;
  AssertEq(Q_CFIFO_Size(cq), 100, 'STRESS: CFIFO 100 enqueued');

  good := true;
  for i := 0 to 99 do
  begin
    ok := Q_CFIFO_Dequeue(cq, @r);
    if (not ok) or (r <> i) then good := false;
  end;
  Assert(good, 'STRESS: CFIFO 100 dequeued in order');
  Q_CFIFO_Free(cq);

  { Min-Heap: 50 elements inserted in reverse, extracted in order }
  h := Q_MINH_New(sizeof(uint32), 4);
  for i := 50 downto 1 do
  begin
    v := i;
    Q_MINH_Insert(h, i, @v);
  end;
  AssertEq(Q_MINH_Size(h), 50, 'STRESS: MINH 50 inserted');

  good := true;
  for i := 1 to 50 do
  begin
    ok := Q_MINH_ExtractMin(h, @r);
    if (not ok) or (r <> i) then good := false;
  end;
  Assert(good, 'STRESS: MINH 50 extracted in ascending order');
  Q_MINH_Free(h);

  Section('--- STRESS done ---');
end;

{ ---------------------------------------------------------------------------- }
{  Public entry point                                                          }
{ ---------------------------------------------------------------------------- }

procedure Q_TEST_RunAll;
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
