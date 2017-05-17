{ ************************************************
  * Asuro
  * Unit: Drivers/ISR3
  * Description: Breakpoint Exception
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr3;

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
    console.writestringln('Breakpoint Exception');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    IDT.set_gate(3, uint32(@Main), $08, ISR_RING_0);
end;

end.