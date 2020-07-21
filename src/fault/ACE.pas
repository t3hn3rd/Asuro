{ 
	Fault->ACE - Alignment Check Exception.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit ACE;

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
    correctInterruptRegisters(true);
    BSOD('AC', 'Alignment Check Exception.');
    console.writestringln('Alignment Check Exception.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    isrmanager.registerISR(17, @Main);
    //memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
    //IDT.set_gate(17, uint32(@Main), $08, ISR_RING_0);
end;

end.