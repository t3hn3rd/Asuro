{ ************************************************
  * Asuro
  * Unit: Drivers/ISR11
  * Description: Segment Not Present Exception
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr11;

interface

uses
    util,
    console,
    isr_types,
    IDT;

procedure register();

implementation

procedure Main(); interrupt;
begin
    util.halt_and_catch_fire;
end;

procedure register();
begin
    IDT.set_gate(11, uint32(@Main), $08, ISR_RING_0);
end;

end.