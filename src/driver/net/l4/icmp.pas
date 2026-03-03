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
unit icmp;

interface

uses
    bios_data_area,
    lmemorymanager, tracer,
    net, nettypes, netutils, ipv4, arp, util;

type
    TARPErrorCode     = (aecFailedToResolveHost, aecNoRouteToHost, aecTimeout, aecTTLExpired);
    TARPReplyCallback = procedure(hdr : PICMPHeader);
    TARPErrorCallback = procedure(hdr : PICMPHeader; Reason : TARPErrorCode);
    TARPHandler = record
        Active  : Boolean;
        OnReply : TARPReplyCallback;
        OnError : TARPErrorCallback;
    end;

procedure register;
procedure sendICMPRequest(ip : puint8; Sequence : uint16; TTL : uint8; OnRep : TARPReplyCallback; OnErr : TARPErrorCallback);

procedure ping_err(hdr : PICMPHeader; Reason : TARPErrorCode);
procedure ping_rep(hdr : PICMPHeader);

implementation

uses
    stdio, strings;

var
    Handlers : Array[0..255] of TARPHandler;

function nextInactiveHandler : uint8;
var
    i : uint8;

begin
    push_trace('icmp.nextInactiveHandler');
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

procedure sendICMPRequest(ip : puint8; Sequence : uint16; TTL : uint8; OnRep : TARPReplyCallback; OnErr : TARPErrorCallback);
var
    handle   : uint8;
    dest_mac : puint8;
    context  : PPacketContext;
    Header   : PICMPHeader;
    Buffer   : void;
    CHK      : uint16;
    Size     : uint32;

begin
    push_trace('icmp.sendICMPRequest');
    writeToLogLn('        L4/ICMP: sendICMPRequest');
    handle:= nextInactiveHandler;
    Handlers[handle].Active:= true;
    Handlers[handle].OnReply:= OnRep;
    Handlers[handle].OnError:= OnErr;
    if SameSubnetIPv4(ip, @getIPv4Config^.Address[0], @getIPv4Config^.Netmask[0]) then begin
        dest_mac:= arp.resolveIP(ip);
    end else begin
        dest_mac:= arp.resolveIP(@getIPv4Config^.Gateway[0]);
    end;
    if dest_mac = nil then begin
        if Handlers[handle].OnError <> nil then Handlers[handle].OnError(nil, aecFailedToResolveHost);
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

        ipv4.send(Buffer, size, context);
        
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
    push_trace('icmp.recv');
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
            ipv4.send(p_data, p_len, p_context);    
        end;
        $00:begin //Reply
            Handle:= Header^.Identifier;
            if (Handle > 0) and (Handle < 256) then begin
                If Handlers[Handle].Active then begin
                    If Handlers[Handle].OnReply <> nil then Handlers[Handle].OnReply(Header);
                    Handlers[Handle].Active:= false;
                    Handlers[Handle].OnError:= nil;
                    Handlers[Handle].OnReply:= nil;
                end;
            end;
        end;
    end; 
end;

var
    PING_T1  : uint64;
    PING_N   : uint16;
    PING_C   : uint16;
    PING_L   : uint32;
    PING_IP  : puint8;
    PING_STDOUT : POutBuf;
    PING_STDERR : POutBuf;

procedure ping_err(hdr : PICMPHeader; Reason : TARPErrorCode);
begin
    stdio.bufWriteStr(PING_STDERR, 'Ping Error: ');
    case Reason of
        aecFailedToResolveHost:stdio.bufWriteStrLn(PING_STDERR, 'Failed to resolve host.');
        aecNoRouteToHost:stdio.bufWriteStrLn(PING_STDERR, 'No route to host.');
        aecTimeout:stdio.bufWriteStrLn(PING_STDERR, 'Timeout expired.');
        aecTTLExpired:stdio.bufWriteStrLn(PING_STDERR, 'TTL Expired.');
    end;
    PING_T1:= Counters.c64;
    INC(PING_C);
    if PING_C < PING_N then begin
        sendICMPRequest(PING_IP, PING_C, 128, @ping_rep, @ping_err);
    end else begin
        stdio.done(PING_L);
    end;
end;

procedure ping_rep(hdr : PICMPHeader);
var
    PING_T2 : uint64;

begin
    PING_T2:= Counters.c64;
    stdio.bufWriteStr(PING_STDOUT, 'Ping Reply: ');
    stdio.bufWriteInt(PING_STDOUT, PING_T2-PING_T1);
    stdio.bufWriteStrLn(PING_STDOUT, 'ms.');
    PING_T1:= PING_T2;
    INC(PING_C);
    if PING_C < PING_N then begin
        sendICMPRequest(PING_IP, PING_C, 128, @ping_rep, @ping_err);
    end else begin
        stdio.done(PING_L);
    end;
end;

procedure ping_terminate();
begin
    PING_N:= 0;
end;

procedure terminal_command_ping(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    ip_str : pchar;
    ip : puint8;

begin
    if ParamCount(Params) > 0 then begin
        ip_str:= getParam(0, Params);
        ip:= stringToIPv4(ip_str);
        if ip <> nil then begin
            PING_STDOUT:= stdout_buf;
            PING_STDERR:= stderr_buf;
            stdio.halt(PING_L, @ping_terminate);
            PING_L:= Counters.c32;
            PING_N:= 10;
            PING_C:= 0;
            PING_T1:= Counters.c64;
            PING_IP:= ip;
            sendICMPRequest(PING_IP, PING_C, 128, @ping_rep, @ping_err); 
        end;
    end;
end;

procedure register;
var
    i : uint32;

begin
    push_trace('icmp.register');
    writeToLogLn('        L4/ICMP: register');
    for i:=0 to 255 do begin
        Handlers[i].Active:= false;
        Handlers[i].OnError:= nil;
        Handlers[i].OnReply:= nil;
    end;
    ipv4.registerProtocol($01, @recv);
    stdio.registerCommand('PING', @terminal_command_ping, 'Ping a host.');
end;

end.