# arch.x86.fault.pf

Page Fault handler (CPU vector 14).

## Overview

Handles the x86 Page Fault exception (`#PF`, vector 14), which is raised when the processor encounters a page that is not present, a privilege violation in page access, or a write to a read-only page. The handler disables interrupts, adjusts the interrupt register pointers (including the error code), and triggers a kernel panic. The faulting linear address is available in CR2 but is not currently decoded by this handler.

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

Registers the page fault handler with `arch.x86.isr.mgr` at ISR vector 14. Must be called during fault subsystem initialisation.

## Notes

- The handler calls `correctInterruptRegisters(true)` because vector 14 pushes an error code encoding the fault type (present bit, write access, user mode, instruction fetch).
- After adjusting register pointers, `x86_panic` is called with fault identifier `'arch.x86.fault.pf'` and description `'Page Fault.'`.
- No demand-paging or copy-on-write recovery is attempted; all page faults are currently treated as fatal.
