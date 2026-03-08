# arch.x86.isr.tmr1

Secondary timer ISR driver at 1024 ticks per second (vector 40).

## Overview

This unit provides a second timer interrupt source registered on IDT vector 40 (IRQ 8, the RTC interrupt after PIC remapping). It is intended to fire at 1024 Hz and dispatches all registered hook callbacks with a fixed data value of 18. Unlike `arch.x86.isr.tmr0`, this unit does not directly program any hardware timer; it relies on the caller having configured the RTC or another IRQ 8 source externally.

## Dependencies

- `core.util`
- `arch.x86.util`
- `arch.x86.isr.types`
- `arch.x86.idt`

Note: `arch.x86.isr.mgr` is used in the implementation to register hooks but is accessed without appearing in the interface `uses` clause.

## Functions and Procedures

### register

```pascal
procedure register();
```

Zeroes the hook array and registers the ISR handler with `arch.x86.isr.mgr` at vector 40. Idempotent; does nothing if already registered. Calling `hook` will also call `register` if it has not been called yet.

### hook

```pascal
procedure hook(hook_method : uint32);
```

Adds a callback function to the dispatch list. `hook_method` is the address of a `procedure(data : void)` callback. Duplicate registrations are silently ignored.

### unhook

```pascal
procedure unhook(hook_method : uint32);
```

Removes a previously registered callback. Searches all slots for `hook_method` and clears the first match found. Note: the current implementation has a minor bug — it exits after examining the first slot regardless of whether a match was found; only the first slot is ever cleared.

## Notes

- The data value `18` passed to callbacks is a legacy artifact; it corresponds to the value 18 that was historically used to identify this timer source. Callbacks should ignore it unless they specifically check for this value.
- Vector 40 is IRQ 8 (the RTC interrupt). For this unit to work, the RTC must be configured to generate periodic interrupts and the corresponding IRQ 8 must be unmasked in the 8259 slave PIC.
