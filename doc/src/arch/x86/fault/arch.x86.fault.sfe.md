# arch.x86.fault.sfe

Stack Fault Exception handler (CPU vector 12).

## Overview

Handles the x86 Stack-Segment Fault (`#SS`, vector 12), which is raised when a stack operation violates segment limits or when loading a non-present stack segment. The handler disables interrupts and triggers a kernel panic.

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

Registers the stack fault handler with `arch.x86.isr.mgr` at ISR vector 12. Must be called during fault subsystem initialisation.

## Notes

- The handler calls `correctInterruptRegisters(true)` because vector 12 pushes an error code encoding the segment selector involved.
- After adjusting register pointers, `x86_panic` is called with fault identifier `'arch.x86.fault.sfe'` and description `'Stack Fault Exception.'`.
