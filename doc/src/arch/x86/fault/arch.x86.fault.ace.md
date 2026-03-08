# arch.x86.fault.ace

Alignment Check Exception handler (CPU vector 17).

## Overview

Handles the x86 Alignment Check exception (`#AC`, vector 17), which is raised when a memory reference to an unaligned address is made while alignment checking is enabled (CR0.AM set and EFLAGS.AC set at CPL 3). The handler disables interrupts and triggers a kernel panic.

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

Registers the alignment check handler with `arch.x86.isr.mgr` at ISR vector 17. Must be called during fault subsystem initialisation.

## Notes

- The handler calls `correctInterruptRegisters(true)` because vector 17 pushes an error code (always zero for alignment check faults).
- After adjusting register pointers, `x86_panic` is called with fault identifier `'arch.x86.fault.ace'` and description `'Alignment Check Exception.'`.
