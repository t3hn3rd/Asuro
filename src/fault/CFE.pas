{ ************************************************
  * Asuro
  * Unit: Drivers/ISR11
  * Description: Coprocessor Fault Exception
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit CFE;

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
    BSOD('CF', 'Coprocessor Fault Exception.');
    console.writestringln('Coprocessor Fault Exception.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    isrmanager.registerISR(16, @Main);
    //memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
    //IDT.set_gate(16, uint32(@Main), $08, ISR_RING_0);
end;

end.