unit testdriver;

interface

uses
    console, drivermanagement;

procedure init;

implementation

function load(ptr : void) : boolean;
begin
    console.writestringln('DUMMY DRIVER LOADED.')
end;

procedure init;
var
    devID : TDeviceIdentifier;

begin
    devID.bus:= biPCI;
    devID.id0:= $00008086;
    devID.id1:= $00000006;
    devID.id2:= $00000000;
    devID.id3:= $00000000;
    devID.ex:= nil;
    drivermanagement.register_driver(@devID, @load);
end;

end.