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
    {
        Res1       : uint16;
        IOPBOffset : uint16;
        LDTR       : uint16;
        Res2       : uint16;
        GS         : uint16;
        Res3       : uint16;
        FS         : uint16;
        Res4       : uint16;
        DS         : uint16;
        Res5       : uint16;
        SS         : uint16;
        Res6       : uint16;
        CS         : uint16;
        Res7       : uint16;
        ES         : uint16;
        Res8       : uint16;
        EDI        : uint32;
        ESI        : uint32;
        EBP        : uint32;
        ESP        : uint32;
        EBX        : uint32;
        EDX        : uint32;
        ECX        : uint32;
        EAX        : uint32;
        EFLAGS     : uint32;
        EIP        : uint32;
        CR3        : uint32;
        SS2        : uint16;
        Res9       : uint16;
        SS1        : uint16;
        Res10      : uint16;
        SS0        : uint16;
        Res11      : uint16;
        ESP0       : uint32;
        LINK       : uint16;
        Res12      : uint16;
    }

    {
        Res12      : uint16;
        LINK       : uint16;
        ESP0       : uint32;
        Res11      : uint16;
        SS0        : uint16;
        Res10      : uint16;
        SS1        : uint16;
        Res9       : uint16;
        SS2        : uint16;
        CR3        : uint32;
        EIP        : uint32;
        EFLAGS     : uint32;
        EAX        : uint32;
        ECX        : uint32;
        EDX        : uint32;
        EBX        : uint32;
        ESP        : uint32;
        EBP        : uint32;
        ESI        : uint32;
        EDI        : uint32;
        Res8       : uint16;
        ES         : uint16;
        Res7       : uint16;
        CS         : uint16;
        Res6       : uint16;
        SS         : uint16;
        Res5       : uint16;
        DS         : uint16;
        Res4       : uint16;
        FS         : uint16;
        Res3       : uint16;
        GS         : uint16;
        Res2       : uint16;
        LDTR       : uint16;
        IOPBOffset : uint16;
        Res1       : uint16;
    }

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

begin
    ptrTaskStateSegment^.ss0:= $10;
    ptrTaskStateSegment^.iomap:= sizeof(TTaskStateSegment);
    gdt.set_gate($05, uint32(ptrTaskStateSegment) - KERNEL_VIRTUAL_BASE, sizeof(TTaskStateSegment), $89, $40); //OFFSET: 40
    asm
        MOV cESP, ESP 
    end;
    ptrTaskStateSegment^.esp0:= cESP;
    console.writestringln('A');
    asm
        mov AX, 40
        ltr AX
    end;
    console.writestringln('B');
end;

end.