unit isr;

interface

uses
    ISR0,
    ISR1;

procedure init();

implementation

procedure init();
begin
    ISR0.register();
    ISR1.register();
end;

end.