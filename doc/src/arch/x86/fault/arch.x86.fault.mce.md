# arch.x86.fault.mce

Machine Check Exception handler (CPU vector 18).

## Overview

Handles the x86 Machine Check exception (`#MC`, vector 18), which is raised when the processor detects an unrecoverable internal hardware error such as a cache error, bus error, or TLB error. The handler disables interrupts and triggers a kernel panic.

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

Registers the machine check handler with `arch.x86.isr.mgr` at ISR vector 18. Must be called during fault subsystem initialisation.

## Notes

- The handler calls `correctInterruptRegisters(false)` because vector 18 does not push an error code.
- After adjusting register pointers, `x86_panic` is called with fault identifier `'arch.x86.fault.mce'` and description `'Machine Check Exception.'`.
- No Machine Check Architecture (MCA) MSRs are read to identify the specific error source.
