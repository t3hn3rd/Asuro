# arch.x86.v86

Virtual 8086 (V86) mode monitor for executing real-mode BIOS interrupts from protected mode.

## Overview

This unit implements a Virtual 8086 mode monitor that allows the kernel to call BIOS interrupt handlers while running in 32-bit protected mode. The caller sets up a `TV86Regs` record with the desired input register values, calls `v86_int`, and receives the BIOS output register values back in the same record.

The implementation works by writing a two-instruction thunk (`INT n` / `INT 0xFF`) into low physical memory at address 0x7C00, building an IRET frame with VM=1 set in EFLAGS to switch the CPU into V86 mode, and executing the thunk. Every privileged instruction executed by the BIOS handler in V86 mode causes a General Protection Fault. The unit installs a custom naked GPF handler (`v86_gpf_isr`) that inspects the faulting instruction and emulates it: `INT`, `IRET`, `CLI`, `STI`, `PUSHF/PUSHFD`, `POPF/POPFD`, all `IN`/`OUT` variants (with and without operand-size prefix), and `HLT`. When the sentinel `INT 0xFF` is encountered, results are copied out of the saved register frame and control returns to the Pascal caller.

A minimal TSS is installed in GDT gate 5 so the CPU can locate the ring-0 stack pointer (ESP0) when transitioning from V86 ring 3 to ring 0 on a GPF.

## Dependencies

- `core.util`
- `arch.x86.util`
- `core.panic`
- `io.syslog`
- `debug.tracer`
- `arch.x86.memory.virtual`
- `arch.x86.gdt`
- `arch.x86.idt`
- `arch.x86.isr.types`

## Constants

| Constant          | Value    | Description |
|-------------------|----------|-------------|
| V86_EFLAGS        | `$23000` | EFLAGS for V86 entry: VM=1, IOPL=3, IF=0 |
| V86_THUNK_ADDR    | `$7C00`  | Physical address of the two-instruction thunk |
| V86_STACK_SEG     | `$0000`  | Real-mode stack segment (SS) |
| V86_STACK_PTR     | `$8000`  | Real-mode stack pointer (SP), grows downward |
| V86_EXIT_INT      | `$FF`    | Sentinel interrupt number signalling V86 exit |
| V86_R0_STACK_SIZE | `4096`   | Size in bytes of the dedicated ring-0 stack used during V86 GPF handling |
| V86_TSS_GDT_GATE  | `5`      | GDT gate index for the TSS descriptor |
| V86_TSS_SELECTOR  | `40`     | TSS segment selector (gate 5 * 8) |
| V86_TSS_SIZE      | `104`    | Minimum x86 TSS size in bytes |

## Types

### TV86Regs / PV86Regs

```pascal
TV86Regs = record
    EAX, EBX, ECX, EDX : uint32;
    ESI, EDI, EBP      : uint32;
    DS, ES, FS, GS     : uint16;
end;
```

Input and output register state for a V86 BIOS call. Populate before calling `v86_int`; read results after it returns.

### TV86GPFFrame / PV86GPFFrame

```pascal
TV86GPFFrame = packed record
    ErrorCode : uint32;
    EIP       : uint32;
    CS        : uint32;
    EFLAGS    : uint32;
    ESP       : uint32;
    SS        : uint32;
    ES        : uint32;
    DS        : uint32;
    FS        : uint32;
    GS        : uint32;
end;
```

The CPU exception frame pushed on the ring-0 stack when a GPF occurs from V86 mode, preceded by the `PUSHAD` frame. The emulator modifies fields directly to redirect V86 execution.

## Functions and Procedures

### init

```pascal
procedure init;
```

Initialises the V86 subsystem. Sets up a minimal TSS in `V86TSS`, installs a GDT descriptor for it at gate 5 (access `$89`, present, DPL 0, TSS available), reloads the GDT, loads the task register (`LTR`), identity-maps the first 4 MiB with the user bit set (so V86 code can access the IVT, BDA, and VGA memory), and replaces IDT gate 13 (`#GP`) with the custom naked handler `v86_gpf_isr`. Must be called once during kernel initialisation before any BIOS calls are made.

### v86_int

```pascal
function v86_int(intNo : uint8; var regs : TV86Regs) : boolean;
```

Executes a real-mode BIOS interrupt from protected mode.

- `intNo` — The BIOS interrupt number to call (e.g., `$10` for video services).
- `regs` — On entry, contains the register values to pass to the BIOS handler. On return, contains the register values returned by the BIOS handler.

Returns `true` if the call completed successfully (sentinel `INT 0xFF` was reached), `false` if the emulator encountered an unhandled opcode and aborted.

The function disables interrupts for the duration of the call and re-enables them on return.

## Notes

- Real-mode memory addresses are accessed by adding `KERNEL_VIRTUAL_BASE` (`$C0000000`) to the physical linear address, since the first 4 MiB of physical memory is identity-mapped at the higher-half kernel base.
- The BIOS thunk is written to physical address 0x7C00 (the standard MBR load address), which is free after boot.
- Segment override prefixes (`$26`, `$2E`, `$36`, `$3E`, `$64`, `$65`) and LOCK/REP prefixes (`$F0`, `$F2`, `$F3`) are recognised and skipped during opcode scanning but are otherwise not emulated.
- The operand-size prefix (`$66`) is handled for `IRETD`, `PUSHFD`, `POPFD`, and 32-bit `IN`/`OUT` variants.
- Non-V86 GPFs that arrive at the patched gate 13 handler are forwarded to `core.panic.panic` via `v86_chain_gpf`.
- Only one V86 call may be in progress at a time; the global state variables are not reentrant.
