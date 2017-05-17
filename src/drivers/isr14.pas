{ ************************************************
  * Asuro
  * Unit: Drivers/ISR14
  * Description: Page Fault
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr14;

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
    console.writestringln('Page Fault.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    IDT.set_gate(14, uint32(@Main), $08, ISR_RING_0);
end;

end.