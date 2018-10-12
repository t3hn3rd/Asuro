{ 
	Driver->Exp->TestDriver - Dummy Driver For Testing.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit testdriver;

interface

uses
    tracer, console, drivermanagement;

procedure init;

implementation

function load(ptr : void) : boolean;
begin
    push_trace('testdriver.load');
    console.outputln('DUMMY DRIVER', 'LOADED.');
    pop_trace;
end;

procedure init;
var
    devID : TDeviceIdentifier;

begin
    push_trace('testdriver.init');
    devID.bus:= biPCI; { PCI BUS }
    devID.id0:= idANY; { ANY DEVICE ID }
    devID.id1:= $00000006; { CLASS }
    devID.id2:= $00000000; { SUBCLASS }
    devID.id3:= $00000000; { PROGIF }
    devID.id4:= idANY;
    devID.ex:= nil; { NO EXTENDED INFO }
    drivermanagement.register_driver('DUMMY DRIVER', @devID, @load);
    pop_trace;
end;

end.