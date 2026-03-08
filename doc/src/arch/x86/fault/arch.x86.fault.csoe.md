# arch.x86.fault.csoe

Coprocessor Segment Overrun Exception handler (CPU vector 9).

## Overview

Handles the x86 Coprocessor Segment Overrun exception (vector 9), a legacy exception from early Intel processors (pre-486) that fired when a floating-point operand straddled a segment boundary. Modern processors do not generate this exception; the handler exists for completeness and to catch any unexpected delivery of vector 9. It disables interrupts and triggers a kernel panic.

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

Registers the coprocessor segment overrun handler with `arch.x86.isr.mgr` at ISR vector 9. Must be called during fault subsystem initialisation.

## Notes

- The handler calls `correctInterruptRegisters(false)` because vector 9 does not push an error code.
- After adjusting register pointers, `x86_panic` is called with fault identifier `'arch.x86.fault.csoe'` and description `'Coprocessor Seg Overrun Exception.'`.
- Intel P6 and later processors repurposed vector 9; it will not fire on modern hardware.
