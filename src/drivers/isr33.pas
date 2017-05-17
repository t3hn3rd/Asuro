{ ************************************************
  * Asuro
  * Unit: Drivers/isr33
  * Description: Keyboard interrupt
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }

unit isr33;

interface

uses
    util,
    console,
    IDT;

type
    pp_byte = procedure(key_code : byte);

var
    procedure_ptr : pp_byte = nil;

procedure register();

implementation

procedure Main; interrupt; //IRQ1, Keyboard Interrupt
begin
    CLI;
    console.writestringln('helo2');
    if(procedure_ptr <> nil) then begin
        procedure_ptr(inb($60));
    end;
    outb($20, $20);
    STI;
end;

procedure register();
begin
    IDT.set_gate(33, uint32(@Main), $08, ISR_RING_0);
end;

end.