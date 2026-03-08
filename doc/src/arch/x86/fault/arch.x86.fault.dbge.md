# arch.x86.fault.dbge

Debug Exception handler (CPU vector 1).

## Overview

Handles the x86 Debug exception (`#DB`, vector 1), which is raised for single-step traps, hardware breakpoints, and other debug conditions. In the current implementation, this exception is treated as fatal and triggers a kernel panic.

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

Registers the debug exception handler with `arch.x86.isr.mgr` at ISR vector 1. Must be called during fault subsystem initialisation.

## Notes

- The handler calls `correctInterruptRegisters(false)` because vector 1 does not push an error code.
- After adjusting register pointers, `x86_panic` is called with fault identifier `'arch.x86.fault.dbge'` and description `'Debug Exception.'`.
- The debug exception can fire as either a fault or a trap depending on the specific debug condition. No distinction is currently made.
