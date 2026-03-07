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

    Provides heap allocation/free for TIORequest records used by the
    submit_io / complete_io path in storagemanager.pas.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit iorequest;

interface

uses
    lmemorymanager,
    storagetypes;

{ Allocate a new TIORequest on the heap and initialise its core fields.
  Caller, State, Error and ByteCount are zeroed (caller fills as needed). }
function  ioreq_alloc(reqType  : TIORequestType;
                      device   : PStorage_Device;
                      lba      : uint32;
                      sectors  : uint32;
                      buf      : pointer) : PIORequest;

{ Free a heap-allocated TIORequest. Safe to call with nil. }
procedure ioreq_free(req : PIORequest);

{ Copy an existing TIORequest into a new heap allocation (deep copy of the
  record, NOT the buffer it points to). Used by dispatch_next to create an
  ISR-safe copy from the CFIFO value-element. }
function  ioreq_copy(src : PIORequest) : PIORequest;

implementation

function ioreq_alloc(reqType  : TIORequestType;
                     device   : PStorage_Device;
                     lba      : uint32;
                     sectors  : uint32;
                     buf      : pointer) : PIORequest;
var
    req : PIORequest;
begin
    req := PIORequest(kalloc(SizeOf(TIORequest)));
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
    if req <> nil then
        kfree(void(req));
end;

function ioreq_copy(src : PIORequest) : PIORequest;
var
    dst : PIORequest;
begin
    dst := PIORequest(kalloc(SizeOf(TIORequest)));
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
