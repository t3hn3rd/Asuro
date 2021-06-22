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
	Driver->Net->L2->Eth2 - Ethernet Driver.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit eth2;

interface

uses
    lmemorymanager, util,
    tracer,
    nettypes, netutils, terminal,
    net,
    netlog,
    console,
    crc;

procedure send(p_data : void; p_len : uint16; eth_type : uint16; p_context : PPacketContext);
procedure registerType(eType : uint16; RecvCB : TRecvCallback);
procedure registerTypePromisc(eType : uint16; RecvCB : TRecvCallback);
procedure register;

implementation

uses
    arp;

var
    Registered : Boolean = false;
    EthTypes   : Array[0..65535] of TRecvCallback;
    Promisc    : Array[0..65535] of Boolean;
    MAC        : puint8;

procedure registerTypePromisc(eType : uint16; RecvCB : TRecvCallback);
begin
    register;
    if EthTypes[eType] = nil then EthTypes[eType]:= RecvCB;
    Promisc[eType]:= true;
end;

procedure registerType(eType : uint16; RecvCB : TRecvCallback);
begin
    register;
    if EthTypes[eType] = nil then EthTypes[eType]:= RecvCB;
end;

procedure send(p_data : void; p_len : uint16; eth_type : uint16; p_context : PPacketContext);
var
    buffer : void;
    hdr    : TEthernetHeader;
    pad    : sint32;
    size   : uint32;
    FCS    : puint32;

begin
    pad:= 46 - p_len;
    if pad < 0 then pad:= 0;
    push_trace('eth2.send');
    writeToLogLn('    L2: eth2.send');
    if p_context <> nil then begin
        size:= sizeof(TEthernetHeader) + p_len + pad;// + 4;
        buffer:= kalloc(size);
        copyMAC(@p_context^.MAC.Source[0], @hdr.src[0]);
        copyMAC(@p_context^.MAC.Destination[0], @hdr.dst[0]);
        hdr.EthTypeHi:= eth_type SHR 8;
        hdr.EthTypeLo:= eth_type AND $FF;
        memcpy(uint32(@hdr), uint32(buffer), sizeof(TEthernetHeader));
        memcpy(uint32(p_data), uint32(buffer)+sizeof(TEthernetHeader), p_len);
        //FCS:= puint32((uint32(buffer) + size) - 4);
        //FCS^:= crc32(puint8(buffer), size - 4);
        net.send(buffer, size);
        kfree(buffer);
    end;
end;

procedure recv(p_data : void; p_len : uint16; p_context : PPacketContext);
var
    Header     : PEthernetHeader;
    proto_type : uint16;
    buf        : puint8;

begin
    //writeToLogLn('    L2: eth2.recv');
    buf:= puint8(p_data);
    
    Header:= PEthernetHeader(buf);
    proto_type:= Header^.EthTypeHi SHL 8;
    proto_type:= proto_type + Header^.EthTypeLo;
    buf:= buf + 14;

    copyMAC(@Header^.src[0], @p_context^.MAC.Source[0]);
    copyMAC(@Header^.dst[0], @p_context^.MAC.Destination[0]);

    if MACEqual(@Header^.dst[0], getMAC) or 
       MACEqual(@Header^.dst[0], @BROADCAST_MAC[0]) or
       Promisc[proto_type] then begin
        if EthTypes[proto_type] <> nil then begin
            EthTypes[proto_type](void(buf), p_len - 14, p_context);
        end;    
    end;
end;

procedure register;
var
    i : uint16;

begin
    push_trace('eth2.register');
    if not Registered then begin
        for i:=0 to 65535 do begin
            EthTypes[i]:= nil;
            Promisc[i]:= false;
        end;
        net.registerNextLayer(@recv);
        MAC:= net.getMAC;
        Registered:= true;
    end;
    pop_trace;
end;

end.