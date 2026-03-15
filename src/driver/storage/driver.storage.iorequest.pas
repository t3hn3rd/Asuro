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
    driver.storage.types;

{ Allocate a new TIORequest from the fixed request pool and initialise its core fields.
  Caller, State, Error and ByteCount are zeroed (caller fills as needed). }
function  ioreq_alloc(reqType  : TIORequestType;
                      device   : PStorage_Device;
                      lba      : uint32;
                      sectors  : uint32;
                      buf      : pointer) : PIORequest;

{ Return a pooled TIORequest to the free list. Safe to call with nil. }
procedure ioreq_free(req : PIORequest);

{ Copy an existing TIORequest into a new pooled allocation (deep copy of the
  record, NOT the buffer it points to). Used by dispatch_next to create an
  ISR-safe copy from the CFIFO value-element. }
function  ioreq_copy(src : PIORequest) : PIORequest;

implementation

const
    IOREQ_POOL_CAPACITY = 512;
    IOREQ_REQ_OFFSET    = sizeof(pointer);

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
    base : uint32;
    node : PIORequestPoolNode;
begin
    if ioreqPoolReady then exit;

    ioreqPoolBuf := kalloc(IOREQ_POOL_CAPACITY * sizeof(TIORequestPoolNode));
    if ioreqPoolBuf = nil then exit;

    ioreqFreeList := nil;
    base := uint32(ioreqPoolBuf);
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
    node : PIORequestPoolNode;
begin
    if not ioreqPoolReady then
        ioreq_pool_init();
    if not ioreqPoolReady then begin
        ioreq_take := nil;
        exit;
    end;

    asm pushf; cli end;
    node := ioreqFreeList;
    if node <> nil then
        ioreqFreeList := node^.Next;
    asm popf end;

    if node = nil then
        ioreq_take := nil
    else
        ioreq_take := @node^.Req;
end;

procedure ioreq_release(req : PIORequest);
var
    node : PIORequestPoolNode;
begin
    if req = nil then exit;
    node := PIORequestPoolNode(uint32(req) - IOREQ_REQ_OFFSET);
    asm pushf; cli end;
    node^.Next := ioreqFreeList;
    ioreqFreeList := node;
    asm popf end;
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
    dst := ioreq_take();
    if dst = nil then begin
        ioreq_copy := nil;
        exit;
    end;
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

end.
