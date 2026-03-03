//  Copyright 2021 Kieron Morris
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
	Driver->Net->L3->ARP - Address Resolution Protocol Driver.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit arp;

interface

uses
    tracer, lmemorymanager,
    util, lists,
    net, nettypes, netutils,
    eth2, ipv4;

type
    PARPCacheRecord = ^TARPCacheRecord;
    TARPCacheRecord = record
        MAC : TMACAddress;
        IP  : TIPv4Address;
    end;

procedure register;
function  IPv4ToMAC(ip : puint8) : puint8;
function  MACToIIPv4(mac : puint8) : puint8;
procedure sendGratuitous;
procedure sendRequest(ip : puint8);
procedure send(hType : uint16; pType : uint16; op : uint16; p_context : PPacketContext);
function resolveIP(ip : puint8) : puint8;

implementation

uses
    stdio, strings;

var
    Registered : Boolean = false;
    Cache      : PLinkedListBase;

function findCacheRecordByMAC(mac : puint8) : PARPCacheRecord;
var
    i : uint32;
    r : PARPCacheRecord;

begin
    push_trace('arp.findCacheRecordByMAC');
    findCacheRecordByMAC:= nil;
    if LL_Size(Cache) > 0 then begin
        for i:=0 to LL_Size(Cache)-1 do begin
            r:= PARPCacheRecord(LL_Get(Cache, i));
            if MACEqual(mac, @r^.MAC[0]) then begin
                findCacheRecordByMAC:= r;
                break;
            end;
        end;
    end;
end;

function findCacheRecordByIP(ip : puint8) : PARPCacheRecord;
var
    i : uint32;
    r : PARPCacheRecord;

begin
    push_trace('arp.findCacheRecordByIP');
    findCacheRecordByIP:= nil;
    if LL_Size(Cache) > 0 then begin
        for i:=0 to LL_Size(Cache)-1 do begin
            r:= PARPCacheRecord(LL_Get(Cache, i));
            if IPEqual(ip, @r^.IP[0]) then begin
                findCacheRecordByIP:= r;
                break;
            end;
        end;
    end;
end;

procedure send(hType : uint16; pType : uint16; op : uint16; p_context : PPacketContext);
var
    buf : void;
    hdr : PARPHeader;
    hSize, pSize : uint8;

begin
    push_trace('arp.send');
    if p_context <> nil then begin
        buf:= kalloc(sizeof(TARPHeader));
        hdr:= PARPHeader(buf);
        case hType of
            $1 : hSize:= 6;
            else hSize:= 0;
        end;
        case pType of
            $0800 : pSize:= 4;
            else pSize:= 0;
        end;
        if (hSize > 0) and (pSize > 0) then begin
            hdr^.Hardware_Type_Hi:= hType SHR 8;
            hdr^.Hardware_Type_Lo:= hType AND $FF;
            hdr^.Protocol_Type_Hi:= pType SHR 8;
            hdr^.Protocol_Type_Lo:= pType AND $FF;
            hdr^.Hardware_Address_Length:= hSize;
            hdr^.Protocol_Address_Length:= pSize;
            hdr^.Operation_Hi:= op SHR 8;
            hdr^.Operation_Lo:= op AND $FF;
            copyMAC(@p_context^.MAC.Source[0], @hdr^.Source_Hardware[0]);
            //copyMAC(@FORCE_MAC[0], @hdr^.Source_Hardware[0]);
            copyIPv4(@p_context^.IP.Source[0], @hdr^.Source_Protocol[0]);
            copyMAC(@p_context^.MAC.Destination[0], @hdr^.Destination_Hardware[0]);
            copyIPv4(@p_context^.IP.Destination[0], @hdr^.Destination_Protocol[0]);
            if MACEqual(@p_context^.MAC.Destination[0], @NULL_MAC[0]) then begin
                CopyMAC(@BROADCAST_MAC[0], @p_context^.MAC.Destination[0]);
            end;
            eth2.send(buf, sizeof(TARPHeader), $0806, p_context);
        end;
        kfree(buf);
    end;
end;

