unit isr;

interface

uses
    ISR0;

procedure init();

implementation

procedure init();
begin
    ISR0.register();
end;

end.