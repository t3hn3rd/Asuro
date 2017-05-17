{ ************************************************
  * Asuro
  * Unit: Drivers/ISR12
  * Description: Stack Fault Exception
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr12;

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
    IDT.set_gate(12, uint32(@Main), $08, ISR_RING_0);
end;

end.