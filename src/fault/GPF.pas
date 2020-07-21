{ 
	Fault->GPF - General Protection Fault.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit GPF;

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
    i    : uint32;
    Regs : PRegisters;

begin
    CLI;
    correctInterruptRegisters(true);
    BSOD('GPF', 'General Protection Fault.');
    console.writestringln('General Protection Fault.');
    util.halt_and_catch_fire;
end;

procedure register();
begin
    isrmanager.registerISR(13, @Main);
    //memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
    //IDT.set_gate(13, uint32(@Main), $08, ISR_RING_0);
end;

end.