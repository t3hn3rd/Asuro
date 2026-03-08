# arch.x86.fault.uie

Unknown Interrupt Exception handler (ISR vector 15).

## Overview

Handles spurious or unknown interrupt vector 15, which does not correspond to a standard x86 CPU exception. This handler provides a catch-all for unexpected interrupts at this vector, disabling interrupts and triggering a kernel panic.

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

Registers the unknown interrupt handler with `arch.x86.isr.mgr` at ISR vector 15. Must be called during fault subsystem initialisation.

## Notes

- The handler calls `correctInterruptRegisters(false)` because vector 15 does not push an error code.
- After adjusting register pointers, `x86_panic` is called with fault identifier `'arch.x86.fault.uie'` and description `'Unknown Interrupt Exception.'`.
- Vector 15 (`$0F`) is architecturally reserved and should never fire on a conforming x86 processor.
