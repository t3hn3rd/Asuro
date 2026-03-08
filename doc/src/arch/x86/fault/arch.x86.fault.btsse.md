# arch.x86.fault.btsse

Bad TSS Exception handler (CPU vector 10).

## Overview

Handles the x86 Invalid TSS exception (`#TS`, vector 10), which is raised when the processor detects an invalid Task State Segment during a task switch or interrupt delivery that involves a privilege level change. The handler disables interrupts and triggers a kernel panic.

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

Registers the bad TSS handler with `arch.x86.isr.mgr` at ISR vector 10. Must be called during fault subsystem initialisation.

## Notes

- The handler calls `correctInterruptRegisters(true)` because vector 10 pushes an error code encoding the TSS segment selector that caused the fault.
- After adjusting register pointers, `x86_panic` is called with fault identifier `'arch.x86.fault.btsse'` and description `'Bad TSS Exception.'`.
