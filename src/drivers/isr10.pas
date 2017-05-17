{ ************************************************
  * Asuro
  * Unit: Drivers/ISR10
  * Description: Bad TSS Exception
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr10;

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
    console.writestringln('Bad TSS Exception.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    IDT.set_gate(10, uint32(@Main), $08, ISR_RING_0);
end;

end.