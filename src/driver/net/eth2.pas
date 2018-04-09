unit eth2;

interface

uses
    net, nettypes, console;

procedure register;

implementation

var
    Registered : Boolean = false;
    EthTypes   : Array[0..65535] of TRecvCallback;
    MAC        : puint8;

procedure registerType(eType : uint16; RecvCB : TRecvCallback);
begin
    if EthTypes[eType] = nil then EthTypes[eType]:= RecvCB;
end;

procedure recv(p_data : void; p_len : uint16);
var
    src, dst   : puint8;
    proto_type : uint16;

begin
    dst:= puint8(p_data);
    src:= puint8(p_data + 6);
    console.output('net.eth2', 'DEST: ');
    writeMACAddress(dst);
    console.output('net.eth2', 'SRC: ');
    writeMACAddress(src);
end;

procedure register;
var
    i : uint16;

begin
    if not Registered then begin
        for i:=0 to 65535 do begin
            EthTypes[i]:= nil;
        end;
        net.registerNextLayer(@recv);
        MAC:= net.getMAC;
        Registered:= true;
    end;
end;

end.