procedure sendGratuitous;
var
    context : PPacketContext;

begin
     push_trace('arp.sendGratuitous');
     writeToLogLn('      L3/ARP: sendGratuitous');
     context:= newPacketContext;
     CopyIPv4(@getIPv4Config^.Address[0], @context^.IP.Destination[0]);
     CopyIPv4(@getIPv4Config^.Address[0], @context^.IP.Source[0]);
     CopyMAC(GetMAC, @context^.MAC.Source[0]);
     CopyMAC(@NULL_MAC[0], @context^.MAC.Destination[0]);
     arp.send($1, $0800, $1, context);
     freePacketContext(context);
end;

procedure sendRequestGateway(ip : puint8);
var
    context : PPacketContext;
    CacheRecord : PARPCacheRecord;

begin
     push_trace('arp.sendRequestGateway');
     context:= newPacketContext;
     CacheRecord:= findCacheRecordByIP(@getIPv4Config^.Gateway[0]);
     if CacheRecord <> nil then begin
        CopyMAC(@CacheRecord^.MAC[0], @context^.MAC.Destination[0]);
        CopyIPv4(ip, @context^.IP.Destination[0]);
        CopyIPv4(@getIPv4Config^.Address[0], @context^.IP.Source[0]);
        CopyMAC(GetMAC, @context^.MAC.Source[0]);
        arp.send($1, $0800, $1, context);
     end;
     freePacketContext(context);
end;

procedure sendRequest(ip : puint8);
var
    context : PPacketContext;
    CacheRecord : PARPCacheRecord;

begin
     push_trace('arp.sendRequest');
     writeToLogLn('      L3/ARP: sendRequest');
     context:= newPacketContext;
     CopyIPv4(ip, @context^.IP.Destination[0]);
     CopyIPv4(@getIPv4Config^.Address[0], @context^.IP.Source[0]);
     CopyMAC(GetMAC, @context^.MAC.Source[0]);
     CacheRecord:= findCacheRecordByIP(@getIPv4Config^.Gateway[0]);
     CopyMAC(@NULL_MAC[0], @context^.MAC.Destination[0]);
     arp.send($1, $0800, $1, context);
     freePacketContext(context);
     sendRequestGateway(ip);
end;

function resolveIP(ip : puint8) : puint8;
var
    CacheRecord : PARPCacheRecord;

begin
    push_trace('arp.resolveIP');
    CacheRecord:= findCacheRecordByIP(ip);
    resolveIP:= nil;
    if CacheRecord = nil then begin
        sendRequest(ip);
        sendRequestGateway(ip);
    end else begin
        resolveIP:= @CacheRecord^.MAC[0];
    end;
end;

procedure recv(p_data : void; p_len : uint16; p_context : PPacketContext);
var
    Header       : PARPHeader;
    AHeader      : TARPAbstractHeader;
    CacheElement : PARPCacheRecord;
    Merge        : boolean;
    context      : PPacketContext;

