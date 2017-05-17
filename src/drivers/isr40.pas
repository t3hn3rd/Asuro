{ ************************************************
  * Asuro
  * Unit: Drivers/isr40
  * Description: 1024/s Timer interrupt
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }

unit isr40;

interface

uses
    util,
    console,
    IDT;

type 
    pp_void = procedure();

var
    procedure_ptr : pp_void = nil;

procedure register();

implementation

procedure Main; interrupt; //IRQ0, called 1024 times a second.
begin
    console.writestringln('helo3');
    if(procedure_ptr <> nil) then begin
        procedure_ptr();
    end;
    outb($A0, $20);
    outb($20, $20);
end;

procedure register();
begin
    IDT.set_gate(40, uint32(@Main), $08, ISR_RING_0);
end;

end.
 