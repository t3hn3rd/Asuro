# arch.x86.isr.tmr0

8 kHz PIT timer ISR driver (IRQ 0, vector 32).

## Overview

This unit programs the 8253/8254 Programmable Interval Timer channel 0 to fire at approximately 8 kHz and installs a handler on IDT vector 32 (IRQ 0). On each tick, all registered hook callbacks are invoked with `nil` as the data argument. The high tick rate is suitable for fine-grained timing and smooth animation at the cost of interrupt overhead.

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

Programs PIT channel 0 with a divisor of 149, yielding a frequency of approximately 8 001 Hz (1 193 180 / 149). Zeroes the hook array and registers the ISR handler at vector 32. Idempotent; does nothing if already registered. Calling `hook` will also call `register` if it has not been called yet.

### hook

```pascal
procedure hook(hook_method : uint32);
```

Adds a callback function to the timer tick dispatch list. `hook_method` is the address of a `procedure(data : void)` callback. Duplicate registrations are silently ignored.

### unhook

```pascal
procedure unhook(hook_method : uint32);
```

Removes a previously registered callback from the dispatch list. Searches all slots for `hook_method` and clears the first match.

## Notes

- The timer ISR disables interrupts (`CLI`) at the start of the handler body.
- Callbacks receive `nil` as the data argument; the argument is unused for timer hooks.
- The context switch ISR (`arch.x86.proc.sched`) replaces IDT gate 32 directly and calls `arch.x86.isr.mgr.dispatchHooks(32)` to fire hooks registered through this unit; the tmr0 hooks therefore still execute even after the scheduler takes over vector 32.
- PIT divisor 149 was chosen to give a conveniently high frequency. The exact frequency is 1 193 180 / 149 ≈ 8 007 Hz.
