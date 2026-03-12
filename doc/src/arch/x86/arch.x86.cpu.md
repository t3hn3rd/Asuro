# arch.x86.cpu

CPU identification, capability detection, clock speed measurement, and feature enablement.

## Overview

This unit probes the processor using the CPUID instruction to discover the vendor identifier string, feature flags (EDX and ECX bitmaps from leaf 1), and clock speed. After probing, it enables SSE and AVX if the hardware supports them. The globally accessible `CPUID` record is populated during `init` and can be queried by other subsystems at any time. A terminal command handler is also exposed so a shell can display CPU information to the user.

## Dependencies

- `core.util`
- `arch.x86.util`
- `driver.timer.rtc`
- `io.stdio`

## Boot Registration

Registered with `boot.mgr` as `arch.x86.cpu` at the `early` barrier.

## Types

### TCapabilities_Old / PCapabilities_Old

A `bitpacked record` that maps the EDX output of CPUID leaf 1 to individual Boolean fields. Each field corresponds to one feature bit in the legacy capability word:

| Field  | Description |
|--------|-------------|
| FPU    | x87 FPU on-chip |
| VME    | Virtual-8086 mode enhancements |
| DE     | Debugging extensions |
| PSE    | Page size extension |
| TSC    | Time-stamp counter |
| MSR    | Model-specific registers |
| PAE    | Physical address extension |
| MCE    | Machine check exception |
| CX8    | CMPXCHG8B instruction |
| APIC   | APIC on-chip |
| SEP    | SYSENTER/SYSEXIT |
| MTRR   | Memory-type range registers |
| PGE    | Page global bit |
| MCA    | Machine check architecture |
| CMOV   | Conditional move instructions |
| PAT    | Page attribute table |
| PSE36  | 36-bit page size extension |
| PSN    | Processor serial number |
| CLF    | CLFLUSH instruction |
| DTES   | Debug store |
| ACPI   | ACPI thermal monitor |
| MMX    | MMX technology |
| FXSR   | FXSAVE/FXRSTOR instructions |
| SSE    | Streaming SIMD extensions |
| SSE2   | SSE2 extensions |
| SS     | Self-snoop |
| HTT    | Hyper-threading technology |
| TM1    | Thermal monitor 1 |
| IA64   | IA-64 processor |
| PBE    | Pending break enable |

Reserved bits (RESV0, RESV1) are included but have no defined meaning.

### TCapabilities_New / PCapabilities_New

A `bitpacked record` that maps the ECX output of CPUID leaf 1 to individual Boolean fields representing newer CPU features:

| Field    | Description |
|----------|-------------|
| SSE3     | SSE3 extensions |
| PCLMUL   | PCLMULQDQ instruction |
| DTES64   | 64-bit DS area |
| MONITOR  | MONITOR/MWAIT |
| DS_CPL   | CPL-qualified debug store |
| VMX      | Virtual machine extensions |
| SMX      | Safer mode extensions |
| EST      | Enhanced Intel SpeedStep |
| TM2      | Thermal monitor 2 |
| SSSE3    | Supplemental SSE3 |
| CID      | L1 context ID |
| FMA      | FMA extensions |
| CX16     | CMPXCHG16B instruction |
| ETPRD    | xTPR update control |
| PDCM     | Perfmon and debug capability |
| PCIDE    | Process-context identifiers |
| DCA      | Direct cache access |
| SSE4_1   | SSE4.1 extensions |
| SSE4_2   | SSE4.2 extensions |
| x2APIC   | x2APIC support |
| MOVBE    | MOVBE instruction |
| POPCNT   | POPCNT instruction |
| AES      | AES instruction extensions |
| XSAVE    | XSAVE/XRSTOR/XSETBV/XGETBV |
| OSXSAVE  | XSAVE enabled by OS |
| AVX      | Advanced vector extensions |
| RDRAND   | RDRAND instruction |

### TClockSpeed

```pascal
TClockSpeed = record
    Hz  : uint32;
    KHz : uint32;
    MHz : uint32;
    GHz : uint32;
end;
```

Holds the measured CPU clock speed at four granularities. All fields are derived from a single TSC measurement; the coarser fields are obtained by integer division.

### TCPUID

```pascal
TCPUID = record
    ClockSpeed    : TClockSpeed;
    Identifier    : Array[0..12] of Char;
    Capabilities0 : PCapabilities_Old;
    Capabilities1 : PCapabilities_New;
end;
```

The top-level CPU information record. `Identifier` is a 12-character null-terminated vendor string (e.g., `GenuineIntel`). `Capabilities0` and `Capabilities1` are pointers into the global `CAP_OLD` and `CAP_NEW` raw DWORD variables.

## Variables

### CPUID

```pascal
var CPUID : TCPUID;
```

Global CPU information record. Valid after `init` has been called.

### CAP_OLD, CAP_NEW

```pascal
var CAP_OLD, CAP_NEW : uint32;
```

Raw 32-bit values of the EDX and ECX registers returned by CPUID leaf 1. `CPUID.Capabilities0` and `CPUID.Capabilities1` point into these.

## Functions and Procedures

### init

```pascal
procedure init();
```

Initialises the CPU subsystem. Sets up capability pointers, executes CPUID to obtain the vendor string, feature bits, and clock speed, then enables SSE and AVX if supported. Must be called before any other code queries `CPUID`.

### Terminal_Command_CPU

```pascal
procedure Terminal_Command_CPU(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
```

Shell command handler. Writes CPU vendor, clock speed (MHz), and the full capability string to `stdout_buf`. Intended to be registered with the terminal command dispatcher.

## Notes

- Clock speed is measured by counting TSC ticks across one RTC second boundary. If the TSC capability bit is not set, the clock speed is reported as zero.
- SSE enablement clears the EM bit and sets the MP bit in CR0, then sets the OSFXSR and OSXMMEXCPT bits in CR4.
- AVX enablement requires both the AVX and XSAVE capability flags; it sets CR4.OSXSAVE and then calls XSETBV to enable x87, SSE, and AVX state components in XCR0.
