{ ************************************************
  * Asuro
  * Unit: Drivers/isr_types
  * Description: Defines for ISRs (WIP)
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit isr_types;

interface

type
    ISR_REGS = record
        ip, cs, flags, sp, ss : uint16;
    end;
	PISR_REGS = ^ISR_REGS;

implementation

end.