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
	CPU - CPU Structures & Utility/Capabilities Functions.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit arch.x86.cpu;

interface

uses
    core.util, arch.x86.util, driver.timer.rtc, io.stdio;

type
    PCapabilities_Old = ^TCapabilities_Old;
    TCapabilities_Old = bitpacked record
        FPU   : Boolean;  
        VME   : Boolean;  
        DE    : Boolean;  
        PSE   : Boolean;  
        TSC   : Boolean;  
        MSR   : Boolean;  
        PAE   : Boolean;  
        MCE   : Boolean;  
        CX8   : Boolean;  
        APIC  : Boolean;
        RESV0 : Boolean;  
        SEP   : Boolean; 
        MTRR  : Boolean; 
        PGE   : Boolean; 
        MCA   : Boolean; 
        CMOV  : Boolean; 
        PAT   : Boolean; 
        PSE36 : Boolean; 
        PSN   : Boolean; 
        CLF   : Boolean; 
        RESV1 : Boolean;
        DTES  : Boolean;  
        ACPI  : Boolean;  
        MMX   : Boolean;  
        FXSR  : Boolean;  
        SSE   : Boolean;  
        SSE2  : Boolean;  
        SS    : Boolean;  
        HTT   : Boolean;  
        TM1   : Boolean;  
        IA64  : Boolean; 
        PBE   : Boolean;
    end;
    PCapabilities_New = ^TCapabilities_New;
    TCapabilities_New = bitpacked record
        SSE3         : Boolean; 
        PCLMUL       : Boolean;
        DTES64       : Boolean;
        MONITOR      : Boolean;  
        DS_CPL       : Boolean;  
        VMX          : Boolean;  
        SMX          : Boolean;  
        EST          : Boolean;  
        TM2          : Boolean;  
        SSSE3        : Boolean;  
        CID          : Boolean;
        RESV0        : Boolean;
        FMA          : Boolean;
        CX16         : Boolean; 
        ETPRD        : Boolean; 
        PDCM         : Boolean;
        RESV1        : Boolean; 
        PCIDE        : Boolean; 
        DCA          : Boolean; 
        SSE4_1       : Boolean; 
        SSE4_2       : Boolean; 
        x2APIC       : Boolean; 
        MOVBE        : Boolean; 
        POPCNT       : Boolean; 
        RESV2        : Boolean;
        AES          : Boolean; 
        XSAVE        : Boolean; 
        OSXSAVE      : Boolean; 
        AVX          : Boolean;
        RESV3        : Boolean;
        RDRAND       : Boolean;
        RESV5        : Boolean;
    end;
    TClockSpeed = record
        Hz  : uint32;
        KHz : uint32;
        MHz : uint32;
        GHz : uint32;
    end;
    TCPUID = record
        ClockSpeed    : TClockSpeed;
        Identifier    : Array[0..12] of Char;
        Capabilities0 : PCapabilities_Old;
        Capabilities1 : PCapabilities_New;
    end;

var
    CPUID            : TCPUID;
    CAP_OLD, CAP_NEW : uint32;

procedure init();
procedure Terminal_Command_CPU(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);

implementation

procedure getCPUIdentifier;
var
    id0, id1, id2 : uint32;
    id : pchar;
    i : uint32;

begin
    asm
        PUSH EAX
        PUSH EBX
        PUSH ECX
        PUSH EDX
        MOV EAX, 0
        CPUID
        MOV id0, EBX
        MOV id1, EDX
        MOV id2, ECX
        POP EDX
        POP ECX
        POP EBX
        POP EAX
    end;
    CPUID.Identifier[12]:= char(0);
    id:= pchar(@id0);
    for i:=0 to 3 do begin
        CPUID.Identifier[0+i]:= id[i];
    end;
    id:= pchar(@id1);
    for i:=0 to 3 do begin
        CPUID.Identifier[4+i]:= id[i];
    end;
    id:= pchar(@id2);
    for i:=0 to 3 do begin
        CPUID.Identifier[8+i]:= id[i];
    end;
end;

procedure getCPUCapabilities;
begin
    asm
        PUSH EAX
        PUSH EBX
        PUSH ECX
        PUSH EDX
        MOV EAX, 1
        CPUID
        MOV CAP_OLD, EDX
        MOV CAP_NEW, ECX
        POP EDX
        POP ECX
        POP EBX
        POP EAX
    end;
end;

procedure getCPUClockSpeed;
var
    t1, t2 : TDateTime;
    c1, c2 : uint64;
    c : uint32;
    
