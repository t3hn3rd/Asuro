{ ************************************************
  * Asuro
  * Unit: Drivers/ISR7
  * Description: No Coprocessor Exception
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr7;

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
    console.writestringln('No Coprocessor Exception.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    IDT.set_gate(7, uint32(@Main), $08, ISR_RING_0);
end;

end.