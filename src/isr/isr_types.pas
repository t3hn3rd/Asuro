//  Copyright 2021 Kieron Morris
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

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