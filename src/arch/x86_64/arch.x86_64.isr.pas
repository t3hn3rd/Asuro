// Copyright 2026 Aaron Hance
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

unit arch.x86_64.isr;

interface

procedure init;
procedure UnitTest;
procedure testFatal(vector: uint32);

implementation

uses debug.early, arch.x86_64.irq, arch.x86_64.context;

type
    TGate = packed record
        offsetLow, selector: uint16;
        ist, attributes: uint8;
        offsetMiddle: uint16;
        offsetHigh, reserved: uint32;
    end;
    TDescriptorPointer = packed record
        limit: uint16;
        base: uint64;
    end;
    TTSS = packed record
        reserved0: uint32;
        rsp0, rsp1, rsp2, reserved1: uint64;
        ist: array[0..6] of uint64;
        reserved2: uint64;
        reserved3, ioMapBase: uint16;
    end;
    TTSSDescriptor = packed record
        limitLow, baseLow: uint16;
        baseMiddle, access, flags, baseHigh: uint8;
        baseUpper, reserved: uint32;
    end;

var
    { Hardware tables must exist before the heap. Fixed bounded reservations,
      not per-fault allocations; GRUB clears their BSS storage. }
    gates: array[0..255] of TGate;
    idtr: TDescriptorPointer;
    tss: TTSS;
    tssDescriptor: TTSSDescriptor; external name 'bootstrap_tss_descriptor';
    entryTable: array[0..255] of uint64; external name 'x64_isr_table';
    kernelStackTop: uint8; external name 'stack_top';
    dfBottom: uint8; external name 'x64_df_stack_bottom';
    dfTop: uint8; external name 'x64_df_stack_top';
    nmiTop: uint8; external name 'x64_nmi_stack_top';
    mcTop: uint8; external name 'x64_mc_stack_top';
    breakpointReturn: uint8; external name 'x64_test_breakpoint_return';
    expectedRSP: uint64; external name 'x64_test_expected_rsp';
    pageFaultInstruction: uint8; external name 'x64_test_page_fault_instruction';
    pageFaultReturn: uint8; external name 'x64_test_page_fault_return';
    expectedTest: uint32;
    breakpointValid, pageFaultValid, fatalActive: boolean;

function testBreakpoint: uint32; cdecl; external name 'x64_test_breakpoint';

procedure testPageFault; cdecl; external name 'x64_test_page_fault';

procedure testInvalidOpcode; cdecl; external name 'x64_test_invalid_opcode';

procedure testDoubleFault; cdecl; external name 'x64_test_double_fault';

procedure loadTables(descriptor: pointer); assembler; nostackframe;
asm
    mov ax, $20
    ltr ax
    lidt [rdi]
end;

procedure init;
var
    i: uint32;
    address: uint64;
