# arch.x86.panic

x86-specific kernel panic bridge between the interrupt frame and the architecture-agnostic panic engine.

## Overview

This unit acts as the glue layer between the x86 interrupt subsystem and the architecture-neutral `core.panic` module. When a fatal CPU exception occurs, the fault handler calls `x86_panic`, which reads the saved register state from the global interrupt frame variables (`IntReg`, `IntErr`, `IntSpec`), packs it into a `TRegisterSnapshot`, and delegates to `core.panic.panic` for display and halt. The `init` procedure registers the x86-specific halt function and initialises the BSOD screen.

## Dependencies

- `core.panic` (interface)
- `arch.x86.util` (implementation)
- `arch.x86.isr.types` (implementation)

## Boot Registration

Registered with `boot.mgr` as `arch.x86.panic`, depending on glob `driver.video*` (waits for all matching entries).

## Functions and Procedures

### init

```pascal
procedure init;
```

Registers `arch.x86.util.halt_and_catch_fire` as the halt callback with `core.panic`, then calls `core.panic.init` to set up the BSOD display. Must be called after LVGL is initialised and before any fault handlers that may trigger a panic.

### x86_panic

```pascal
procedure x86_panic(fault : pchar; info : pchar);
```

Builds a `TRegisterSnapshot` from the current interrupt frame globals and invokes `core.panic.panic`.

- `fault` — Short fault identifier string (e.g., `'arch.x86.fault.gpf'`).
- `info` — Human-readable description (e.g., `'General Protection Fault.'`).

The snapshot includes, in order: EBP, EAX, EBX, ECX, EDX, ESI, EDI, DS, ES, FS, GS (from `IntReg`), ERROR (from `IntErr`), and EIP, CS, EFLAGS (from `IntSpec`). Fields whose corresponding pointer is `nil` are omitted.

Must be called after `correctInterruptRegisters()` has been called by the ISR wrapper so that `IntReg`, `IntErr`, and `IntSpec` point to the correct offsets within the saved interrupt frame.

## Notes

- The `addEntry` helper is internal and not exported. It appends one name–value pair to the snapshot, respecting the `MAX_REGISTER_ENTRIES` limit defined in `core.panic`.
- Whether `IntErr` contains a meaningful error code depends on the exception type. Faults that do not push an error code should call `correctInterruptRegisters(false)` before `x86_panic`, which causes `IntErr` to point to a zero-filled sentinel value.
