{ ************************************************
  * Asuro
  * Unit: Drivers/ISR9
  * Description: Coprocessor Seg Overrun Exception
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit CSOE;

interface

uses
    util,
    console,
    isr_types,
    isrmanager,
    IDT;

procedure register();

implementation

procedure Main();
var
    i : integer;
    
begin
    CLI;
    BSOD('CSO', 'Coprocessor Seg Overrun Exception.');
    console.writestringln('Coprocessor Seg Overrun Exception.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    isrmanager.registerISR(9, @Main);
    //memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
    //IDT.set_gate(9, uint32(@Main), $08, ISR_RING_0);
end;

end.