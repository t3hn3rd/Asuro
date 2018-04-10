unit netutils;

interface

uses
    util, nettypes, console, lmemorymanager;

procedure copyMAC(src : puint8; dst : puint8);
procedure copyIPv4(src : puint8; dst : puint8);
procedure writeMACAddress(mac : puint8);
procedure writeIPv4Address(ip : puint8);
function MACEqual(mac1 : puint8; mac2 : puint8) : boolean;
function IPEqual(ip1 : puint8; ip2 : puint8) : boolean;
function newPacketContext : PPacketContext;
procedure freePacketContext(p_context : PPacketContext);

implementation

function IPEqual(ip1 : puint8; ip2 : puint8) : boolean;
var
    i : uint8;

begin
    IPEqual:= true;
    for i:=0 to 3 do begin
        if ip1[i] <> ip2[i] then begin
            IPEqual:= false;
            exit;
        end;
    end;
end;

function MACEqual(mac1 : puint8; mac2 : puint8) : boolean;
var
    i : uint8;

begin
    MACEqual:= true;
    for i:=0 to 5 do begin
        if mac1[i] <> mac2[i] then begin
            MACEqual:= false;
            exit;
        end;
    end;
end;

procedure writeIPv4Address(ip : puint8);
var
    i : integer;

begin
    console.writeint(ip[0]);
    for i:=1 to 3 do begin
        console.writestring('.');
        console.writeint(ip[i]);
    end;
    console.writestringln(' ');   
end;

procedure writeMACAddress(mac : puint8);
var
    i : integer;

begin
    console.writehexpair(mac[0]);
    for i:=1 to 5 do begin
        console.writestring(':');
        console.writehexpair(mac[i]);
    end;
    console.writestringln(' ');
end;

function newPacketContext : PPacketContext;
begin
    newPacketContext:= PPacketContext(kalloc(sizeof(TPacketContext)));
    memset(uint32(newPacketContext), 0, sizeof(TPacketContext));
end;

procedure freePacketContext(p_context : PPacketContext);
begin
    kfree(void(p_context));
end;

procedure copyMAC(src : puint8; dst : puint8);
var
    i : uint8;

begin
    for i:=0 to 5 do begin
        dst[i]:= src[i];
    end;
end;

procedure copyIPv4(src : puint8; dst : puint8);
var
    i : uint8;

begin
    for i:=0 to 3 do begin
        dst[i]:= src[i];
    end;
end;

end.