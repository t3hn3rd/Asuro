{ ************************************************
  * Asuro
  * Unit: Drivers/ISR15
  * Description: Unknown Interrupt Exception
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit UIE;

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
    BSOD('UI', 'Unknown Interrupt Exception.');
    console.writestringln('Unknown Interrupt Exception.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    isrmanager.registerISR(15, @Main);
    //memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
    //IDT.set_gate(15, uint32(@Main), $08, ISR_RING_0);
end;

end.