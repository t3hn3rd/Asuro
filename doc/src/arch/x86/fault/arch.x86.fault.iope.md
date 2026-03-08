# arch.x86.fault.iope

Invalid Opcode Exception handler (CPU vector 6).

## Overview

Handles the x86 Invalid Opcode exception (`#UD`, vector 6), which is raised when the processor encounters an undefined or illegal instruction encoding. The handler disables interrupts and triggers a kernel panic.

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

Registers the invalid opcode handler with `arch.x86.isr.mgr` at ISR vector 6. Must be called during fault subsystem initialisation.

## Notes

- The handler calls `correctInterruptRegisters(false)` because vector 6 does not push an error code.
- After adjusting register pointers, `x86_panic` is called with fault identifier `'arch.x86.fault.iope'` and description `'Invalid OPCode Exception.'`.
