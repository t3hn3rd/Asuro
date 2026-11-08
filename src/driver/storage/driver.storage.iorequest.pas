//  Copyright 2021 Aaron Hance
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
    Driver->Storage->IORequest - I/O request allocation and lifecycle helpers.

    Provides fixed-pool allocation/free for TIORequest records used by the
    submit_io / complete_io path in driver.storage.mgr.pas.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit driver.storage.iorequest;

interface

uses
    memory.heap,
    arch.platform.cpu,
    arch.platform.diagnostics,
    driver.storage.types;

{ Allocate a new TIORequest from the fixed request pool and initialise its core fields.
  Caller, State, Error and ByteCount are zeroed (caller fills as needed). }
procedure UnitTest;

function  ioreq_alloc(reqType  : TIORequestType;
                      device   : PStorage_Device;
                      lba      : uint32;
                      sectors  : uint32;
                      buf      : pointer) : PIORequest;

{ Return a pooled TIORequest to the free list. Safe to call with nil. }
procedure ioreq_free(req : PIORequest);

{ Copy an existing TIORequest into a new pooled allocation (deep copy of the
  record, NOT the buffer it points to). Used by submit_io before enqueueing
  the owned pointer. Manager-only merge/timing fields are initialised here. }
function  ioreq_copy(src : PIORequest) : PIORequest;

implementation

const
    IOREQ_POOL_CAPACITY = 512;

type
    PIORequestPoolNode = ^TIORequestPoolNode;
    TIORequestPoolNode = record
        Next : PIORequestPoolNode;
        Req  : TIORequest;
    end;

var
    ioreqPoolReady : boolean;
    ioreqPoolBuf   : pointer;
    ioreqFreeList  : PIORequestPoolNode;

procedure ioreq_pool_init();
var
    i    : uint32;
    base : PtrUInt;
    node : PIORequestPoolNode;
begin
    if ioreqPoolReady then exit;

    ioreqPoolBuf := kalloc(IOREQ_POOL_CAPACITY * sizeof(TIORequestPoolNode));
    if ioreqPoolBuf = nil then exit;

    ioreqFreeList := nil;
    base := PtrUInt(ioreqPoolBuf);
    if IOREQ_POOL_CAPACITY > 0 then
        for i := 0 to IOREQ_POOL_CAPACITY - 1 do begin
            node := PIORequestPoolNode(base + (i * sizeof(TIORequestPoolNode)));
            node^.Next := ioreqFreeList;
            ioreqFreeList := node;
        end;

    ioreqPoolReady := true;
end;

function ioreq_take() : PIORequest;
var
    node: PIORequestPoolNode;
    flags: PtrUInt;
begin
    ioreq_take := nil;
    flags := arch.platform.cpu.lock;
    if not ioreqPoolReady then ioreq_pool_init;
    node := ioreqFreeList;
    if node <> nil then begin
        ioreqFreeList := node^.Next;
        ioreq_take := @node^.Req;
    end;
    arch.platform.cpu.unlock(flags);
end;

procedure ioreq_release(req : PIORequest);
var
    node: PIORequestPoolNode;
    flags: PtrUInt;
begin
    if req = nil then exit;
    node := PIORequestPoolNode(PtrUInt(req) - PtrUInt(@PIORequestPoolNode(nil)^.Req));
    flags := arch.platform.cpu.lock;
    node^.Next := ioreqFreeList;
    ioreqFreeList := node;
    arch.platform.cpu.unlock(flags);
end;

function ioreq_alloc(reqType  : TIORequestType;
                     device   : PStorage_Device;
                     lba      : uint32;
                     sectors  : uint32;
                     buf      : pointer) : PIORequest;
var
    req : PIORequest;
begin
    req := ioreq_take();
    if req = nil then begin
        ioreq_alloc := nil;
        exit;
    end;
    req^.MergeNext := nil;
    req^.OriginalSectors := sectors;
    req^.QueuedTick := 0;
    req^.DispatchTick := 0;
    req^.RequestType := reqType;
    req^.State       := iosPending;
    req^.Device      := device;
    req^.LBA         := lba;
    req^.SectorCount := sectors;
    req^.Buffer      := buf;
    req^.ByteCount   := 0;
    req^.Error       := eNone;
    req^.Caller      := nil;
    req^.UserData    := nil;
    req^.Callback    := nil;
    req^.CallbackData := nil;
    ioreq_alloc := req;
end;

procedure ioreq_free(req : PIORequest);
begin
    ioreq_release(req);
end;

function ioreq_copy(src : PIORequest) : PIORequest;
var
    dst : PIORequest;
begin
    ioreq_copy := nil;
    if src = nil then exit;
    dst := ioreq_take();
    if dst = nil then begin
        ioreq_copy := nil;
        exit;
    end;
    dst^.MergeNext := nil;
    dst^.OriginalSectors := src^.SectorCount;
    dst^.QueuedTick := 0;
    dst^.DispatchTick := 0;
    dst^.RequestType := src^.RequestType;
    dst^.State       := src^.State;
    dst^.Device      := src^.Device;
    dst^.LBA         := src^.LBA;
    dst^.SectorCount := src^.SectorCount;
    dst^.Buffer      := src^.Buffer;
    dst^.ByteCount   := src^.ByteCount;
    dst^.Error       := src^.Error;
    dst^.Caller      := src^.Caller;
    dst^.UserData    := src^.UserData;
    dst^.Callback    := src^.Callback;
    dst^.CallbackData := src^.CallbackData;
    ioreq_copy := dst;
end;

procedure testCallback(error: TError; data: pointer);
begin
    if error = eNone then inc(PUInt32(data)^);
end;

procedure UnitTest;
var
    head, req, next, copyReq: PIORequest;
    payload: PUInt32;
    count, passed, failed: uint32;
    flags: PtrUInt;

    procedure Assert(condition: boolean);
    begin
        if condition then
            inc(passed)
        else
            inc(failed);
    end;
begin
    passed := 0;
    failed := 0;
    flags := arch.platform.cpu.lock;
    head := nil;
    count := 0;
    repeat
        req := ioreq_alloc(ioRead, nil, count, 1, nil);
        if req = nil then break;
        req^.MergeNext := head;
        head := req;
        inc(count);
    until count = IOREQ_POOL_CAPACITY;
    Assert((count > 0) and (ioreq_alloc(ioRead, nil, 0, 1, nil) = nil));
    while head <> nil do begin
        next := head^.MergeNext;
        ioreq_free(head);
        head := next;
    end;

    payload := PUInt32(kalloc(sizeof(uint32)));
    req := ioreq_alloc(ioRead, nil, 123, 2, payload);
    if (payload <> nil) and (req <> nil) then begin
        req^.Callback := @testCallback;
        req^.CallbackData := payload;
        copyReq := ioreq_copy(req);
        if copyReq <> nil then begin
            Assert((copyReq <> req) and (copyReq^.Buffer = payload) and
                (copyReq^.LBA = 123) and (copyReq^.OriginalSectors = 2));
            copyReq^.Callback(eNone, copyReq^.CallbackData);
            Assert(payload^ = 1);
            ioreq_free(copyReq);
        end else
            inc(failed);
    end else
        inc(failed);
    ioreq_free(req);
    kfree(void(payload));
    Assert(ioreq_copy(nil) = nil);
    arch.platform.cpu.unlock(flags);
    testSummary('IOREQ', 'IOREQ_TESTS_PASSED', 'IOREQ_TESTS_FAILED', passed, failed);
end;

end.