begin
    if (sizeof(TGate) <> 16) or (sizeof(TDescriptorPointer) <> 10) or
       (sizeof(TTSS) <> 104) or (sizeof(TTSSDescriptor) <> 16) or
       (sizeof(TFrame) <> 184) then begin
        puts('FAIL: x86_64 hardware table layout'#13#10);
        bootstrap_halt;
    end;
    tss.rsp0 := PtrUInt(@kernelStackTop);
    tss.ist[0] := PtrUInt(@dfTop);
    tss.ist[1] := PtrUInt(@nmiTop);
    tss.ist[2] := PtrUInt(@mcTop);
    tss.ioMapBase := sizeof(TTSS); { beyond limit: no I/O permission bitmap }
    address := PtrUInt(@tss);
    tssDescriptor.limitLow := sizeof(TTSS) - 1;
    tssDescriptor.baseLow := uint16(address);
    tssDescriptor.baseMiddle := uint8(address shr 16);
    tssDescriptor.access := $89; { present, DPL0, available 64-bit TSS }
    tssDescriptor.flags := 0;
    tssDescriptor.baseHigh := uint8(address shr 24);
    tssDescriptor.baseUpper := uint32(address shr 32);
    tssDescriptor.reserved := 0;
    for i := 0 to 255 do begin
        address := entryTable[i];
        gates[i].offsetLow := uint16(address);
        gates[i].selector := $18;
        gates[i].ist := 0;
        gates[i].attributes := $8E; { present DPL0 interrupt gate, clears IF }
        gates[i].offsetMiddle := uint16(address shr 16);
        gates[i].offsetHigh := uint32(address shr 32);
        gates[i].reserved := 0;
    end;
    gates[8].ist := 1;
    gates[2].ist := 2;
    gates[18].ist := 3;
    idtr.limit := sizeof(gates) - 1;
    idtr.base := PtrUInt(@gates);
    loadTables(@idtr);
    puts('ASURO x86_64: IDT/TSS ready; DF/NMI/MC emergency stacks installed'#13#10);
end;

procedure dispatch(frame: PFrame); cdecl; [public, alias: 'x64_exception_dispatch'];
const
    names: array[0..14] of pchar = (
        'R15', 'R14', 'R13', 'R12', 'R11', 'R10', 'R9', 'R8',
        'RDI', 'RSI', 'RBP', 'RBX', 'RDX', 'RCX', 'RAX');
var
    i: uint32;
    registers: PUInt64;
begin
    if (frame^.vector >= 32) and (frame^.vector <= 47) then begin
        arch.x86_64.irq.dispatch(frame^.vector);
        exit;
    end;
    registers := @frame^.r15;
    if (expectedTest = 1) and (frame^.vector = 3) and
       (frame^.rip = PtrUInt(@breakpointReturn)) then begin
        breakpointValid := (frame^.error = 0) and (frame^.cs = $18) and
            (frame^.ss = $10) and (frame^.rsp = expectedRSP) and
            ((frame^.flags and $401) = $401);
        for i := 0 to 14 do
            if registers[i] <> $1122334455667788 then breakpointValid := false;
        { Deliberately destroy FX state inside the handler: the assembly return
          path must restore it, not merely rely on Pascal avoiding SIMD. }
        asm
            fninit
            pxor xmm0, xmm0
            pxor xmm15, xmm15
        end;
        exit;
    end;
    if (expectedTest = 2) and (frame^.vector = 14) and
       (frame^.rip = PtrUInt(@pageFaultInstruction)) then begin
        pageFaultValid := (frame^.error = 2) and (frame^.cr2 = $100000000) and
            (frame^.cs = $18) and (frame^.ss = $10);
        frame^.rip := PtrUInt(@pageFaultReturn); { recover only this exact probe }
        exit;
    end;

    if fatalActive then begin
        puts('FATAL: nested exception while reporting'#13#10);
        field('VECTOR', frame^.vector);
        bootstrap_halt;
    end;
    fatalActive := true;
    puts('FATAL x86_64 exception: ');
    case frame^.vector of
        2: puts('NMI');
        6: puts('invalid opcode');
        8: puts('double fault');
        13: puts('general protection');
        14: puts('page fault');
        18: puts('machine check');
    else
        puts('unexpected vector');
    end;
    puts(#13#10);
    field('VECTOR', frame^.vector);
    field('ERROR', frame^.error);
    field('RIP', frame^.rip);
    field('CS', frame^.cs);
    field('RFLAGS', frame^.flags);
    field('RSP', frame^.rsp);
    field('SS', frame^.ss);
    field('CR2', frame^.cr2);
    field('FRAME', PtrUInt(frame));
    if (PtrUInt(frame) >= PtrUInt(@dfBottom)) and
       (PtrUInt(frame) + sizeof(TFrame) <= PtrUInt(@dfTop)) then
        puts('STACK=double-fault IST1'#13#10);
    for i := 0 to 14 do field(names[i], registers[i]);
    puts('HALTED: exception diagnostics complete'#13#10);
    bootstrap_halt;
end;

procedure UnitTest;
var
    passed, failed: uint32;
    result: uint32;

    procedure Assert(condition: boolean; name: pchar);
    begin
        if condition then begin
            inc(passed);
            puts('PASS: ');
        end else begin
            inc(failed);
            puts('FAIL: ');
        end;
        puts(name);
        puts(#13#10);
    end;
begin
    passed := 0;
    failed := 0;
    breakpointValid := false;
    expectedTest := 1;
    result := testBreakpoint;
    expectedTest := 0;
    Assert(breakpointValid and (result = 1),
        'INT3 frame, GPRs, RFLAGS, x87/SSE and IRETQ');
    pageFaultValid := false;
    expectedTest := 2;
    testPageFault;
    expectedTest := 0;
    Assert(pageFaultValid, 'page-fault error code, CR2 and IRETQ recovery');
    field('EXCEPTION_TESTS_PASSED', passed);
    field('EXCEPTION_TESTS_FAILED', failed);
    if failed <> 0 then bootstrap_halt;
end;

procedure testFatal(vector: uint32);
begin
    puts('TEST: deliberate fatal exception'#13#10);
    case vector of
        6: testInvalidOpcode;
        14: testPageFault;
        8: testDoubleFault;
    end;
    puts('FAIL: fatal exception returned'#13#10);
    bootstrap_halt;
end;

end.
