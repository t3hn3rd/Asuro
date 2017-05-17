{ ************************************************
  * Asuro
  * Unit: Drivers/ISR13
  * Description: General Protection Fault
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr13;

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
    console.writestringln('General Protection Fault.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    IDT.set_gate(13, uint32(@Main), $08, ISR_RING_0);
end;

end.