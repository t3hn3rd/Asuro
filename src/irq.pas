{ ************************************************
  * Asuro
  * Unit: irq
  * Description: mapping IRQs
  ************************************************
  * Author: Aaron Hance
  * Contributors:
  ************************************************ }

unit irq;

interface

uses util, console;

procedure init();

implementation

procedure init();
begin
    console.writestringln('IRQ: INIT START.');
    outb($20, $11);
    outb($A0, $11);
    outb($21, $20);
    outb($A1, $28);
    outb($21, $04);
    outb($A1, $02);
    outb($21, $01);
    outb($A1, $01);

    outb($21, $00);
    outb($A1, $00);

    console.writestringln('IRQ: INIT END.');
end;

end.