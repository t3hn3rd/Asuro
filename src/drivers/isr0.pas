unit isr0;

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
    console.writestringln('Divide by Zero Exception.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    IDT.set_gate(0, uint32(@Main), $08, ISR_RING_0);
end;

end.