unit isr32;

interface

uses
    util,
    console,
    IDT;

type 
    pp_void : procedure();

var
    procedure_ptr : pp_void = nil;

procedure register();

implementation

procedure Main; interrupt; //IRQ0, called every 55ms
begin
    CLI;
    if(procedure_ptr <> nil) then begin
        procedure_ptr();
    end;
    outb($0020, $20);
end;

procedure register();
begin
    IDT.set_gate(32, uint32(@Main), $08, ISR_RING_0);
end;

end.
