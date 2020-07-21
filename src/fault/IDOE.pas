{ 
	Fault->IDO - Into Detected Overflow Exception.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit IDOE;

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
    correctInterruptRegisters(false);
    BSOD('IDO', 'Into Detected Overflow Exception.');
    console.writestringln('IDO Exception.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    isrmanager.registerISR(4, @Main);
    //memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
    //IDT.set_gate(4, uint32(@Main), $08, ISR_RING_0);
end;

end.