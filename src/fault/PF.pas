{ 
	Fault->PF - Page Fault.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit PF;

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
    BSOD('PF', 'Page Fault.');
    console.writestringln('Page Fault.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    isrmanager.registerISR(14, @Main);
    //memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
    //IDT.set_gate(14, uint32(@Main), $08, ISR_RING_0);
end;

end.