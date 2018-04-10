unit netutils;

interface

uses
    nettypes, console;

procedure writeMACAddress(mac : puint8);
procedure writeIPv4Address(ip : puint8);
function MACEqual(mac1 : puint8; mac2 : puint8) : boolean;

implementation

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

end.