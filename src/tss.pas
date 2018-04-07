{ ************************************************
  * Asuro
  * Unit: tss
  * Description: Representation of Kernel Space to
  *              Enable System Calls Via Interrupts.
  ************************************************
  * Author: K Morris
  * Contributors:
  ************************************************ }
unit tss;

interface

uses
    gdt,
    vmemorymanager,
    console;

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
    console.outputln('TSS','INIT BEGIN.');
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
    console.outputln('TSS','INIT END.');
end;

end.