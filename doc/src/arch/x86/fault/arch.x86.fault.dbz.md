# arch.x86.fault.dbz

Divide By Zero Exception handler (CPU vector 0).

## Overview

Handles the x86 Divide Error exception (`#DE`, vector 0), which is raised when the processor executes a `DIV` or `IDIV` instruction with a zero divisor or when the quotient overflows the destination register. The handler disables interrupts, adjusts the interrupt register pointers, and triggers a kernel panic.

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

Registers the divide-by-zero handler with `arch.x86.isr.mgr` at ISR vector 0. Must be called during fault subsystem initialisation.

## Notes

- The handler calls `correctInterruptRegisters(false)` because vector 0 does not push an error code onto the stack.
- After adjusting register pointers, `x86_panic` is called with fault identifier `'arch.x86.fault.dbz'` and description `'Divide By Zero Exception.'`.
- This is a fatal, non-recoverable exception; the system halts after displaying the panic screen.
