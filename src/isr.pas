{ ************************************************
  * Asuro
  * Unit: isr
  * Description: Stub for ISR Driver Initialization
  ************************************************
  * Author: K Morris
  * Contributors: A Hance
  ************************************************ }

unit isr;

interface

uses
    Console,
    ISR0,  ISR1,  ISR2,  ISR3,  ISR4,  ISR5,  ISR6,  ISR7,  ISR8, ISR9, 
    ISR10, ISR11, ISR12, ISR13, ISR14, ISR15, ISR16, ISR17, ISR18, 
    ISR32, ISR33,
    ISR40, ISR44;   

procedure init();

implementation

procedure init();
begin
    console.writestringln('ISR: INIT START.');
    ISR0.register();  // Divide-By-Zero
    ISR1.register();  // Debug
    ISR2.register();  // Non-Maskable Inturrupt
    ISR3.register();  // Breakpoint
    ISR4.register();  // Detected Overflow
    ISR5.register();  // Out of Bounds
    ISR6.register();  // Invalid OPCode
    ISR7.register();  // No Coprocessor
    ISR8.register();  // Double Fault
    ISR9.register();  // CP Segment Overrun
    ISR10.register(); // Bad TSS
    ISR11.register(); // Segment not Present
    ISR12.register(); // Stack Fault
    ISR13.register(); // General Protection Fault
    ISR14.register(); // Page Fault
    ISR15.register(); // Unknown Interrupt
    ISR16.register(); // CP Fault
    ISR17.register(); // Alignment Check
    ISR18.register(); // Machine Check

    ISR32.register(); // 55ms Timer
    ISR33.register(); // Keyboard
    ISR40.register(); // 1024/s Timer
    ISR44.register(); // Mouse
    console.writestringln('ISR: INIT END.');
end;

end.