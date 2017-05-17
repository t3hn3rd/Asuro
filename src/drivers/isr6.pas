{ ************************************************
  * Asuro
  * Unit: Drivers/ISR6
  * Description: Invalid OPCode Exception
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr6;

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
    console.writestringln('Invalid OPCode Exception.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    IDT.set_gate(6, uint32(@Main), $08, ISR_RING_0);
end;

end.