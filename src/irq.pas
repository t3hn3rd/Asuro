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
uses util;

procedure init();

implementation

procedure init();
begin
    outb($0020, $11);
    outb($00A0, $11);
    outb($0021, $20);
    outb($00A1, $28);
    outb($0021, $04);
    outb($00A1, $02);    
    outb($0021, $01);
    outb($00A1, $01);
end;

end.