{ 
	Interrupt Request Line - Initialization & Remapping.
	
	@author(Aaron Hance <ah@aaronhance.me>)
}
unit irq;

interface

uses util, console;

procedure init();

implementation

procedure init();
begin
    console.outputln('IRQ','INIT START.');
    outb($20, $11);
    io_wait;
    outb($A0, $11);
    io_wait;
    outb($21, $20);
    io_wait;
    outb($A1, $28);
    io_wait;
    outb($21, $04);
    io_wait;
    outb($A1, $02);
    io_wait;
    outb($21, $01);
    io_wait;
    outb($A1, $01);
    io_wait;
    outb($21, $00);
    io_wait;
    outb($A1, $00);
    io_wait;
    console.outputln('IRQ','INIT END.');
end;

end.