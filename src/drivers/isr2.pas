{ ************************************************
  * Asuro
  * Unit: Drivers/ISR2
  * Description: Non-Maskable Interrupt Exception
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr2;

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
    console.writestringln('NMI Exception.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    IDT.set_gate(2, uint32(@Main), $08, ISR_RING_0);
end;

end.