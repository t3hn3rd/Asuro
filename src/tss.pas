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
    end;
    PTaskStateSegment = ^TTaskStateSegment;

var
    TaskStateSegment : TTaskStateSegment;
    ptrTaskStateSegment : PTaskStateSegment = @TaskStateSegment;

procedure init;

implementation

procedure init;
var
    i : uint32;
    cESP : uint32;

begin
    console.writestringln('A');
    i:=KERNEL_PAGE_NUMBER+4;
    console.writestringln('B');
    while not vmemorymanager.new_page(i) do begin
        i:= i + 1;
    end;
    console.writestringln('C');
    ptrTaskStateSegment:= PTaskStateSegment(i SHL 22);
    console.writestringln('D');
    ptrTaskStateSegment^.SS0:= $10;
    console.writestringln('E');
    ptrTaskStateSegment^.ESP0:= $00;
    console.writestringln('F');
    ptrTaskStateSegment^.IOPBOffset:= sizeof(TTaskStateSegment);
    console.writestringln('G');
    gdt.set_gate($05, i SHL 22 - KERNEL_VIRTUAL_BASE, sizeof(TTaskStateSegment), $89, $40); //OFFSET: 40
    console.writestringln('H');
    asm
        MOV cESP, ESP 
    end;
    console.writestringln('I');
    ptrTaskStateSegment^.ESP0:= cESP;
    console.writestringln('J');
    asm
        mov AX, 40
        ltr AX
    end;
    console.writestringln('K');
end;

end.