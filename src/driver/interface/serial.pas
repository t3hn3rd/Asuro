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
	Driver->Interface->Serial - Serial Driver.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit serial;

interface

uses
    util, isrmanager, strings;

const
    COM1 = $3F8;
    COM2 = $2F8;
    COM3 = $3E8;
    COM4 = $2E8;

procedure init();
function receive(PORT : uint16; timeout : uint32) : uint8;
function send(PORT : uint16; data : uint8; timeout : uint32) : boolean;
function sendString(str : pchar) : boolean;
function sendHex(i : uint32) : boolean;
procedure soutb(port : uint16; val : uint8);
function sinb(port : uint16) : uint8;

implementation

{ no implementation uses }

procedure soutb(port : uint16; val : uint8);
begin
     asm
          PUSH EAX
          PUSH EDX
          MOV DX, port
          MOV AL, val
          OUT DX, AL
          POP EDX
          POP EAX
     end;
     io_wait;
end;

function sinb(port : uint16) : uint8;
var
     tmp : uint8;
begin
     asm
          PUSH EAX
          PUSH EDX
          MOV DX, port
          IN AL, DX
          MOV tmp, AL
          POP EDX
          POP EAX
     end;
     sinb := tmp;
     io_wait;
end;

procedure IRQ_Hook();
begin
 
end;

procedure initPort(PORT : uint16);
begin
    soutb(PORT + 1, $00);
    soutb(PORT + 3, $80);
    soutb(PORT + 0, $03);
    soutb(PORT + 1, $00);
    soutb(PORT + 3, $03);
    soutb(PORT + 2, $C7);
    soutb(PORT + 4, $0B);
end;

procedure init();
begin
    initPort(COM1);
    initPort(COM2);
    initPort(COM3);
    initPort(COM4);
end;

function serial_received(PORT : uint16) : uint32;
begin
    serial_received:= sinb(PORT + 5) AND 1;
end;

function is_transmit_empty(PORT : uint16) : uint32;
begin
    is_transmit_empty:= sinb(PORT + 5) AND $20;
end;

function receive(PORT : uint16; timeout : uint32) : uint8;
var
    _timeout : uint32;

begin
    receive:= 0;
    _timeout:= timeout;
    while (serial_received(PORT) = 0) AND (_timeout > 0) do begin 
        dec(_timeout);
    end;
    if _timeout <> 0 then begin
        receive:= sinb(PORT);
    end;
end;

function send(PORT : uint16; data : uint8; timeout : uint32) : boolean;
var
    _timeout : uint32;

begin
    send:= false;
    _timeout:= timeout;
    while (is_transmit_empty(PORT) = 0) and (_timeout > 0) do begin 
        dec(_timeout);
    end;
    if _timeout <> 0 then begin
        soutb(PORT, data);
        send:= true;
    end;
end;

function sendString(str : pchar) : boolean;
var
    i : uint32;

begin
    sendString:= true;
    for i:=0 to StringSize(str)-1 do begin
        sendString:= sendString AND send(COM1, uint8(str[i]), 10000);
    end;
    sendString:= sendString AND send(COM1, uint8(13), 10000);
    sendString:= sendString AND send(COM1, uint8(10), 10000);
end;

function sendHex(i : uint32) : boolean;
var
   Hex : Array[0..7] of Byte;
   Res : DWORD;
   Rem : DWORD;
   c   : Integer;
   
begin
     for c:=0 to 7 do begin
          Hex[c]:= 0;
     end;
     c:=0;
     Res:= i;
     Rem:= Res mod 16;
     while Res > 0 do begin
          Hex[c]:= Rem;
          Res:= Res div 16;
          Rem:= Res mod 16;
          c:=c+1;
     end;
     send(COM1, uint8('0'), 10000);
     send(COM1, uint8('x'), 10000);
     for c:=7 downto 0 do begin
          if Hex[c] <> 255 then begin
               case Hex[c] of
                    0:send(COM1,   uint8('0'), 10000);
                    1:send(COM1,   uint8('1'), 10000);
                    2:send(COM1,   uint8('2'), 10000);
                    3:send(COM1,   uint8('3'), 10000);
                    4:send(COM1,   uint8('4'), 10000);
                    5:send(COM1,   uint8('5'), 10000);
                    6:send(COM1,   uint8('6'), 10000);
                    7:send(COM1,   uint8('7'), 10000);
                    8:send(COM1,   uint8('8'), 10000);
                    9:send(COM1,   uint8('9'), 10000);
                    10:send(COM1,  uint8('A'), 10000);
                    11:send(COM1,  uint8('B'), 10000);
                    12:send(COM1,  uint8('C'), 10000);
                    13:send(COM1,  uint8('D'), 10000);
                    14:send(COM1,  uint8('E'), 10000);
                    15:send(COM1,  uint8('F'), 10000);
                    else send(COM1,uint8('?'), 10000);
               end;
          end;
     end;
     send(COM1, uint8(13), 10000);
     send(COM1, uint8(10), 10000);
     sendHex:= true;
end;

end.