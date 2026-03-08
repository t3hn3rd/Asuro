# arch.x86.fault.idoe

Into Detected Overflow Exception handler (CPU vector 4).

## Overview

Handles the x86 Overflow exception (`#OF`, vector 4), which is raised when the `INTO` instruction is executed and the overflow flag (OF) is set. The handler disables interrupts and triggers a kernel panic.

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

Registers the overflow handler with `arch.x86.isr.mgr` at ISR vector 4. Must be called during fault subsystem initialisation.

## Notes

- The handler calls `correctInterruptRegisters(false)` because vector 4 does not push an error code.
- After adjusting register pointers, `x86_panic` is called with fault identifier `'arch.x86.fault.idoe'` and description `'Into Detected Overflow Exception.'`.
- The `INTO` instruction is rarely used in modern code; this exception is primarily a legacy compatibility handler.
