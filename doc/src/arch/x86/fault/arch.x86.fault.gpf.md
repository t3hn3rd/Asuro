# arch.x86.fault.gpf

General Protection Fault handler (CPU vector 13).

## Overview

Handles the x86 General Protection Fault (`#GP`, vector 13), which is raised by a wide variety of protection violations including invalid segment selector loads, privilege level violations, I/O permission violations, and reserved bit violations. The handler disables interrupts, adjusts the interrupt register pointers (including the error code), and triggers a kernel panic.

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

Registers the GPF handler with `arch.x86.isr.mgr` at ISR vector 13. Must be called during fault subsystem initialisation.

## Notes

- The handler calls `correctInterruptRegisters(true)` because vector 13 pushes an error code onto the stack; the error code encodes the segment selector involved in the fault, or zero if the fault has no associated selector.
- After adjusting register pointers, `x86_panic` is called with fault identifier `'arch.x86.fault.gpf'` and description `'General Protection Fault.'`.
- When the V86 monitor (`arch.x86.v86`) is active, IDT gate 13 is replaced by `v86_gpf_isr` to handle V86 mode faults. The registration made here is overridden by `arch.x86.v86.init`.