begin
    c:= 0;
    if CPUID.Capabilities0^.TSC then begin
        t1:= getDateTime;
        t2:= getDateTime;
        c1:= getTSC;
        while (t1.Seconds = t2.Seconds) do begin
            t2:= getDateTime;
            c1:= getTSC;
        end;
        t1:= getDateTime;
        t2:= getDateTime;
        while (t1.Seconds = t2.Seconds) do begin
            t2:= getDateTime;
        end;
        c2:= getTSC;
        c:= c2 - c1;
    end;
    CPUID.ClockSpeed.Hz:= c;
    CPUID.ClockSpeed.KHz:= CPUID.ClockSpeed.Hz div 1000;
    CPUID.ClockSpeed.MHz:= CPUID.ClockSpeed.KHz div 1000;
    CPUID.ClockSpeed.GHz:= CPUID.ClockSpeed.MHz div 1000;
end;

procedure printCapabilities(outbuf : POutBuf);
begin
    { Old Capabilities }
    if CPUID.Capabilities0^.FPU     then io.stdio.bufWriteStr(outbuf, 'FPU');
    if CPUID.Capabilities0^.VME     then io.stdio.bufWriteStr(outbuf, ', VME');
    if CPUID.Capabilities0^.DE      then io.stdio.bufWriteStr(outbuf, ', DE');
    if CPUID.Capabilities0^.PSE     then io.stdio.bufWriteStr(outbuf, ', PSE');
    if CPUID.Capabilities0^.TSC     then io.stdio.bufWriteStr(outbuf, ', TSC');
    if CPUID.Capabilities0^.MSR     then io.stdio.bufWriteStr(outbuf, ', MSR');
    if CPUID.Capabilities0^.PAE     then io.stdio.bufWriteStr(outbuf, ', PAE');
    if CPUID.Capabilities0^.MCE     then io.stdio.bufWriteStr(outbuf, ', MCE');
    if CPUID.Capabilities0^.CX8     then io.stdio.bufWriteStr(outbuf, ', CX8');
    if CPUID.Capabilities0^.APIC    then io.stdio.bufWriteStr(outbuf, ', APIC');
    if CPUID.Capabilities0^.SEP     then io.stdio.bufWriteStr(outbuf, ', SEP');
    if CPUID.Capabilities0^.MTRR    then io.stdio.bufWriteStr(outbuf, ', MTRR');
    if CPUID.Capabilities0^.PGE     then io.stdio.bufWriteStr(outbuf, ', PGE');
    if CPUID.Capabilities0^.MCA     then io.stdio.bufWriteStr(outbuf, ', MCA');
    if CPUID.Capabilities0^.CMOV    then io.stdio.bufWriteStr(outbuf, ', CMOV');
    if CPUID.Capabilities0^.PAT     then io.stdio.bufWriteStr(outbuf, ', PAT');
    if CPUID.Capabilities0^.PSE36   then io.stdio.bufWriteStr(outbuf, ', PSE36');
    if CPUID.Capabilities0^.PSN     then io.stdio.bufWriteStr(outbuf, ', PSN');
    if CPUID.Capabilities0^.CLF     then io.stdio.bufWriteStr(outbuf, ', CLF');
    if CPUID.Capabilities0^.DTES    then io.stdio.bufWriteStr(outbuf, ', DTES');
    if CPUID.Capabilities0^.ACPI    then io.stdio.bufWriteStr(outbuf, ', ACPI');
    if CPUID.Capabilities0^.MMX     then io.stdio.bufWriteStr(outbuf, ', MMX');
    if CPUID.Capabilities0^.FXSR    then io.stdio.bufWriteStr(outbuf, ', FXSR');
    if CPUID.Capabilities0^.SSE     then io.stdio.bufWriteStr(outbuf, ', SSE');
    if CPUID.Capabilities0^.SSE2    then io.stdio.bufWriteStr(outbuf, ', SSE2');
    if CPUID.Capabilities0^.SS      then io.stdio.bufWriteStr(outbuf, ', SS');
    if CPUID.Capabilities0^.HTT     then io.stdio.bufWriteStr(outbuf, ', HTT');
    if CPUID.Capabilities0^.TM1     then io.stdio.bufWriteStr(outbuf, ', TM1');
    if CPUID.Capabilities0^.IA64    then io.stdio.bufWriteStr(outbuf, ', IA64');
    if CPUID.Capabilities0^.PBE     then io.stdio.bufWriteStr(outbuf, ', PBE');
    { Newer Capabilities }
    if CPUID.Capabilities1^.SSE3    then io.stdio.bufWriteStr(outbuf, ', SSE3');
    if CPUID.Capabilities1^.PCLMUL  then io.stdio.bufWriteStr(outbuf, ', PCLMUL');
    if CPUID.Capabilities1^.DTES64  then io.stdio.bufWriteStr(outbuf, ', DTES64');
    if CPUID.Capabilities1^.MONITOR then io.stdio.bufWriteStr(outbuf, ', MONITOR');
    if CPUID.Capabilities1^.DS_CPL  then io.stdio.bufWriteStr(outbuf, ', DS_CPL');
    if CPUID.Capabilities1^.VMX     then io.stdio.bufWriteStr(outbuf, ', VMX');
    if CPUID.Capabilities1^.SMX     then io.stdio.bufWriteStr(outbuf, ', SMX');
    if CPUID.Capabilities1^.EST     then io.stdio.bufWriteStr(outbuf, ', EST');
    if CPUID.Capabilities1^.TM2     then io.stdio.bufWriteStr(outbuf, ', TM2');
    if CPUID.Capabilities1^.SSSE3   then io.stdio.bufWriteStr(outbuf, ', SSSE3');
    if CPUID.Capabilities1^.CID     then io.stdio.bufWriteStr(outbuf, ', CID');
    if CPUID.Capabilities1^.FMA     then io.stdio.bufWriteStr(outbuf, ', FMA');
    if CPUID.Capabilities1^.CX16    then io.stdio.bufWriteStr(outbuf, ', CX16');
    if CPUID.Capabilities1^.ETPRD   then io.stdio.bufWriteStr(outbuf, ', ETPRD');
    if CPUID.Capabilities1^.PDCM    then io.stdio.bufWriteStr(outbuf, ', PDCM');
    if CPUID.Capabilities1^.PCIDE   then io.stdio.bufWriteStr(outbuf, ', PCIDE');
    if CPUID.Capabilities1^.DCA     then io.stdio.bufWriteStr(outbuf, ', DCA');
    if CPUID.Capabilities1^.SSE4_1  then io.stdio.bufWriteStr(outbuf, ', SSE4_1');
    if CPUID.Capabilities1^.SSE4_2  then io.stdio.bufWriteStr(outbuf, ', SSE4_2');
    if CPUID.Capabilities1^.x2APIC  then io.stdio.bufWriteStr(outbuf, ', x2APIC');
    if CPUID.Capabilities1^.MOVBE   then io.stdio.bufWriteStr(outbuf, ', MOVBE');
    if CPUID.Capabilities1^.POPCNT  then io.stdio.bufWriteStr(outbuf, ', POPCNT');
    if CPUID.Capabilities1^.AES     then io.stdio.bufWriteStr(outbuf, ', AES');
    if CPUID.Capabilities1^.XSAVE   then io.stdio.bufWriteStr(outbuf, ', XSAVE');
    if CPUID.Capabilities1^.OSXSAVE then io.stdio.bufWriteStr(outbuf, ', OSXSAVE');
    if CPUID.Capabilities1^.AVX     then io.stdio.bufWriteStr(outbuf, ', AVX');
    if CPUID.Capabilities1^.RDRAND  then io.stdio.bufWriteStr(outbuf, ', RDRAND');
    io.stdio.bufWriteStrLn(outbuf, ' ');
