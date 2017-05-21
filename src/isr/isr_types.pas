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

const
    MAX_HOOKS = 16;

type
    ISR_REGS = record
        ip, cs, flags, sp, ss : uint16;
    end;
	PISR_REGS = ^ISR_REGS;

    pp_hook_method = procedure(data : void);
    pp_void = pp_hook_method;

implementation

end.