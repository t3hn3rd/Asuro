# arch.x86.fault.nce

No Coprocessor Exception handler (CPU vector 7).

## Overview

Handles the x86 Device Not Available exception (`#NM`, vector 7), which is raised when a floating-point or SSE instruction is executed while the TS flag is set in CR0, or when an FPU instruction is attempted with no FPU present (EM flag set in CR0). The handler disables interrupts and triggers a kernel panic.

## Dependencies

- `arch.x86.util`
- `arch.x86.panic`
- `arch.x86.isr.types`
- `arch.x86.isr.mgr`
- `arch.x86.idt`

## Functions and Procedures

### register

```pascal
procedure register();
```

Registers the no-coprocessor handler with `arch.x86.isr.mgr` at ISR vector 7. Must be called during fault subsystem initialisation.

## Notes

- The handler calls `correctInterruptRegisters(false)` because vector 7 does not push an error code.
- After adjusting register pointers, `x86_panic` is called with fault identifier `'arch.x86.fault.nce'` and description `'No Coprocessor Exception.'`.
- Since the kernel enables SSE in `arch.x86.cpu.init`, this exception should not fire in normal operation unless CR0.TS is set without a corresponding FPU context save.
