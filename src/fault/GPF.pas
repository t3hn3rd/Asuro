{ ************************************************
  * Asuro
  * Unit: Drivers/ISR13
  * Description: General Protection Fault
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

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
    asm
        MOV EAX, EBP
        MOV Regs, EAX
    end;
    BSOD('GPF', 'General Protection Fault.');
    console.writestringln('General Protection Fault.');
    console.writestring('Flags: ');
    console.writehexln(Regs^.EFlags);
    console.writestring('EIP: ');
    console.writehexln(Regs^.EIP);
    console.writestring('CS: ');
    console.writehexln(Regs^.CS);
    console.writestring('Error Code: ');
    console.writehexln(Regs^.ErrorCode);
    util.halt_and_catch_fire;
end;

procedure register();
begin
    isrmanager.registerISR(13, @Main);
    //memset(uint32(@Hooks[0]), 0, sizeof(pp_hook_method)*MAX_HOOKS);
    //IDT.set_gate(13, uint32(@Main), $08, ISR_RING_0);
end;

end.