end;

procedure Terminal_Command_CPU(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin
    io.stdio.bufWriteStr(stdout_buf, 'Vendor: ');
    io.stdio.bufWriteStrLn(stdout_buf, @CPUID.Identifier[0]);
    io.stdio.bufWriteStr(stdout_buf, 'CPU Clock: ');
    io.stdio.bufWriteInt(stdout_buf, CPUID.ClockSpeed.MHz);
    io.stdio.bufWriteStrLn(stdout_buf, 'MHz');
    io.stdio.bufWriteStr(stdout_buf, 'CPU Capabilities: ');
    printCapabilities(stdout_buf);
end;

procedure enableSSE();
begin
    If CPUID.Capabilities0^.SSE then begin
        asm
            MOV EAX, CR0
            AND AX, $FFFB
            OR AX, $2
            MOV CR0, EAX
            MOV EAX, CR4
            OR AX, 3 shl 9
            MOV CR4, EAX
        end;
    end;
end;

procedure enableAVX();
begin
    if CPUID.Capabilities1^.AVX and CPUID.Capabilities1^.XSAVE then begin
        { Enable OSXSAVE in CR4 (bit 18) - required before XGETBV/XSETBV }
        asm
            MOV EAX, CR4
            OR EAX, (1 shl 18)
            MOV CR4, EAX
        end;
        { Set XCR0 bits: x87 (0) + SSE (1) + AVX (2) }
        asm
            PUSH EAX
            PUSH ECX
            PUSH EDX
            XOR ECX, ECX
            db $0F
            db $01
            db $D0
            OR EAX, 7
            db $0F
            db $01
            db $D1
            POP EDX
            POP ECX
            POP EAX
        end;
    end;
end;

procedure init();
begin
    CPUID.Capabilities0:= PCapabilities_Old(@CAP_OLD);
    CPUID.Capabilities1:= PCapabilities_New(@CAP_NEW); 
    getCPUIdentifier;
    getCPUCapabilities;
    getCPUClockSpeed;
    enableSSE;
    enableAVX;
end;

end.