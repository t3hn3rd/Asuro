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
	Interrupt Descriptor Table - Structures & Interface.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit idt;

interface

uses
    util, console;

const
     ISR_RING_0 = $8E;
     ISR_RING_1 = $AE;
     ISR_RING_2 = $CE;
     ISR_RING_3 = $EE;

type
    TIDT_Entry = packed record
        base_low  : uint16;
        selector  : uint16;
        always_0  : uint8;
        flags     : uint8;
        base_high : uint16; 
    end;
    PIDT_Entry = ^TIDT_Entry;

    TIDT_Pointer = packed record
        limit : uint16;
        base  : uint32;
    end;
    PIDT_Pointer = ^TIDT_Pointer;

var
    IDT_Entries : Array [0..255] of TIDT_Entry;
    IDT_Pointer : TIDT_Pointer;

procedure init();
procedure set_gate(Number : uint8; Base : uint32; Selector : uint16; Flags : uint8);

implementation

procedure load(idt_pointer : uint32); assembler; nostackframe;
asm
    MOV EAX, idt_pointer
    LIDT [EAX]
end;

procedure set_gate(Number : uint8; Base : uint32; Selector : uint16; Flags : uint8);
begin
    IDT_Entries[Number].base_high:= (Base and $FFFF0000) SHR 16;
    IDT_Entries[Number].base_low:= (Base and $0000FFFF);
    IDT_Entries[Number].selector:= Selector;
    IDT_Entries[Number].flags:= Flags;
    IDT_Entries[Number].always_0:= $00;
    console.output('IDT','GATE ');
    console.writeint(Number);
    console.writestringln(' SET.');
    load(uint32(@IDT_Pointer));
end;

procedure init();
begin
    console.outputln('IDT','INIT START.');
    IDT_Pointer.limit:= (sizeof(TIDT_Entry) * 256) - 1;
    IDT_Pointer.base:= uint32(@IDT_Entries);
    console.outputln('IDT','CLEAR.');
    util.memset(uint32(@IDT_Entries[0]), 0, sizeof(TIDT_Entry) * 256);
    console.outputln('IDT','LOAD.');
    load(uint32(@IDT_Pointer));
    console.outputln('IDT','INIT END.');
end;

end.