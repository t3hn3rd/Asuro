# arch.x86.fault.dfe

Double Fault Exception handler (CPU vector 8).

## Overview

Handles the x86 Double Fault exception (`#DF`, vector 8), which occurs when the processor encounters a fault while attempting to deliver a previous exception. A double fault is a severe condition that typically indicates a corrupted stack or a bug in an exception handler. The handler disables interrupts, adjusts the interrupt register pointers (including the error code, which is always zero for double faults), and triggers a kernel panic.

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

Registers the double fault handler with `arch.x86.isr.mgr` at ISR vector 8. Must be called during fault subsystem initialisation.

## Notes

- The handler calls `correctInterruptRegisters(true)` because vector 8 pushes an error code (always zero) onto the stack.
- After adjusting register pointers, `x86_panic` is called with fault identifier `'arch.x86.fault.dfe'` and description `'Double Fault.'`.
- A triple fault (fault during double fault handling) will cause an immediate CPU reset without invoking any handler.
