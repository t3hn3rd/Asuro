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
    outb($0021, 32);
    outb($00A1, 40);
    outb($0021, 4);
    outb($00A1, 2);    
    outb($0021, 1);
    outb($00A1, 1);
end;

end.