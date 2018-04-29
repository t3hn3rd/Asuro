unit serial;

interface

uses
    util, isrmanager;

const
    COM1 = $3F8;
    COM2 = $2F8;
    COM3 = $3E8;
    COM4 = $2E8;

procedure init();
function receive(PORT : uint16; timeout : uint32) : uint8;
function send(PORT : uint16; data : uint8; timeout : uint32) : boolean;

implementation

uses
    console;

procedure IRQ_Hook();
begin
 
end;

procedure initPort(PORT : uint16);
begin
    outb(PORT + 1, $00);
    outb(PORT + 3, $80);
    outb(PORT + 0, $03);
    outb(PORT + 1, $00);
    outb(PORT + 3, $03);
    outb(PORT + 2, $C7);
    outb(PORT + 4, $0B);
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
    serial_received:= inb(PORT + 5) AND 1;
end;

function is_transmit_empty(PORT : uint16) : uint32;
begin
    is_transmit_empty:= inb(PORT + 5) AND $20;
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
        receive:= inb(PORT);
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
        outb(PORT, data);
        send:= true;
    end;
end;

end.