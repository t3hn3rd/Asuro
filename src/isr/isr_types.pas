{ 
	ISR->ISR_Types - Interrupt Service Routine Structures.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}

unit isr_types;

interface

const
    MAX_HOOKS = 16;

type
    PRegisters = ^TRegisters;
    TRegisters = record
        edi,esi,ebp,esp,ebx,edx,ecx,eax: uint32;
        ErrorCode : uint32;
        eip,cs,eflags,UserESP,ss: uint32;
    end;

    pp_hook_method = procedure(data : void);
    pp_void = pp_hook_method;

implementation

end.