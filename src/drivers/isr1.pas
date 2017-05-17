unit isr1;

interface

uses
    util,
    console,
    IDT;

procedure register();

implementation

procedure Main; interrupt;
begin
    CLI;
    
    util.halt_and_catch_fire;
end;

procedure register();
begin
    IDT.set_gate(1, uint32(@Main), $08, ISR_RING_0);
end;

end.