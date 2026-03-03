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
	Driver->Net->L3->IPv4 - Internet Protocol Version 4 Driver.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit ipv4;

interface

uses
    tracer, lmemorymanager,
    util, strings,
    net, nettypes, netutils,
    lists,
    eth2;

procedure send(p_data : void; p_len : uint16; p_context : PPacketContext);
procedure registerProtocol(Protocol_ID : uint8; recv_callback : TRecvCallback);
function  getIPv4Config : PIPv4Configuration;
procedure register;

implementation

uses
    arp, stdio;

var
    Registered : Boolean = false;
    Protocols  : Array[0..255] of TRecvCallback;
    Config     : TIPv4Configuration;
    CurrentID  : uint16 = 0;

function  getIPv4Config : PIPv4Configuration;
begin
    push_trace('ipv4.getIPv4Config');
    getIPv4Config:= @Config;
    pop_trace;
end;

procedure send(p_data : void; p_len : uint16; p_context : PPacketContext);
var
    Header : TIPV4Header;
    Len    : uint16;
    CHK    : uint16;
    buffer : void;

begin
    push_trace('ipv4.send');
    inc(CurrentID);
    Header.version:= 4;
    Header.header_len:= 5;
    Header.ToS:= 0;
    Len:= 20 + p_len;
    Header.total_len_Hi:= Len SHR 8;
    Header.total_len_Lo:= Len AND $FF;
    Header.identifier_Hi:= CurrentID SHR 8;
    Header.identifier_Lo:= CurrentID AND $FF;
    Header.Flags:= 0;
    Header.Fragment_Off:= 0;
    Header.TTL:= p_context^.TTL;
    Header.Protocol:= p_context^.Protocol.L4 AND $FF;
    Header.HDR_CHK_Hi:= 0;
    Header.HDR_CHK_Lo:= 0;
    CopyIPv4(@getIPv4Config^.Address[0], @Header.Src[0]);
    CopyIPv4(@p_context^.IP.Destination[0], @Header.Dst[0]);
    Header.Options:= 0;
    Header.Padding:= 0;
    CHK:= calculateChecksum(puint16(@Header), sizeof(TIPV4Header));
    Header.HDR_CHK_Hi:= CHK AND $FF;//CHK SHR 8;
    Header.HDR_CHK_Lo:= CHK SHR 8;//CHK AND $FF;
    Buffer:= kalloc(Len);
    memcpy(uint32(@Header), uint32(Buffer), Header.header_len * 4);
    memcpy(uint32(p_data), uint32(Buffer) + (Header.header_len * 4), p_len);
    eth2.send(Buffer, (Header.header_len * 4) + p_len, $0800, p_context);
    kfree(Buffer);
    pop_trace;
end;

procedure recv(p_data : void; p_len : uint16; p_context : PPacketContext);
var
    Header  : PIPV4Header;
    AHeader : TIPV4AbstractHeader;
    i       : Integer;
    buf     : puint8;
    len     : uint16;

begin
    push_trace('ipv4.recv');
    Header:= PIPV4Header(p_data);
    AHeader.version:= Header^.version;
    AHeader.header_len:= Header^.header_len;
    AHeader.ToS:= Header^.ToS;
    AHeader.total_len:= (Header^.total_len_Hi SHL 8) + Header^.total_len_Lo;
    AHeader.identifier:= (Header^.identifier_Hi SHL 8) + Header^.identifier_Lo;
    AHeader.Flags.RS:= false;
    AHeader.Flags.DF:= (Header^.Flags AND $2) > 0;
    AHeader.Flags.MF:= (Header^.Flags AND $1) > 0;
    AHeader.Fragment_Off:= Header^.Fragment_Off;
    AHeader.TTL:= Header^.TTL;
    AHeader.Protocol:= Header^.Protocol;
    AHeader.HDR_CHK:= (Header^.HDR_CHK_Hi SHL 8) + Header^.HDR_CHK_Lo;
    for i:=0 to 3 do begin
        AHeader.Src[i]:= Header^.Src[i];
        AHeader.Dst[i]:= Header^.Dst[i];
    end;
    AHeader.Options:= Header^.Options;

    buf:= puint8(p_data);
    buf:= buf + (AHeader.header_len * 4);
    len:= p_len - (AHeader.header_len * 4);

    copyIPv4(@AHeader.Src[0], @p_context^.IP.Source[0]);
    copyIPv4(@AHeader.Dst[0], @p_context^.IP.Destination[0]);

    if Config.UP then begin
        if (IPEqual(@Config.Address[0], @AHeader.Dst[0])) OR (AHeader.Dst[3] = 255) OR (IPEqual(@Config.Address[0], @NULL_IP[0])) then begin
            if Protocols[AHeader.Protocol] <> nil then begin
                Protocols[AHeader.Protocol](void(buf), len, p_context);
            end;
        end;
    end;
    pop_trace;
