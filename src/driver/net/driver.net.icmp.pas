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
	Driver->Net->L4->ICMP - Internet Control Message Protocol Driver,
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.net.icmp;

interface

uses
    arch.x86.bda,
    memory.heap, debug.tracer,
    driver.net, driver.net.types, driver.net.util, driver.net.ipv4, driver.net.arp, core.util, arch.x86.util;

type
    TARPErrorCode     = (aecFailedToResolveHost, aecNoRouteToHost, aecTimeout, aecTTLExpired);
    TARPReplyCallback = procedure(hdr : PICMPHeader; userData : void);
    TARPErrorCallback = procedure(hdr : PICMPHeader; Reason : TARPErrorCode; userData : void);
    TARPHandler = record
        Active   : Boolean;
        OnReply  : TARPReplyCallback;
        OnError  : TARPErrorCallback;
        UserData : void;
    end;

procedure register;
procedure sendICMPRequest(ip : puint8; Sequence : uint16; TTL : uint8; OnRep : TARPReplyCallback; OnErr : TARPErrorCallback; userData : void);

implementation

var
    Handlers : Array[0..255] of TARPHandler;

function nextInactiveHandler : uint8;
var
    i : uint8;

begin
    push_trace('driver.net.icmp.nextInactiveHandler');
    nextInactiveHandler:= 0;
    for i:=1 to 255 do begin
        if not Handlers[i].Active then begin
            nextInactiveHandler:= i;
            break;
        end;
    end;
end;

procedure sendResponse(p_context : PPacketContext);
begin

end;

procedure sendICMPRequest(ip : puint8; Sequence : uint16; TTL : uint8; OnRep : TARPReplyCallback; OnErr : TARPErrorCallback; userData : void);
var
    handle   : uint8;
    dest_mac : puint8;
    context  : PPacketContext;
    Header   : PICMPHeader;
    Buffer   : void;
    CHK      : uint16;
    Size     : uint32;

begin
    push_trace('driver.net.icmp.sendICMPRequest');
    writeToLogLn('        L4/ICMP: sendICMPRequest');
    handle:= nextInactiveHandler;
    Handlers[handle].Active:= true;
    Handlers[handle].OnReply:= OnRep;
    Handlers[handle].OnError:= OnErr;
    Handlers[handle].UserData:= userData;
    if SameSubnetIPv4(ip, @getIPv4Config^.Address[0], @getIPv4Config^.Netmask[0]) then begin
        dest_mac:= driver.net.arp.resolveIP(ip);
    end else begin
        dest_mac:= driver.net.arp.resolveIP(@getIPv4Config^.Gateway[0]);
    end;
    if dest_mac = nil then begin
        if Handlers[handle].OnError <> nil then Handlers[handle].OnError(nil, aecFailedToResolveHost, Handlers[handle].UserData);
        Handlers[handle].Active:= false;
    end else begin
        context:= newPacketContext;
        copyMAC(getMAC, @context^.MAC.Source[0]);
        copyIPv4(@getIPv4Config^.Address[0], @context^.IP.Source[0]);
        copyMAC(dest_mac, @context^.MAC.Destination[0]);
        copyIPv4(ip, @context^.IP.Destination[0]);
        context^.TTL:= TTL;
        context^.Protocol.L4:= $01;

        Size:= sizeof(TICMPHeader) + sizeof(ICMP_DATA_GENERIC);
        Buffer:= kalloc(Size);
        Header:= PICMPHeader(Buffer);
        Header^.ICMP_Type:= $08;
        Header^.ICMP_CHK_Hi:= 0;
        Header^.ICMP_CHK_Lo:= 0;
        Header^.Identifier:= handle;
        Header^.Sequence:= Sequence;

        memcpy(uint32(@ICMP_DATA_GENERIC[0]), uint32(Buffer) + sizeof(TICMPHeader), sizeof(ICMP_DATA_GENERIC));

        CHK:= calculateChecksum(puint16(Buffer), Size);

        Header^.ICMP_CHK_Hi:= CHK AND $FF;
        Header^.ICMP_CHK_Lo:= CHK SHR 8;

        driver.net.ipv4.send(Buffer, size, context);
        
        freePacketContext(context);
    end;
end;

{procedure sendRequest(ip : puint8);
begin

end;}

procedure recv(p_data : void; p_len : uint16; p_context : PPacketContext);
var
    Header : PICMPHeader;
    CHK    : uint16;
    Handle : uint8;

begin
    push_trace('driver.net.icmp.recv');
    writeToLogLn('        L4/ICMP: recv');
    Header:= PICMPHeader(p_data);
    //writehexlnWND(Header^.ICMP_Type, getTerminalHWND); 
    case Header^.ICMP_Type of
        $08:Begin //Request
            contextMACSwitch(p_context);
            contextIPv4Switch(p_context);
            Header^.ICMP_Type:= 0;
            Header^.ICMP_CHK_Hi:= 0;
            Header^.ICMP_CHK_Lo:= 0;
            CHK:= calculateChecksum(puint16(p_data), p_len);
            Header^.ICMP_CHK_Hi:= CHK AND $FF;
            Header^.ICMP_CHK_Lo:= CHK SHR 8;
            p_context^.Protocol.L4:= $01;
            p_context^.TTL:= 128;
            driver.net.ipv4.send(p_data, p_len, p_context);    
        end;
        $00:begin //Reply
            Handle:= Header^.Identifier;
            if (Handle > 0) and (Handle < 256) then begin
                If Handlers[Handle].Active then begin
                    If Handlers[Handle].OnReply <> nil then Handlers[Handle].OnReply(Header, Handlers[Handle].UserData);
                    Handlers[Handle].Active:= false;
                    Handlers[Handle].OnError:= nil;
                    Handlers[Handle].OnReply:= nil;
                    Handlers[Handle].UserData:= nil;
                end;
            end;
        end;
    end; 
end;

procedure register;
var
    i : uint32;

begin
    push_trace('driver.net.icmp.register');
    writeToLogLn('        L4/ICMP: register');
    for i:=0 to 255 do begin
        Handlers[i].Active:= false;
        Handlers[i].OnError:= nil;
        Handlers[i].OnReply:= nil;
        Handlers[i].UserData:= nil;
    end;
    driver.net.ipv4.registerProtocol($01, @recv);
end;

end.