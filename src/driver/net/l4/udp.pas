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
	Driver->Net->L4->UDP - User Datagram Protocol Driver.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit udp;

interface

uses
    lmemorymanager,
    nettypes, netutils,
    ipv4, netlog, net,
    util;

procedure register();
function bind(bindContext : PUDPBindContext) : TUDPError;
function unbind(bindContext : PUDPBindContext) : TUDPError;
procedure send(p_data : void; p_len : uint16; udpContext : PUDPSendContext);

implementation

uses
    console, terminal;

var
    Ports : Array[0..65535] of PUDPBindContext;

function CalculateChecksum(p_data : void; p_len : uint16; udpContext : PUDPSendContext) : uint16;
var
    pseudoBuffer    : void;
    pseudoBuffer32  : puint32;
    pseudoBuffer16  : puint16;
    pseudoBuffer8   : puint8;
    pseudoSize      : uint16;
    nullend         : boolean;
    pseudoHeader    : PUDPPseudoHeader;
    pseduoSrc       : uint16;
    i               : uint16;
    Checksum_u      : uint32;
    Checksum_c      : uint16;
    Checksum_f      : uint16;
    size            : uint16;

begin
        size:= p_len + sizeof(TUDPHeader);
        //Checksum
        if udpContext^.socket <> nil then begin
            pseduoSrc:= udpContext^.socket^.Port;
        end else begin
            pseduoSrc:= 0;
        end;
        nullend:= false;
        pseudoSize:= p_len;
        if (pseudoSize mod 2) = 1 then begin
            pseudoSize:= pseudoSize + 1;
            nullend:= true;
        end;
        pseudoBuffer:= kalloc(sizeof(TUDPPseudoHeader) + pseudoSize);
        pseudoBuffer8:= puint8(pseudoBuffer);
        pseudoBuffer16:= puint16(pseudoBuffer);
        pseudoBuffer32:= puint32(pseudoBuffer);
        pseudoHeader:= PUDPPseudoHeader(pseudoBuffer);
        copyIPv4(puint8(@udpContext^.context^.IP.Source[0]), puint8(@pseudoBuffer8[0]));
        copyIPv4(puint8(@udpContext^.context^.IP.Destination[0]), puint8(@pseudoBuffer8[4]));
        pseudoHeader^.Protocol:= $11;
        pseudoHeader^.Length:= pseudoSize + sizeof(TUDPHeader);
        pseudoHeader^.UDP_Source:= pseduoSrc;
        pseudoHeader^.UDP_Destination:= udpContext^.DstPort;
        pseudoHeader^.UDP_Length:= size;
        memcpy(uint32(p_data), uint32(pseudoBuffer) + SizeOf(TUDPPseudoHeader), p_len);
        if nullend then pseudoBuffer8[pseudoSize-1]:= 0;
        
        pseudoHeader^.Source_IP:= switchendian32(pseudoHeader^.Source_IP);
        pseudoHeader^.Destination_IP:= switchendian32(pseudoHeader^.Destination_IP);

        Checksum_u:= 0;

        for i:=0 to (SizeOf(TUDPPseudoHeader) div 2)-1 do begin
            Checksum_u:= Checksum_u + pseudoBuffer16[i];
        end;

        for i:=(SizeOf(TUDPPseudoHeader) div 2) to ((pseudoSize + SizeOf(TUDPPseudoHeader)) div 2) - 1 do begin
            Checksum_u:= Checksum_u + switchendian16(pseudoBuffer16[i]);
        end;

        Checksum_f:= Checksum_u AND $FFFF;
        Checksum_c:= (Checksum_u AND $FFFF0000) SHR 16;
        Checksum_f:= Checksum_f + Checksum_c;
        Checksum_f:= not Checksum_f; 
        CalculateChecksum:= Checksum_f; 

        kfree(pseudoBuffer);

end;

procedure send(p_data : void; p_len : uint16; udpContext : PUDPSendContext);
var
    buffer      : void;
    hdr         : PUDPHeader;
    size        : uint16;
    checksum    : uint16;
    i           : uint16;


