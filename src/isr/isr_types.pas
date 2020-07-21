{ 
	ISR->ISR_Types - Interrupt Service Routine Structures.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}

unit isr_types;

interface

const
    MAX_HOOKS = 16;

type
    TInterruptRegisters = packed record
        EBP    : uint32;
        EAX    : uint32;
        EBX    : uint32;
        ECX    : uint32;
        EDX    : uint32;
        ESI    : uint32;
        EDI    : uint32;
        DS     : uint16;
        ES     : uint16;
        FS     : uint16;
        GS     : uint16;
    end;
    PInterruptRegisters = ^TInterruptRegisters;
    
    TError = packed record
        Error : uint32;
    end;
    PError = ^TError;

    TInterruptSpecialRegisters = packed record
        EIP    : uint32;
        CS     : uint32;
        EFLAGS : uint32;
    end;
    PInterruptSpecialRegisters = ^TInterruptSpecialRegisters;

    PRegisters = ^TRegisters;
    TRegisters = record
        edi,esi,ebp,esp,ebx,edx,ecx,eax: uint32;
        ErrorCode : uint32;
        eip,cs,eflags,UserESP,ss: uint32;
    end;

    pp_hook_method = procedure(data : void);
    pp_void = pp_hook_method;

var
    IntReg    : PInterruptRegisters = nil;
    IntSpec   : PInterruptSpecialRegisters = nil;
    IntErr    : PError = nil;
    ZeroError : uint32 = 0;

procedure correctInterruptRegisters(Errorcode : boolean);

implementation

procedure correctInterruptRegisters(Errorcode : boolean);
begin
    if IntReg <> nil then begin
        If errorcode then begin
            IntSpec:= PInterruptSpecialRegisters(uint32(IntReg) + sizeof(TInterruptRegisters) + uint32(4));
            IntErr:= PError(uint32(IntReg) + sizeof(TInterruptRegisters));
        end else begin
            IntSpec:= PInterruptSpecialRegisters(uint32(IntReg) + sizeof(TInterruptRegisters));
            IntErr:= PError(@ZeroError);
        end;
    end;
end;

end.