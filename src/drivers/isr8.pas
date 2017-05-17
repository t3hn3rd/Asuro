{ ************************************************
  * Asuro
  * Unit: Drivers/ISR8
  * Description: Double Fault Exception
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr8;

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
    console.writestringln('Double Fault.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    IDT.set_gate(8, uint32(@Main), $08, ISR_RING_0);
end;

end.