end;

procedure terminal_command_ifconfig(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    Command, Sub, Address, Gateway, Netmask : pchar;
    _Address, _Gateway, _Netmask : puint8;
    Target : TIPv4Address;
    context : PPacketContext;
    i : uint32;

begin
    if paramCount(params) > 1 then begin
        Command:= GetParam(0, Params);
        if StringEquals(Command, 'set') then begin
            if paramCount(params) > 3 then begin
                Address:= GetParam(1, Params);
                Gateway:= GetParam(2, Params);
                Netmask:= GetParam(3, Params);
                _Address:= stringToIPv4(Address);
                _Gateway:= stringToIPv4(Gateway);
                _Netmask:= stringToIPv4(Netmask);
                copyIPv4(_Address, @Config.Address[0]);
                copyIPv4(_Gateway, @Config.Gateway[0]);
                copyIPv4(_Netmask, @Config.Netmask[0]);
                kfree(void(_Address));
                kfree(void(_Gateway));
                kfree(void(_Netmask));
            end else begin
                stdio.bufWriteStrLn(stderr_buf, 'Invalid number of params to call ''set''.');
            end;
        end;
        if StringEquals(Command, 'net') then begin
            Sub:= GetParam(1, Params);
            if StringEquals(Sub, 'up') then begin
                Config.UP:= true;
            end;
            if StringEquals(Sub, 'down') then begin
                Config.UP:= false;
            end;
        end;
        arp.sendGratuitous;
        CopyIPv4(@Config.Gateway[0], @Target[0]);
        arp.sendRequest(@Target[0]);
    end else begin
        stdio.bufWriteStr(stdout_buf, '   MAC:     ');
        writeMACAddress(net.GetMAC, stdout_buf);
        stdio.bufWriteStr(stdout_buf, '   IPv4:    ');
        writeIPv4Address(@Config.Address[0], stdout_buf);
        stdio.bufWriteStr(stdout_buf, '   Gateway: ');
        writeIPv4Address(@Config.Gateway[0], stdout_buf);
        stdio.bufWriteStr(stdout_buf, '   Netmask: ');
        writeIPv4Address(@Config.Netmask[0], stdout_buf);
        if Config.UP then 
            stdio.bufWriteStrLn(stdout_buf, '   NetUP:   true') 
        else 
            stdio.bufWriteStrLn(stdout_buf, '   NetUP:   false');
    end;
end;

procedure register;
var
    i : uint8;

begin
    push_trace('ipv4.register');
    if not Registered then begin
        writeToLogLn('      L3/IPv4: register');
        for i:=0 to 255 do begin
            Protocols[i]:= nil;
        end;
        for i:=0 to 3 do begin
            Config.Address[i]:= 0;
            Config.Gateway[i]:= 0;
            Config.Netmask[i]:= 0;
        end;
        Config.UP:= false;
        eth2.registerType($0800, @recv);
        stdio.registerCommand('IFCONFIG', @terminal_command_ifconfig, 'Configure Network Settings.');
        Registered:= true;
    end;
    pop_trace;
end;

procedure registerProtocol(Protocol_ID : uint8; recv_callback : TRecvCallback);
begin
    push_trace('ipv4.registerProtocol');
    register;
    if Protocols[Protocol_ID] = nil then Protocols[Protocol_ID]:= recv_callback;
    pop_trace;
end;

end.