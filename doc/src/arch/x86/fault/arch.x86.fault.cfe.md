# arch.x86.fault.cfe

Coprocessor Fault Exception handler (CPU vector 16).

## Overview

Handles the x86 x87 Floating-Point Exception (`#MF`, vector 16), which is raised by an unmasked x87 FPU error. Common causes include invalid operation, division by zero, overflow, underflow, and precision exceptions in floating-point arithmetic. The handler disables interrupts and triggers a kernel panic.

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

Registers the coprocessor fault handler with `arch.x86.isr.mgr` at ISR vector 16. Must be called during fault subsystem initialisation.

## Notes

- The handler calls `correctInterruptRegisters(false)` because vector 16 does not push an error code.
- After adjusting register pointers, `x86_panic` is called with fault identifier `'arch.x86.fault.cfe'` and description `'Coprocessor Fault Exception.'`.
- The specific FPU error type can be determined from the x87 status word, but this is not currently decoded by the handler.
