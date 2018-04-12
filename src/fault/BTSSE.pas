{ ************************************************
  * Asuro
  * Unit: Drivers/ISR10
  * Description: Bad TSS Exception
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit BTSSE;

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
    BSOD('TSS', 'Bad TSS Exception.');
    console.writestringln('Bad TSS Exception.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    isrmanager.registerISR(10, @Main);
    //memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
    //IDT.set_gate(10, uint32(@Main), $08, ISR_RING_0);
end;

end.