{ ************************************************
  * Asuro
  * Unit: Drivers/ISR11
  * Description: Coprocessor Fault Exception
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr16;

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
    IDT.set_gate(16, uint32(@Main), $08, ISR_RING_0);
end;

end.