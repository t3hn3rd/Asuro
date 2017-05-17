{ ************************************************
  * Asuro
  * Unit: Drivers/ISR18
  * Description: Machine Check Exception
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr18;

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
    console.writestringln('Machine Check Exception.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    IDT.set_gate(18, uint32(@Main), $08, ISR_RING_0);
end;

end.