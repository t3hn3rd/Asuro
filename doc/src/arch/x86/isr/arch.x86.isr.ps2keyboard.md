# arch.x86.isr.ps2keyboard

PS/2 keyboard ISR driver with hookable scancode delivery.

## Overview

This unit installs a handler on IRQ 1 (IDT vector 33) that reads one scancode byte from the PS/2 controller's data port (`$60`) and dispatches it to all registered hook callbacks. External code registers hook functions that accept a `void` parameter; the raw scancode byte is passed as the argument. The driver supports up to `MAX_HOOKS` simultaneous hook registrations.

## Dependencies

- `core.util`
- `arch.x86.util`
- `arch.x86.isr.types`
- `arch.x86.isr.mgr`
- `arch.x86.idt`

## Functions and Procedures

### register

```pascal
procedure register();
```

Registers the keyboard ISR handler with `arch.x86.isr.mgr` at vector 33 (IRQ 1 after PIC remapping). Reads and discards one pending byte from port `$60` to clear any pre-existing scancode. Idempotent; does nothing if already registered.

### hook

```pascal
procedure hook(hook_method : uint32);
```

Adds a callback function to the scancode dispatch list. The `hook_method` parameter is the address of a `procedure(data : void)` callback. Duplicate registrations (same address already present) are silently ignored. The callback will be invoked with the raw scancode byte cast to `void` on each keypress or release.

### unhook

```pascal
procedure unhook(hook_method : uint32);
```

Removes a previously registered callback from the dispatch list. Searches for the first slot containing `hook_method` and sets it to `nil`.

## Notes

- The handler disables interrupts (`CLI`) at the start of the ISR body. The `interrupt` procedure directive on the underlying ISR stub and the EOI logic in `arch.x86.isr.mgr.ISR_N` handle re-enabling interrupts and sending EOI.
- Raw scancodes are delivered; no scancode-to-key translation is performed by this unit. Consumers are responsible for interpreting make/break codes, extended key sequences (0xE0 prefix), and modifier state.
- There is a known intermittent issue noted in the source where the keyboard ISR sometimes fails to be called after PIC setup; investigation is pending.
