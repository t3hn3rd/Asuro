# arch.x86.fault.snpe

Segment Not Present Exception handler (CPU vector 11).

## Overview

Handles the x86 Segment Not Present exception (`#NP`, vector 11), which is raised when the processor attempts to load a segment or gate descriptor whose Present bit is clear. The handler disables interrupts and triggers a kernel panic.

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

Registers the segment-not-present handler with `arch.x86.isr.mgr` at ISR vector 11. Must be called during fault subsystem initialisation.

## Notes

- The handler calls `correctInterruptRegisters(true)` because vector 11 pushes an error code encoding the segment selector that was found not present.
- After adjusting register pointers, `x86_panic` is called with fault identifier `'arch.x86.fault.snpe'` and description `'Segment Not Present Exception.'`.
