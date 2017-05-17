{ ************************************************
  * Asuro
  * Unit: Drivers/ISR15
  * Description: Unknown Interrupt Exception
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr15;

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
    console.writestringln('Unknown Interrupt Exception.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    IDT.set_gate(15, uint32(@Main), $08, ISR_RING_0);
end;

end.