{ 
	CPU - CPU Structures & Utility/Capabilities Functions.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit cpu;

interface

uses
    console, util, RTC, terminal;

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

procedure printCapabilities(WND : HWND);
begin
    { Old Capabilities }
    if CPUID.Capabilities0^.FPU     then writestringWND('FPU', WND);
    if CPUID.Capabilities0^.VME     then writestringWND(', VME', WND);
    if CPUID.Capabilities0^.DE      then writestringWND(', DE', WND);
    if CPUID.Capabilities0^.PSE     then writestringWND(', PSE', WND);
    if CPUID.Capabilities0^.TSC     then writestringWND(', TSC', WND);
    if CPUID.Capabilities0^.MSR     then writestringWND(', MSR', WND);
    if CPUID.Capabilities0^.PAE     then writestringWND(', PAE', WND);
    if CPUID.Capabilities0^.MCE     then writestringWND(', MCE', WND);
    if CPUID.Capabilities0^.CX8     then writestringWND(', CX8', WND);
    if CPUID.Capabilities0^.APIC    then writestringWND(', APIC', WND);
    if CPUID.Capabilities0^.SEP     then writestringWND(', SEP', WND);
    if CPUID.Capabilities0^.MTRR    then writestringWND(', MTRR', WND);
    if CPUID.Capabilities0^.PGE     then writestringWND(', PGE', WND);
    if CPUID.Capabilities0^.MCA     then writestringWND(', MCA', WND);
    if CPUID.Capabilities0^.CMOV    then writestringWND(', CMOV', WND);
    if CPUID.Capabilities0^.PAT     then writestringWND(', PAT', WND);
    if CPUID.Capabilities0^.PSE36   then writestringWND(', PSE36', WND);
    if CPUID.Capabilities0^.PSN     then writestringWND(', PSN', WND);
    if CPUID.Capabilities0^.CLF     then writestringWND(', CLF', WND);
    if CPUID.Capabilities0^.DTES    then writestringWND(', DTES', WND);
    if CPUID.Capabilities0^.ACPI    then writestringWND(', ACPI', WND);
    if CPUID.Capabilities0^.MMX     then writestringWND(', MMX', WND);
    if CPUID.Capabilities0^.FXSR    then writestringWND(', FXSR', WND);
    if CPUID.Capabilities0^.SSE     then writestringWND(', SSE', WND);
    if CPUID.Capabilities0^.SSE2    then writestringWND(', SSE2', WND);
    if CPUID.Capabilities0^.SS      then writestringWND(', SS', WND);
    if CPUID.Capabilities0^.HTT     then writestringWND(', HTT', WND);
    if CPUID.Capabilities0^.TM1     then writestringWND(', TM1', WND);
    if CPUID.Capabilities0^.IA64    then writestringWND(', IA64', WND);
    if CPUID.Capabilities0^.PBE     then writestringWND(', PBE', WND);
    { Newer Capabilities }
    if CPUID.Capabilities1^.SSE3    then writestringWND(', SSE3', WND);
    if CPUID.Capabilities1^.PCLMUL  then writestringWND(', PCLMUL', WND);
    if CPUID.Capabilities1^.DTES64  then writestringWND(', DTES64', WND);
    if CPUID.Capabilities1^.MONITOR then writestringWND(', MONITOR', WND);
    if CPUID.Capabilities1^.DS_CPL  then writestringWND(', DS_CPL', WND);
    if CPUID.Capabilities1^.VMX     then writestringWND(', VMX', WND);
    if CPUID.Capabilities1^.SMX     then writestringWND(', SMX', WND);
    if CPUID.Capabilities1^.EST     then writestringWND(', EST', WND);
    if CPUID.Capabilities1^.TM2     then writestringWND(', TM2', WND);
    if CPUID.Capabilities1^.SSSE3   then writestringWND(', SSSE3', WND);
    if CPUID.Capabilities1^.CID     then writestringWND(', CID', WND);
    if CPUID.Capabilities1^.FMA     then writestringWND(', FMA', WND);
    if CPUID.Capabilities1^.CX16    then writestringWND(', CX16', WND);
    if CPUID.Capabilities1^.ETPRD   then writestringWND(', ETPRD', WND);
    if CPUID.Capabilities1^.PDCM    then writestringWND(', PDCM', WND);
    if CPUID.Capabilities1^.PCIDE   then writestringWND(', PCIDE', WND);
    if CPUID.Capabilities1^.DCA     then writestringWND(', DCA', WND);
    if CPUID.Capabilities1^.SSE4_1  then writestringWND(', SSE4_1', WND);
    if CPUID.Capabilities1^.SSE4_2  then writestringWND(', SSE4_2', WND);
    if CPUID.Capabilities1^.x2APIC  then writestringWND(', x2APIC', WND);
    if CPUID.Capabilities1^.MOVBE   then writestringWND(', MOVBE', WND);
    if CPUID.Capabilities1^.POPCNT  then writestringWND(', POPCNT', WND);
    if CPUID.Capabilities1^.AES     then writestringWND(', AES', WND);
    if CPUID.Capabilities1^.XSAVE   then writestringWND(', XSAVE', WND);
    if CPUID.Capabilities1^.OSXSAVE then writestringWND(', OSXSAVE', WND);
    if CPUID.Capabilities1^.AVX     then writestringWND(', AVX', WND);
    if CPUID.Capabilities1^.RDRAND  then writestringWND(', RDRAND', WND);
    writestringlnWND(' ', WND);
end;

procedure Terminal_Command_CPU(Params : PParamList);
begin
    writeStringWND('Vendor: ', getTerminalHWND);
    writeStringLnWND(@CPUID.Identifier[0], getTerminalHWND);
    writeStringWND('CPU Clock: ', getTerminalHWND);
    writeIntWND(CPUID.ClockSpeed.MHz, getTerminalHWND);
    writeStringlnWND('MHz', getTerminalHWND);
    writeStringWND('CPU Capabilities: ', getTerminalHWND);
    printCapabilities(getTerminalHWND);
end;

procedure init();
begin
    terminal.registerCommand('CPU', @Terminal_Command_CPU, 'CPU Info.');
    CPUID.Capabilities0:= PCapabilities_Old(@CAP_OLD);
    CPUID.Capabilities1:= PCapabilities_New(@CAP_NEW); 
    getCPUIdentifier;
    getCPUCapabilities;
    getCPUClockSpeed;
end;

end.