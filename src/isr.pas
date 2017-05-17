unit isr;

interface

uses
    idt,
    console,
    util;

procedure init();

implementation

procedure CLI(); assembler; nostackframe;
asm
    CLI
end;

procedure isr0(); interrupt;
begin
    CLI;
    console.writestringln('Divide by Zero Exception.');
    util.halt_and_catch_fire;
end;

procedure init();
begin
    idt.set_gate(0, uint32(@isr0), $08, ISR_RING_0);
end;

end.