begin
    if udpContext <> nil then begin
        size:= p_len + sizeof(TUDPHeader);
        buffer:= kalloc(size);
        hdr:= PUDPHeader(kalloc(sizeof(TUDPHeader)));
        if udpContext^.socket <> nil then begin
            hdr^.SrcPort:= switchendian16(udpContext^.socket^.Port);
        end else begin
            hdr^.SrcPort:= 0;
        end;
        hdr^.DstPort:= switchendian16(udpContext^.DstPort);

        checksum:= CalculateChecksum(p_data, p_len, udpContext);

        hdr^.Checksum:= switchendian16(checksum);
        hdr^.Length:= switchendian16(size);
 
        memcpy(uint32(hdr), uint32(buffer), sizeof(TUDPHeader));
        memcpy(uint32(p_data), uint32(buffer) + sizeof(TUDPHeader), p_len); 

        udpContext^.context^.Protocol.L4:= $11;       

        ipv4.send(buffer, size, udpContext^.context);

        kfree(buffer);
        kfree(void(hdr));
    end;
end;

function bind(bindContext : PUDPBindContext) : TUDPError;
var
    result  : TUDPError;
    context : PUDPBindContext;

begin
    result:= tueGenericError;
    if bindContext <> nil then begin
        if Ports[bindContext^.port] = nil then begin
            context:= PUDPBindContext(kalloc(sizeof(TUDPBindContext)));
            context^.Port:= bindContext^.port;
            context^.Callback:= bindContext^.Callback;
            context^.UID:= bindContext^.UID;
            Ports[context^.Port]:= context;
            result:= tueOK;
        end else begin
            result:= tuePortInUse;
        end;
    end;
    bind:= result;
end;

function unbind(bindContext : PUDPBindContext) : TUDPError;
var
    result : TUDPError;
    context : PUDPBindContext;

begin
    result:= tueGenericError;
    if bindContext <> nil then begin
        context:= Ports[bindContext^.port];
        if Ports[bindContext^.port] <> nil then begin
            if context^.UID = bindContext^.UID then begin
                kfree(void(context));
                Ports[bindContext^.port]:= nil;
                result:= tueOK;
            end else begin
                result:= tueInvalidUID;
            end;
        end else begin
            result:= tuePortNotFound;
        end;
    end;
    unbind:= result;
end;

procedure ProcessPacket(p_data : void; p_len : uint16; p_context : PPacketContext);
var
    header  : PUDPHeader;
    context : PUDPPacketContext;
    buf     : puint8;
    bind    : PUDPBindContext;
    hex     : puint8;
    i       : uint32;
    size    : uint16;

begin
    header:= PUDPHeader(p_data);
    if Ports[switchendian16(header^.DstPort)] <> nil then begin
        context:= PUDPPacketContext(kalloc(sizeof(TUDPPacketContext)));
        context^.PacketContext:= p_context;
        context^.SrcPort:= switchendian16(header^.SrcPort);
        context^.DstPort:= switchendian16(header^.DstPort);
        context^.ChecksumValid:= false;
        context^.Length:= switchendian16(header^.Length);
        buf:= puint8(p_data);
        buf:= buf + sizeof(TUDPHeader);
        size:= context^.Length - sizeof(TUDPHeader);
        bind:= Ports[context^.DstPort];
        bind^.Callback(void(buf), size, context);
        kfree(void(context));
    end;
end;

procedure TestRecv(p_data : void; p_len : uint16; context : PUDPPacketContext);
var
    Output : PChar;
    i      : uint16;

begin
    Output:= PChar(p_data);
    for i:=0 to p_len-1 do begin
        writechar(Output[i]);
    end;
    writestringln(' ');
end;

procedure register();
var
    i       : uint16;
    context : PUDPBindContext;
    r       : TUDPError;
    
    SendContext   : PUDPSendContext;
    BindContext   : PUDPBindContext;
    PacketContext : PPacketContext;
    Checksum      : uint32;

begin
    for i:=0 to 65535 do begin
        Ports[i]:= nil;
    end;
    //writestring('[TestBind] ');
    //SendContext:= PUDPSendContext(kalloc(SizeOf(TUDPSendContext)));
    //BindContext:= PUDPBindContext(kalloc(SizeOf(TUDPBindContext)));
    //PacketContext:= PPacketContext(kalloc(SizeOf(TPacketContext)));
    //SendContext^.DstPort:= 10;
    //SendContext^.Socket:= BindContext;
    //SendContext^.Context:= PacketContext;
    //BindContext^.Port:= 20;
    //copyIPv4(puint8(@UDPT_S_IP[0]), puint8(@PacketContext^.IP.Source[0]));
    //copyIPv4(puint8(@UDPT_D_IP[0]), puint8(@PacketContext^.IP.Destination[0]));
    //Checksum:= CalculateChecksum(void(@UDPT_DATA[0]), 2, SendContext);
    //writehexln(Checksum);
    //while true do begin end;

    ipv4.registerProtocol($11, @ProcessPacket);
end;

end.