begin
    push_trace('arp.recv');
    { Get our converted Header }
    Header:= PARPHeader(p_data);
    AHeader.Hardware_Type:= (Header^.Hardware_Type_Hi SHL 8) + Header^.Hardware_Type_Lo;
    AHeader.Protocol_Type:= (Header^.Protocol_Type_Hi SHL 8) + Header^.Protocol_Type_Lo;
    AHeader.Hardware_Address_Length:= Header^.Hardware_Address_Length;
    AHeader.Protocol_Address_Length:= Header^.Protocol_Address_Length;
    AHeader.Operation:= (Header^.Operation_Hi SHL 8) + Header^.Operation_Lo;
    copyMAC(@Header^.Source_Hardware[0], @AHeader.Source_Hardware[0]);
    copyIPv4(@Header^.Source_Protocol[0], @AHeader.Source_Protocol[0]);
    copyMAC(@Header^.Destination_Hardware[0], @AHeader.Destination_Hardware[0]);
    copyIPv4(@Header^.Destination_Protocol[0], @AHeader.Destination_Protocol[0]);
    
    { Process ARP Packet }
    CacheElement:= findCacheRecordByIP(@AHeader.Source_Protocol[0]);
    if CacheElement = nil then CacheElement:= findCacheRecordByMAC(@AHeader.Source_Hardware[0]);
    if CacheElement <> nil then begin
        copyMAC(@AHeader.Source_Hardware[0], @CacheElement^.MAC[0]);
        copyIPv4(@AHeader.Source_Protocol[0], @CacheElement^.IP[0]);
    end else begin
        CacheElement:= PARPCacheRecord(LL_Add(Cache));
        CopyMAC(@AHeader.Source_Hardware[0], @CacheElement^.MAC[0]);
        copyIPv4(@AHeader.Source_Protocol[0], @CacheElement^.IP[0]);
    end;
    if IPEqual(@AHeader.Destination_Protocol[0], @getIPv4Config^.Address[0]) then begin
        case AHeader.Operation of
            $1:begin { ARP Request }
                context:= newPacketContext;
                copyMAC(@AHeader.Source_Hardware[0], @context^.MAC.Destination[0]);
                copyIPv4(@AHeader.Source_Protocol[0], @context^.IP.Destination[0]);
                copyMAC(getMAC, @context^.MAC.Source[0]);
                copyIPv4(@getIPv4Config^.Address[0], @context^.IP.Source[0]);
                send($1, $0800, $2, context);
                freePacketContext(context);
            end;
            $2:begin { ARP Reply }
                
            end;
            $3:begin { RARP Request }
                
            end;
            $4:begin { RARP Reply }
                
            end;
            $5:begin { DRARP Request }
                
            end;
            $6:begin { DRARP Reply }
                
            end;
            $7:begin { DRARP Error }
                
            end;
            $8:begin { InARP Request }
                
            end;
            $9:begin { InARP Reply }
                
            end;
        end;
    end;
end;

procedure terminal_command_arp(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    i : uint32;
    elm : PARPCacheRecord;
    sIP : pchar;
    _IP : puint8;

begin
    if ParamCount(Params) > 0 then begin
        sIP:= getParam(0, Params);
        _IP:= stringToIPv4(sIP);
        sendRequest(_IP);
        stdio.bufWriteStrLn(stdout_buf, 'ARP Request Sent.');
    end else begin
        if LL_Size(Cache) > 0 then begin
            stdio.bufWriteStrLn(stdout_buf, 'MAC                IPv4');
            For i:=0 to LL_Size(Cache)-1 do begin
                elm:= PARPCacheRecord(LL_Get(Cache, i));
                writeMACAddressEx(@elm^.MAC[0], stdout_buf);
                stdio.bufWriteStr(stdout_buf, '  ');
                writeIPv4AddressEx(@elm^.IP[0], stdout_buf);
                stdio.bufWriteStrLn(stdout_buf, ' ');
            end;
        end else begin
            stdio.bufWriteStrLn(stdout_buf, 'No entries in ARP table.');
        end;
    end;
end;

procedure register;
begin
    push_trace('arp.register');
    if not Registered then begin
        writeToLogLn('      L3/ARP: register');
        Cache:= LL_New(sizeof(TARPCacheRecord));
        eth2.registerTypePromisc($0806, @recv);
        stdio.registerCommand('ARP', @terminal_command_arp, 'Get ARP Table.');
        Registered:= true;
    end;
    pop_trace;
end;

function IPv4ToMAC(ip : puint8) : puint8;
var
     r : PARPCacheRecord;

begin
    push_trace('arp.IPv4ToMAC');
    register;
    IPv4ToMAC:= nil;
    r:= findCacheRecordByIP(ip);
    if r <> nil then begin
        IPv4ToMAC:= @r^.MAC[0];
    end;
    pop_trace;
end;

function MACToIIPv4(mac : puint8) : puint8;
var
     r : PARPCacheRecord;

begin
    push_trace('arp.MACToIPv4');
    register;
    MACToIIPv4:= nil;
    r:= findCacheRecordByMAC(mac);
    if r <> nil then begin
        MACToIIPv4:= @r^.IP[0];
    end;
    pop_trace;
end;

end.