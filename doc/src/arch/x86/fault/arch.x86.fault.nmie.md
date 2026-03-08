# arch.x86.fault.nmie

Non-Maskable Interrupt handler (CPU vector 2).

## Overview

Handles the x86 Non-Maskable Interrupt (NMI, vector 2), which is triggered by hardware signalling a critical error such as a memory parity error, bus error, or watchdog timeout. Because the NMI cannot be masked by the interrupt flag, it can arrive at any time. In the current implementation, an NMI is treated as fatal and triggers a kernel panic.

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

Registers the NMI handler with `arch.x86.isr.mgr` at ISR vector 2. Must be called during fault subsystem initialisation.

## Notes

- The handler calls `correctInterruptRegisters(false)` because vector 2 does not push an error code.
- After adjusting register pointers, `x86_panic` is called with fault identifier `'arch.x86.fault.nmie'` and description `'Non-Maskable Interrupt Exception.'`.
- NMIs are not maskable; the `CLI` instruction does not prevent them from being delivered.
