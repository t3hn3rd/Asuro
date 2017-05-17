{ ************************************************
  * Asuro
  * Unit: Drivers/isr32
  * Description: 55ms Timer interrupt
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }

unit isr32;

interface

uses
    util,
    console,
    isr_types,
    IDT;

//type 
//    pp_void = procedure();

//var
//    procedure_ptr : pp_void = nil;

procedure register();

implementation

procedure Main; interrupt; //IRQ0, called every 55ms
begin
    //if(procedure_ptr <> nil) then begin
        //procedure_ptr();
    //end;
    outb($20, $20);
end;

procedure register();
begin
    asm
        mov al, $36
        out $46, al
        mov ax, 1165
        out $40, al
        mov al, ah
        out $40, al
    end;
    IDT.set_gate(32, uint32(@Main), $08, ISR_RING_0);
end;

end.
