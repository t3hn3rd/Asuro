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
	Global Descriptor Table - Data Structures & Interface.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit gdt;

interface

uses
    syslog;

type
    TGDT_Entry = packed record
        limit_low   : uint16;
        base_low    : uint16;
        base_middle : uint8;
        access      : uint8;
        granularity : uint8;
        base_high   : uint8;
    end;
    PGDT_Entry = ^TGDT_Entry;

    TGDT_Pointer = packed record
        limit : uint16;
        base  : uint32;
    end;

var
    gdt_entries : array[0..1023] of TGDT_Entry;
    gdt_pointer : TGDT_Pointer;

procedure init();
procedure set_gate(Gate_Number : uint32; Base : uint32; Limit : uint32; Access : uint8; Granularity : uint8);
procedure flush;
procedure reload;

implementation

procedure flush_gdt(gdt_pointer : uint32); assembler; nostackframe;
asm
    MOV EAX, gdt_pointer
    LGDT [EAX]
    MOV AX, $10
    MOV DS, AX
    MOV ES, AX
    MOV FS, AX
    MOV GS, AX
    MOV SS, AX
    db $EA          // Bypass stupid inline ASM restrictions-
    dw @@flush, $08 // by assembling the farjump instruction ourselves.                    
@@flush:            // It's just data, honest gov'.
end;

procedure flush;
begin
    syslog.logln('GDT','FLUSH.');
    flush_gdt(uint32(@gdt_pointer));
end;

procedure reload_gdt(gdt_ptr : uint32); assembler;
asm
    MOV EAX, gdt_ptr
    LGDT [EAX]
end;

procedure reload;
begin
    syslog.logln('GDT','RELOAD.');
    reload_gdt(uint32(@gdt_pointer));
end;

procedure set_gate(Gate_Number : uint32; Base : uint32; Limit : uint32; Access : uint8; Granularity : uint8);
var
    lLimit : uint32;

begin
    lLimit:= (Gate_Number + 1) * 8;
    lLimit:= lLimit - 1;
    if lLimit > gdt_pointer.limit then begin
        gdt_pointer.limit:= lLimit;
    end;
    gdt_entries[Gate_Number].base_low    := (Base AND $FFFF);
    gdt_entries[Gate_Number].base_middle := (Base SHR 16) AND $FF;
    gdt_entries[Gate_Number].base_high   := (Base SHR 24) AND $FF;
    gdt_entries[Gate_Number].limit_low   := (Limit AND $FFFF);
    gdt_entries[Gate_Number].granularity := ((Limit SHR 16) AND $0F) OR (Granularity AND $F0);
    gdt_entries[Gate_Number].access      := Access;    
    syslog.log('GDT','GATE ');
    syslog.writeint(Gate_Number);
    syslog.writestringln(' SET.');
end;

procedure init();
begin
    syslog.logln('GDT','INIT START.');
    gdt_pointer.limit:= 0;
    gdt_pointer.base  := uint32(@gdt_entries);  
    set_gate($00, $00, $00,       $00, $00); //OFFSET: 0
    set_gate($01, $00, $FFFFFFFF, $9A, $CF); //OFFSET: 8
    set_gate($02, $00, $FFFFFFFF, $92, $CF); //OFFSET: 16
    set_gate($03, $00, $FFFFFFFF, $FA, $CF); //OFFSET: 24
    set_gate($04, $00, $FFFFFFFF, $F2, $CF); //OFFSET: 32
    flush;
    syslog.logln('GDT','INIT END.');
end;

end.