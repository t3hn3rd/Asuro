{ ************************************************
  * Asuro
  * Unit: isr
  * Description: Stub for ISR Driver Initialization
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr;

interface

uses
    ISR0,  ISR1,  ISR2,  ISR3,  ISR4,  ISR5,  ISR6,  ISR7,  ISR8, ISR9, 
    ISR10, ISR11, ISR12, ISR13, ISR14, ISR15, ISR16, ISR17, ISR18;

    

procedure init();

implementation

procedure init();
begin
    ISR0.register();
    ISR1.register();
    ISR2.register();
    ISR3.register();
    ISR4.register();
    ISR5.register();
    ISR6.register();
    ISR7.register();
    ISR8.register();
    ISR9.register();
    ISR10.register();
    ISR11.register();
    ISR12.register();
    ISR13.register();
    ISR14.register();
    ISR15.register();
    ISR16.register();
    ISR17.register();
    ISR18.register();
end;

end.