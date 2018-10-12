{ 
	Fault->IOPE - Invalid OPCode Exception.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit IOPE;

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
    BSOD('IO', 'Invalid OPCode Exception.');
    console.writestringln('Invalid OPCode Exception.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    isrmanager.registerISR(6, @Main);
    //memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
    //IDT.set_gate(6, uint32(@Main), $08, ISR_RING_0);
end;

end.