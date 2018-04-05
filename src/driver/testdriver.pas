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
    devID.bus:= biPCI; { PCI BUS }
    devID.id0:= idANY; { ANY DEVICE ID }
    devID.id1:= $00000006; { CLASS }
    devID.id2:= $00000000; { SUBCLASS }
    devID.id3:= $00000000; { PROGIF }
    devID.id4:= idANY;
    devID.ex:= nil; { NO EXTENDED INFO }
    drivermanagement.register_driver('DUMMY DRIVER', @devID, @load);
end;

end.