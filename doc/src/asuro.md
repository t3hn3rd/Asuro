# asuro

Kernel main entry point.

## Overview

`asuro` contains `kmain`, the first Pascal-level function called by the bootloader after the assembly stub hands off control. It stores the Multiboot info pointer and magic value, initialises the FPC system unit, then delegates the entire boot sequence to `boot.mgr.run`. Once all registered boot entries have executed, it calls `yield` to enable preemptive scheduling and idle the CPU.

The unit also registers its own `init` procedure with `boot.mgr` (depending on `io.syslog`). This procedure validates the Multiboot magic number — panicking if it does not match — and logs the framebuffer address and dimensions from the Multiboot info structure.

## Dependencies

- `boot.mgr`
- `io.syslog`
- `core.panic`
- `arch.x86.multiboot`
- `arch.x86.proc.sched`

## Boot Registration

Registered with `boot.mgr` as `asuro`, depending on `io.syslog`.

## Functions and Procedures

### kmain

```pascal
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall;
```

Exported as `kmain` (public alias). Performs three steps:

1. Stores the Multiboot info pointer and magic value into module-level globals.
2. Calls `System.init()` — FPC RTL initialisation (runs all unit `initialization` sections, which populates `boot.mgr`'s registration table).
3. Calls `boot.mgr.run` — executes all registered boot entries in dependency-resolved order.
4. Calls `yield` — enables preemptive scheduling and enters the idle loop.

### init (internal)

```pascal
procedure init;
```

Registered with `boot.mgr` as `asuro`. Validates that the Multiboot magic number matches `MULTIBOOT_BOOTLOADER_MAGIC`, panicking if it does not. Logs the assigned framebuffer address and dimensions from the Multiboot info structure.

### yield (internal)

```pascal
procedure yield;
```

Logs "Boot complete", calls `arch.x86.proc.sched.init` to enable preemptive context switching (replaces ISR_32), then enters an infinite `STI` / `HLT` loop. All subsequent execution is driven by timer and device interrupts.

## Notes

- The old hardcoded boot sequence previously in `kmain` has been replaced entirely by `boot.mgr`. Individual units now self-register their init procedures and dependencies; `kmain` only bootstraps the framework and idles.
- `System.init()` triggers `FPC_INITIALIZEUNITS`, which runs every unit's `initialization` section. This is what populates `boot.mgr`'s entry table before `run` is called.
