unit isr1;

interface

uses
    util,
    console,
    IDT;

var
    last_key : byte;

procedure register();

implementation

procedure Main; interrupt; //IRQ1, Keyboard Interrupt
begin
    CLI;
    last_key = inb($60);
    outb($0020, $20);
end;

procedure register();
begin
    IDT.set_gate(33, uint32(@Main), $08, ISR_RING_0);
end;

end.