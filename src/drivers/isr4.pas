{ ************************************************
  * Asuro
  * Unit: Drivers/ISR4
  * Description: Into Detected Overflow Exception
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr4;

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
    console.writestringln('IDO Exception.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    IDT.set_gate(4, uint32(@Main), $08, ISR_RING_0);
end;

end.