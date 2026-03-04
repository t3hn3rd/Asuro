{
    V86 - Virtual 8086 Mode Monitor.

    Provides a generic v86_int API for executing real-mode BIOS interrupts
    from protected mode. Handles GP traps from V86 mode with instruction
    emulation (INT, IRET, CLI, STI, PUSHF, POPF, IN, OUT, HLT, plus 0x66
    operand-size prefix for PUSHFD/POPFD and 32-bit IO).

    Usage:
        var regs: TV86Regs;
        regs.EAX := $4F02;   // VBE set mode
        regs.EBX := mode;
        v86_int($10, regs);  // Call INT 10h
        // Results in regs.EAX etc.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit v86;

interface

uses
    util, syslog, tracer, vmemorymanager, tss, idt, isr_types;

const
    { V86 EFLAGS: VM=1 ($20000), IOPL=3 ($3000), IF=0 }
    V86_EFLAGS      = $23000;
    { Thunk location in low memory (physical 0x7C00, free after boot) }
    V86_THUNK_ADDR  = $7C00;
    { V86 real-mode stack at SS:SP = 0000:8000 (grows down from 0x8000) }
    V86_STACK_SEG   = $0000;
    V86_STACK_PTR   = $8000;
    { INT 0xFF = exit sentinel }
    V86_EXIT_INT    = $FF;
    { Size of the ring-0 stack used for V86 GPF handling }
    V86_R0_STACK_SIZE = 4096;

type
    { Register state for V86 BIOS calls }
    TV86Regs = record
        EAX, EBX, ECX, EDX : uint32;
        ESI, EDI, EBP      : uint32;
        DS, ES, FS, GS     : uint16;
    end;
    PV86Regs = ^TV86Regs;

    { V86 exception frame pushed by CPU on #GP from V86 mode,
      preceded by our PUSHAD. Layout matches stack after PUSHAD + CPU push. }
    TV86GPFFrame = packed record
        { Error code pushed by CPU }
        ErrorCode   : uint32;
        { Return state }
        EIP         : uint32;
        CS          : uint32;
        EFLAGS      : uint32;
        { Ring transition state }
        ESP         : uint32;
        SS          : uint32;
        { V86 segment registers }
        ES          : uint32;
        DS          : uint32;
        FS          : uint32;
        GS          : uint32;
    end;
    PV86GPFFrame = ^TV86GPFFrame;

procedure init;
function v86_int(intNo : uint8; var regs : TV86Regs) : boolean;

implementation

var
    { Global V86 state }
    V86Active       : boolean = false;
    V86Success      : boolean = false;
    V86SavedESP     : uint32 = 0;
    V86SavedEBP     : uint32 = 0;
    V86ReturnAddr   : uint32 = 0;
    V86OldESP0      : uint32 = 0;
    V86RegsPtr      : PV86Regs = nil;
    V86ShadowIF     : boolean = true;

    { V86 IRET frame values (set before entry) }
    V86EntryEIP     : uint32 = 0;
    V86EntryCS      : uint32 = 0;
    V86EntryEFLAGS  : uint32 = 0;
    V86EntryESP     : uint32 = 0;
    V86EntrySS      : uint32 = 0;
    V86EntryES      : uint32 = 0;
    V86EntryDS      : uint32 = 0;
    V86EntryFS      : uint32 = 0;
    V86EntryGS      : uint32 = 0;

    { Input GPRs loaded before IRET }
    V86InEAX        : uint32 = 0;
    V86InEBX        : uint32 = 0;
    V86InECX        : uint32 = 0;
    V86InEDX        : uint32 = 0;
    V86InESI        : uint32 = 0;
    V86InEDI        : uint32 = 0;
    V86InEBP        : uint32 = 0;

    { Ring-0 stack for V86 exception handling }
    V86Ring0Stack   : array[0..V86_R0_STACK_SIZE - 1] of uint8;

{ ========================================================================= }
{ V86 real-mode memory helpers (access via kernel mapping at 0xC0000000)     }
{ ========================================================================= }

{ Read a byte from a real-mode linear address }
function rm_read8(linear : uint32) : uint8;
begin
    rm_read8 := PuByte(linear + KERNEL_VIRTUAL_BASE)^;
end;

{ Write a byte to a real-mode linear address }
procedure rm_write8(linear : uint32; val : uint8);
begin
    PuByte(linear + KERNEL_VIRTUAL_BASE)^ := val;
end;

{ Read a 16-bit word from a real-mode linear address }
function rm_read16(linear : uint32) : uint16;
begin
    rm_read16 := PUInt16(linear + KERNEL_VIRTUAL_BASE)^;
end;

{ Write a 16-bit word to a real-mode linear address }
procedure rm_write16(linear : uint32; val : uint16);
begin
    PUInt16(linear + KERNEL_VIRTUAL_BASE)^ := val;
end;

{ Read a 32-bit dword from a real-mode linear address }
function rm_read32(linear : uint32) : uint32;
begin
    rm_read32 := PUInt32(linear + KERNEL_VIRTUAL_BASE)^;
end;

{ Write a 32-bit dword to a real-mode linear address }
procedure rm_write32(linear : uint32; val : uint32);
begin
    PUInt32(linear + KERNEL_VIRTUAL_BASE)^ := val;
end;

{ Read byte at CS:IP + offset }
function read_ip(frame : PV86GPFFrame; offset : uint32) : uint8;
var
    linear : uint32;
begin
    linear := (frame^.CS and $FFFF) * 16 + ((frame^.EIP + offset) and $FFFF);
    read_ip := rm_read8(linear);
end;

{ Push a 16-bit word onto the V86 stack }
procedure v86_push16(frame : PV86GPFFrame; value : uint16);
var
    sp : uint32;
begin
    frame^.ESP := (frame^.ESP - 2) and $FFFF;
    sp := (frame^.SS and $FFFF) * 16 + frame^.ESP;
    rm_write16(sp, value);
end;

{ Pop a 16-bit word from the V86 stack }
function v86_pop16(frame : PV86GPFFrame) : uint16;
var
    sp : uint32;
begin
    sp := (frame^.SS and $FFFF) * 16 + frame^.ESP;
    v86_pop16 := rm_read16(sp);
    frame^.ESP := (frame^.ESP + 2) and $FFFF;
end;

{ Push a 32-bit dword onto the V86 stack }
procedure v86_push32(frame : PV86GPFFrame; value : uint32);
var
    sp : uint32;
begin
    frame^.ESP := (frame^.ESP - 4) and $FFFF;
    sp := (frame^.SS and $FFFF) * 16 + frame^.ESP;
    rm_write32(sp, value);
end;

{ Pop a 32-bit dword from the V86 stack }
function v86_pop32(frame : PV86GPFFrame) : uint32;
var
    sp : uint32;
begin
    sp := (frame^.SS and $FFFF) * 16 + frame^.ESP;
    v86_pop32 := rm_read32(sp);
    frame^.ESP := (frame^.ESP + 4) and $FFFF;
end;

{ ========================================================================= }
{ V86 GPF instruction emulator                                              }
{ ========================================================================= }

{ Handle a #GP from V86 mode. Called from the naked ISR with a pointer
  to the PUSHAD frame (GPRs) and the CPU exception frame (V86 segments).
  Returns 0 to continue V86, 1 to exit V86. }
function v86_emulate(gprs : PUInt32; frame : PV86GPFFrame) : uint32; cdecl;
var
    opcode      : uint8;
    intno       : uint8;
    ip_offset   : uint32;
    prefix66    : boolean;
    ivt_off     : uint16;
    ivt_seg     : uint16;
    ivt_addr    : uint32;
    port        : uint16;
    val8        : uint8;
    val16       : uint16;
    val32       : uint32;
    flags16     : uint16;

begin
    v86_emulate := 0;
    ip_offset := 0;
    prefix66 := false;

    { Scan past prefixes }
    opcode := read_ip(frame, ip_offset);

    { Handle operand-size override prefix }
    if opcode = $66 then begin
        prefix66 := true;
        ip_offset := ip_offset + 1;
        opcode := read_ip(frame, ip_offset);
    end;

    { Handle segment override prefixes (just skip them) }
    while (opcode = $26) or (opcode = $2E) or (opcode = $36) or
          (opcode = $3E) or (opcode = $64) or (opcode = $65) do begin
        ip_offset := ip_offset + 1;
        opcode := read_ip(frame, ip_offset);
    end;

    { Handle LOCK/REP prefixes (skip) }
    while (opcode = $F0) or (opcode = $F2) or (opcode = $F3) do begin
        ip_offset := ip_offset + 1;
        opcode := read_ip(frame, ip_offset);
    end;

    case opcode of

        { ---- INT n (CD nn) ---- }
        $CD: begin
            intno := read_ip(frame, ip_offset + 1);

            { Check for exit sentinel INT 0xFF }
            if intno = V86_EXIT_INT then begin
                { Copy GPR results back to the caller's TV86Regs }
                { GPRs on stack (PUSHAD order): EDI=0, ESI=4, EBP=8, _ESP=12, EBX=16, EDX=20, ECX=24, EAX=28 }
                if V86RegsPtr <> nil then begin
                    V86RegsPtr^.EAX := gprs[7]; { offset 28 = EAX }
                    V86RegsPtr^.EBX := gprs[4]; { offset 16 = EBX }
                    V86RegsPtr^.ECX := gprs[6]; { offset 24 = ECX }
                    V86RegsPtr^.EDX := gprs[5]; { offset 20 = EDX }
                    V86RegsPtr^.ESI := gprs[1]; { offset 4  = ESI }
                    V86RegsPtr^.EDI := gprs[0]; { offset 0  = EDI }
                    V86RegsPtr^.EBP := gprs[2]; { offset 8  = EBP }
                    V86RegsPtr^.DS  := frame^.DS and $FFFF;
                    V86RegsPtr^.ES  := frame^.ES and $FFFF;
                    V86RegsPtr^.FS  := frame^.FS and $FFFF;
                    V86RegsPtr^.GS  := frame^.GS and $FFFF;
                end;
                V86Success := true;
                V86Active := false;
                v86_emulate := 1; { Signal exit }
                exit;
            end;

            { Normal INT n: push FLAGS, CS, IP onto V86 stack, redirect to IVT handler }
            { Advance past: prefixes + CD nn }
            frame^.EIP := frame^.EIP + ip_offset + 2;

            { Push current FLAGS (16-bit), CS, IP onto V86 stack }
            flags16 := frame^.EFLAGS and $FFFF;
            if V86ShadowIF then
                flags16 := flags16 or $0200
            else
                flags16 := flags16 and (not uint16($0200));
            v86_push16(frame, flags16);
            v86_push16(frame, frame^.CS and $FFFF);
            v86_push16(frame, frame^.EIP and $FFFF);

            { Read IVT entry: 4 bytes at intno * 4 }
            ivt_addr := uint32(intno) * 4;
            ivt_off := rm_read16(ivt_addr);
            ivt_seg := rm_read16(ivt_addr + 2);

            { Redirect execution to the BIOS handler }
            frame^.EIP := ivt_off;
            frame^.CS  := ivt_seg;

            { Clear IF in shadow (BIOS handlers typically CLI first) }
            V86ShadowIF := false;
        end;

        { ---- IRET (CF) ---- }
        $CF: begin
            if prefix66 then begin
                { 32-bit IRETD }
                frame^.EIP    := v86_pop32(frame);
                frame^.CS     := v86_pop32(frame);
                val32         := v86_pop32(frame);
                { Preserve VM bit, update shadow IF }
                V86ShadowIF := (val32 and $0200) <> 0;
                frame^.EFLAGS := (frame^.EFLAGS and $FFFF0000) or (val32 and $FFFF);
                frame^.EFLAGS := frame^.EFLAGS or $20000; { Keep VM=1 }
            end else begin
                { 16-bit IRET }
                frame^.EIP    := v86_pop16(frame);
                frame^.CS     := v86_pop16(frame);
                flags16       := v86_pop16(frame);
                V86ShadowIF := (flags16 and $0200) <> 0;
                frame^.EFLAGS := (frame^.EFLAGS and $FFFF0000) or flags16;
                frame^.EFLAGS := frame^.EFLAGS or $20000; { Keep VM=1 }
            end;
        end;

        { ---- CLI (FA) ---- }
        $FA: begin
            V86ShadowIF := false;
            frame^.EIP := frame^.EIP + ip_offset + 1;
        end;

        { ---- STI (FB) ---- }
        $FB: begin
            V86ShadowIF := true;
            frame^.EIP := frame^.EIP + ip_offset + 1;
        end;

        { ---- PUSHF / PUSHFD (9C) ---- }
        $9C: begin
            flags16 := frame^.EFLAGS and $FFFF;
            if V86ShadowIF then
                flags16 := flags16 or $0200
            else
                flags16 := flags16 and (not uint16($0200));
            if prefix66 then begin
                val32 := frame^.EFLAGS and $00FCFFFF; { Clear VM, IOPL }
                if V86ShadowIF then
                    val32 := val32 or $0200
                else
                    val32 := val32 and (not uint32($0200));
                v86_push32(frame, val32);
            end else begin
                v86_push16(frame, flags16);
            end;
            frame^.EIP := frame^.EIP + ip_offset + 1;
        end;

        { ---- POPF / POPFD (9D) ---- }
        $9D: begin
            if prefix66 then begin
                val32 := v86_pop32(frame);
                V86ShadowIF := (val32 and $0200) <> 0;
                frame^.EFLAGS := (frame^.EFLAGS and $FFFF0000) or (val32 and $FFFF);
                frame^.EFLAGS := frame^.EFLAGS or $20000; { Keep VM=1 }
            end else begin
                flags16 := v86_pop16(frame);
                V86ShadowIF := (flags16 and $0200) <> 0;
                frame^.EFLAGS := (frame^.EFLAGS and $FFFF0000) or flags16;
                frame^.EFLAGS := frame^.EFLAGS or $20000; { Keep VM=1 }
            end;
            frame^.EIP := frame^.EIP + ip_offset + 1;
        end;

        { ---- IN AL, imm8 (E4) ---- }
        $E4: begin
            port := read_ip(frame, ip_offset + 1);
            asm
                mov dx, port
                in al, dx
                mov val8, al
            end;
            { Store in EAX low byte (GPR array index 7 = EAX) }
            gprs[7] := (gprs[7] and $FFFFFF00) or val8;
            frame^.EIP := frame^.EIP + ip_offset + 2;
        end;

        { ---- IN AX/EAX, imm8 (E5) ---- }
        $E5: begin
            port := read_ip(frame, ip_offset + 1);
            if prefix66 then begin
                asm
                    mov dx, port
                    in eax, dx
                    mov val32, eax
                end;
                gprs[7] := val32;
            end else begin
                asm
                    mov dx, port
                    in ax, dx
                    mov val16, ax
                end;
                gprs[7] := (gprs[7] and $FFFF0000) or val16;
            end;
            frame^.EIP := frame^.EIP + ip_offset + 2;
        end;

        { ---- IN AL, DX (EC) ---- }
        $EC: begin
            port := gprs[5] and $FFFF; { EDX low 16 bits }
            asm
                mov dx, port
                in al, dx
                mov val8, al
            end;
            gprs[7] := (gprs[7] and $FFFFFF00) or val8;
            frame^.EIP := frame^.EIP + ip_offset + 1;
        end;

        { ---- IN AX/EAX, DX (ED) ---- }
        $ED: begin
            port := gprs[5] and $FFFF;
            if prefix66 then begin
                asm
                    mov dx, port
                    in eax, dx
                    mov val32, eax
                end;
                gprs[7] := val32;
            end else begin
                asm
                    mov dx, port
                    in ax, dx
                    mov val16, ax
                end;
                gprs[7] := (gprs[7] and $FFFF0000) or val16;
            end;
            frame^.EIP := frame^.EIP + ip_offset + 1;
        end;

        { ---- OUT imm8, AL (E6) ---- }
        $E6: begin
            port := read_ip(frame, ip_offset + 1);
            val8 := gprs[7] and $FF;
            asm
                mov dx, port
                mov al, val8
                out dx, al
            end;
            frame^.EIP := frame^.EIP + ip_offset + 2;
        end;

        { ---- OUT imm8, AX/EAX (E7) ---- }
        $E7: begin
            port := read_ip(frame, ip_offset + 1);
            if prefix66 then begin
                val32 := gprs[7];
                asm
                    mov dx, port
                    mov eax, val32
                    out dx, eax
                end;
            end else begin
                val16 := gprs[7] and $FFFF;
                asm
                    mov dx, port
                    mov ax, val16
                    out dx, ax
                end;
            end;
            frame^.EIP := frame^.EIP + ip_offset + 2;
        end;

        { ---- OUT DX, AL (EE) ---- }
        $EE: begin
            port := gprs[5] and $FFFF;
            val8 := gprs[7] and $FF;
            asm
                mov dx, port
                mov al, val8
                out dx, al
            end;
            frame^.EIP := frame^.EIP + ip_offset + 1;
        end;

        { ---- OUT DX, AX/EAX (EF) ---- }
        $EF: begin
            port := gprs[5] and $FFFF;
            if prefix66 then begin
                val32 := gprs[7];
                asm
                    mov dx, port
                    mov eax, val32
                    out dx, eax
                end;
            end else begin
                val16 := gprs[7] and $FFFF;
                asm
                    mov dx, port
                    mov ax, val16
                    out dx, ax
                end;
            end;
            frame^.EIP := frame^.EIP + ip_offset + 1;
        end;

        { ---- HLT (F4) ---- }
        $F4: begin
            { Just skip it — V86 code halting is meaningless for us }
            frame^.EIP := frame^.EIP + ip_offset + 1;
        end;

    else begin
        { Unhandled opcode — log and signal exit with failure }
        syslog.log('V86', 'Unhandled opcode: $');
        syslog.writehexln(opcode);
        syslog.log('V86', 'At CS:IP = ');
        syslog.writehex(frame^.CS);
        syslog.writestring(':');
        syslog.writehexln(frame^.EIP);
        V86Success := false;
        V86Active := false;
        v86_emulate := 1; { Exit V86 }
    end;

    end; { case }
end;

{ ========================================================================= }
{ Naked GPF handler — replaces IDT gate 13                                  }
{ ========================================================================= }

procedure v86_chain_gpf; cdecl;
begin
    BSOD('GPF', 'General Protection Fault.');
    halt_and_catch_fire;
end;

procedure v86_gpf_isr; assembler; nostackframe;
asm
    { Stack on entry from V86 #GP (CPU pushes in privilege-change + V86 order):
        [ESP+36] GS
        [ESP+32] FS
        [ESP+28] DS
        [ESP+24] ES
        [ESP+20] SS
        [ESP+16] ESP (V86 SP)
        [ESP+12] EFLAGS (VM=1)
        [ESP+8]  CS
        [ESP+4]  EIP
        [ESP+0]  Error Code (0)

      Stack on entry from normal ring-0 #GP:
        [ESP+12] EFLAGS
        [ESP+8]  CS
        [ESP+4]  EIP
        [ESP+0]  Error Code
    }

    { Check if this came from V86 mode: EFLAGS.VM is at [ESP+12] }
    test dword ptr [esp + 12], $20000
    jnz @v86_handle

    { -------------------------------------------------------------------- }
    { Non-V86 GPF: set up kernel segments, BSOD and halt                  }
    { -------------------------------------------------------------------- }
    pushad
    mov ax, $10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    call v86_chain_gpf
    { v86_chain_gpf never returns (BSOD + halt) }

@v86_handle:
    { -------------------------------------------------------------------- }
    { V86 GPF: save all GPRs, call Pascal emulator                        }
    { -------------------------------------------------------------------- }
    pushad
    mov ax, $10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    { Compute arg pointers BEFORE pushing them onto the stack.
      ESP currently points to the PUSHAD frame (32 bytes).
      Exception frame (ErrorCode, EIP, CS, EFLAGS, ESP, SS, ES, DS, FS, GS)
      is at ESP + 32. }
    mov eax, esp            { arg1 = pointer to PUSHAD frame (GPR array) }
    lea ebx, [esp + 32]    { arg2 = pointer to V86 exception frame }

    { Push args for cdecl call: right-to-left (arg2 first, then arg1) }
    push ebx                { arg2: PV86GPFFrame }
    push eax                { arg1: PUInt32 (GPR array) }
    call v86_emulate
    add esp, 8              { caller cleans up 2 args (cdecl) }

    { EAX = 0: continue V86, EAX = 1: exit V86 }
    test eax, eax
    jnz @v86_exit

    { Continue V86: restore GPRs and IRETD back into V86 mode }
    popad
    add esp, 4              { skip error code }
    iretd

@v86_exit:
    { Exit V86: restore the saved protected-mode kernel context.
      TSS ESP0 is restored by the exit handler so that normal interrupts
      use the correct ring-0 stack again. }
    mov eax, dword ptr [V86OldESP0]
    mov ebx, dword ptr [ptrTaskStateSegment]
    mov dword ptr [ebx + 4], eax   { TTaskStateSegment.esp0 is at offset 4 }

    { Restore kernel stack frame and jump back into v86_int }
    mov esp, dword ptr [V86SavedESP]
    mov ebp, dword ptr [V86SavedEBP]
    jmp dword ptr [V86ReturnAddr]
end;

{ ========================================================================= }
{ V86 entry: build IRET frame and enter V86 mode                           }
{ ========================================================================= }

{ Write the thunk (INT n + INT FF) into low memory at V86_THUNK_ADDR }
procedure setup_thunk(intNo : uint8);
var
    addr : uint32;
begin
    addr := V86_THUNK_ADDR;
    rm_write8(addr + 0, $CD);      { INT }
    rm_write8(addr + 1, intNo);    { n }
    rm_write8(addr + 2, $CD);      { INT }
    rm_write8(addr + 3, V86_EXIT_INT); { 0xFF }
end;

{ The core v86_int function }
function v86_int(intNo : uint8; var regs : TV86Regs) : boolean;
begin
    push_trace('v86.v86_int');

    CLI;

    { Mark V86 active }
    V86Active := true;
    V86Success := false;
    V86ShadowIF := true;
    V86RegsPtr := @regs;

    { Save current TSS ESP0 }
    V86OldESP0 := tss.get_esp0;

    { Set TSS ESP0 to our dedicated ring-0 stack for V86 traps }
    tss.set_esp0(uint32(@V86Ring0Stack) + V86_R0_STACK_SIZE);

    { Write thunk code into physical memory at 0x7C00 }
    setup_thunk(intNo);

    { Set up the V86 IRET frame values }
    V86EntryEIP    := V86_THUNK_ADDR;               { CS:IP → 0000:7C00 }
    V86EntryCS     := V86_THUNK_ADDR shr 4;         { Segment for thunk }
    V86EntryEIP    := V86_THUNK_ADDR and $F;         { Offset within segment }
    V86EntryEFLAGS := V86_EFLAGS;                    { VM=1, IOPL=3 }
    V86EntryESP    := V86_STACK_PTR;                  { SP = 0x8000 }
    V86EntrySS     := V86_STACK_SEG;                  { SS = 0x0000 }
    V86EntryES     := regs.ES;
    V86EntryDS     := regs.DS;
    V86EntryFS     := regs.FS;
    V86EntryGS     := regs.GS;

    { Set up input GPRs }
    V86InEAX := regs.EAX;
    V86InEBX := regs.EBX;
    V86InECX := regs.ECX;
    V86InEDX := regs.EDX;
    V86InESI := regs.ESI;
    V86InEDI := regs.EDI;
    V86InEBP := regs.EBP;

    { Save kernel context and enter V86 mode.
      The exit handler will restore ESP/EBP and JMP to @v86_return. }
    asm
        { Save kernel stack state }
        mov dword ptr [V86SavedESP], esp
        mov dword ptr [V86SavedEBP], ebp

        { Save the return label address }
        lea eax, [@v86_return]
        mov dword ptr [V86ReturnAddr], eax

        { Build V86 IRET frame (CPU expects: GS, FS, DS, ES, SS, ESP, EFLAGS, CS, EIP) }
        push dword ptr [V86EntryGS]
        push dword ptr [V86EntryFS]
        push dword ptr [V86EntryDS]
        push dword ptr [V86EntryES]
        push dword ptr [V86EntrySS]
        push dword ptr [V86EntryESP]
        push dword ptr [V86EntryEFLAGS]
        push dword ptr [V86EntryCS]
        push dword ptr [V86EntryEIP]

        { Load GPRs for the BIOS call }
        mov eax, dword ptr [V86InEAX]
        mov ebx, dword ptr [V86InEBX]
        mov ecx, dword ptr [V86InECX]
        mov edx, dword ptr [V86InEDX]
        mov esi, dword ptr [V86InESI]
        mov edi, dword ptr [V86InEDI]
        mov ebp, dword ptr [V86InEBP]

        { Enter V86 mode — CPU pops EIP, CS, EFLAGS(VM=1), ESP, SS, ES, DS, FS, GS }
        iretd

        { V86 exit handler jumps here after restoring ESP/EBP }
    @v86_return:
    end;

    { We arrive here after V86 exit (registers already copied to V86RegsPtr by emulator) }
    { TSS ESP0 already restored by the exit handler }

    V86Active := false;
    v86_int := V86Success;

    STI;

    pop_trace;
end;

{ ========================================================================= }
{ Initialization                                                            }
{ ========================================================================= }

procedure init;
begin
    push_trace('v86.init');
    syslog.logln('V86', 'INIT BEGIN.');

    { Identity-map the first 4MB at virtual 0x00000000 with User bit.
      This allows V86 code to access the IVT, BDA, video ROM, and
      VGA memory as real-mode linear addresses go through paging. }
    vmemorymanager.map_page_user(0, 0);

    { Override IDT gate 13 (#GP) with our naked V86-aware handler }
    idt.set_gate(13, uint32(@v86_gpf_isr), $08, ISR_RING_0);

    syslog.logln('V86', 'INIT END.');
    pop_trace;
end;

end.
