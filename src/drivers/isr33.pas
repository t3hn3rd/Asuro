unit isr33;

interface

uses
    util,
    console,
    IDT;

type
    pp_int : procedure(byte);

var
    procedure_ptr : pp_int = nil;

procedure register();

implementation

procedure Main; interrupt; //IRQ1, Keyboard Interrupt
begin
    CLI;
    if(procedure_ptr <> nil) tehn begin
        procedure_ptr(inb($60));
    end;
    outb($0020, $20);
end;

procedure register();
begin
    IDT.set_gate(33, uint32(@Main), $08, ISR_RING_0);
end;

end.