{ ************************************************
  * Asuro
  * Unit: Drivers/ISR17
  * Description: Alignment Check Exception
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr17;

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
    CLI;
    console.writestringln('Alignment Check Exception.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    IDT.set_gate(17, uint32(@Main), $08, ISR_RING_0);
end;

end.