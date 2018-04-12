{ ************************************************
  * Asuro
  * Unit: Drivers/ISR1
  * Description: Debug Exception
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit DBGE;

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
    BSOD('DE', 'Debug Exception');
    console.writestringln('Debug Exception.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    isrmanager.registerISR(1, @Main);
    //memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
    //IDT.set_gate(1, uint32(@Main), $08, ISR_RING_0);
end;

end.