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
	TSS - Task State Segment (stub).
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit tss;

interface

uses
    gdt,
    vmemorymanager,
    syslog;

type
    TTaskStateSegment = packed record
        link : uint16;
        link_h : uint16;

        esp0 : uint32;
        ss0 : uint16;
        ss0_h : uint16;

        esp1 : uint32;
        ss1 : uint16;
        ss1_h : uint16;

        esp2 : uint32;
        ss2 : uint16;
        ss2_h : uint16;

        cr3 : uint32;
        eip : uint32;
        eflags : uint32;

        eax : uint32;
        ecx : uint32;
        edx : uint32;
        ebx : uint32;

        esp : uint32;
        ebp : uint32;
        esi : uint32;
        edi : uint32;
        es : uint16;
        es_h : uint16;
        cs : uint16;
        cs_h : uint16;
        ss : uint16;
        ss_h : uint16;
        ds : uint16;
        ds_h : uint16;
        fs : uint16;
        fs_h : uint16;
        gs : uint16;
        gs_h : uint16;
        ldt : uint16;
        ldt_h : uint16;
        trap : uint16;
        iomap : uint16;
    end;
    PTaskStateSegment = ^TTaskStateSegment;

var
    TaskStateSegment : TTaskStateSegment;
    ptrTaskStateSegment : PTaskStateSegment = @TaskStateSegment;

procedure init;

implementation

procedure init;
var
    cESP : uint32;
    cCR3 : uint32;

begin
    syslog.logln('TSS','INIT BEGIN.');
    ptrTaskStateSegment^.ss0:= $08;
    ptrTaskStateSegment^.iomap:= sizeof(TTaskStateSegment)-1;
    asm
        MOV cESP, ESP 
        MOV EAX, CR3
        MOV cCR3, EAX
    end;
    ptrTaskStateSegment^.esp0:= cESP;
    ptrTaskStateSegment^.CR3:= cCR3;
    gdt.set_gate($05, uint32(ptrTaskStateSegment) - KERNEL_VIRTUAL_BASE, sizeof(TTaskStateSegment) - 1, $89, $40); //OFFSET: 40
    gdt.reload;
    asm
        mov AX, 40
        ltr AX
    end;
    syslog.logln('TSS','INIT END.');
end;

end.