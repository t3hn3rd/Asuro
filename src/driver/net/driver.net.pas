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
	Driver->Net->L1->Net - Network Card<->Driver Interface.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.net;

interface

uses
    boot.mgr,
    debug.tracer,
    driver.net.types, driver.net.util,
    io.syslog,
    driver.timer.rtc;

procedure init;
procedure registerNetworkCard(SendCallback : TNetSendCallback; _MAC : puint8);
procedure registerNextLayer(RecvCallback : TRecvCallback);
procedure send(p_data : void; p_len : uint16);
procedure recv(p_data : void; p_len : uint16);
function  getMAC : puint8;
procedure writeToLog(str : pchar);
procedure writeToLogLn(str : pchar);

implementation

uses  
    driver.net.dev.e1000,              //dev
    driver.net.proto.eth2,               //L2
    driver.net.proto.arp, driver.net.proto.ipv4,          //L3
    driver.net.proto.icmp, driver.net.proto.tcp, driver.net.proto.udp,     //L4
    driver.net.proto.dhcp;               //L5

var
    CBSend : TNetSendCallback = nil;
    CBNext : TRecvCallback    = nil;
    MAC    : puint8           = @NULL_MAC[0];

procedure writeToLog(str : pchar);
var
    DateTime : TDateTime;

begin
    DateTime:= getDateTime;
    io.syslog.writestring('[');

    if DateTime.Hours < 10 then io.syslog.writeint(0);
    io.syslog.writeint(DateTime.Hours);
    io.syslog.writestring(':');
    
    if DateTime.Minutes < 10 then io.syslog.writeint(0);
    io.syslog.writeint(DateTime.Minutes);
    io.syslog.writestring(':');

    if DateTime.Seconds < 10 then io.syslog.writeint(0);
    io.syslog.writeint(DateTime.Seconds);
    io.syslog.writestring('] '); 

    io.syslog.writestring(str);
end;

procedure writeToLogLn(str : pchar);
begin
    writeToLog(str);
    io.syslog.writestringln(' ');
end;

procedure registerNetworkCard(SendCallback : TNetSendCallback; _MAC : puint8);
begin
    push_trace('driver.net.registerNetworkCard');
    if CBSend = nil then begin
        CBSend:= SendCallback;
        MAC:= _MAC;
    end;    
    pop_trace;
end;

procedure registerNextLayer(RecvCallback : TRecvCallback);
begin
    push_trace('driver.net.registerNextLayer');
    if CBNext = nil then begin
        CBNext:= RecvCallback;
    end;
    pop_trace;
end;

procedure send(p_data : void; p_len : uint16);
begin
    push_trace('driver.net.send');
    writeToLogLn('L1/NET: send');
    if CBSend <> nil then CBSend(p_data, p_len);
    pop_trace;
end;

procedure recv(p_data : void; p_len : uint16);
var
    context : PPacketContext;

begin
    push_trace('driver.net.recv');
    context:= newPacketContext;
    if CBNext <> nil then CBNext(p_data, p_len, context);
    freePacketContext(context);
    pop_trace;
end;

function getMAC : puint8;
begin
    push_trace('driver.net.getMAC');
    getMAC:= MAC;
    pop_trace;
end;

procedure init;
begin
    push_trace('driver.net.init');
    writeToLogLn('L1/NET: init');
    //l2
    driver.net.proto.eth2.register;
    //l3
    driver.net.proto.arp.register;
    driver.net.proto.ipv4.register;
    //l4
    driver.net.proto.icmp.register;
    driver.net.proto.tcp.register;
    driver.net.proto.udp.register;
    //l5
    driver.net.proto.dhcp.register;
    pop_trace;
end;

initialization
    boot.mgr.registerBoot('driver.net', @Init, 'Net Driver', BOOT_MGR_BARRIER_LATE)

end.