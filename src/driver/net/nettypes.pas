unit nettypes;

interface

uses
    console;

type
    TNetSendCallback = function(p_data : void; p_len : uint16) : sint32;
    TRecvCallback    = procedure(p_data : void; p_len : uint16);

procedure writeMACAddress(mac : puint8);

implementation

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