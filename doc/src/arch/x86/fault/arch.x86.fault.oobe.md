# arch.x86.fault.oobe

Out of Bounds Exception handler (CPU vector 5).

## Overview

Handles the x86 BOUND Range Exceeded exception (`#BR`, vector 5), which is raised when the `BOUND` instruction detects that an array index is outside the declared bounds. The handler disables interrupts and triggers a kernel panic.

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

Registers the out-of-bounds handler with `arch.x86.isr.mgr` at ISR vector 5. Must be called during fault subsystem initialisation.

## Notes

- The handler calls `correctInterruptRegisters(false)` because vector 5 does not push an error code.
- After adjusting register pointers, `x86_panic` is called with fault identifier `'arch.x86.fault.oobe'` and description `'Out of Bounds Exception.'`.
