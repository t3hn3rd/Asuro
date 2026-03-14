# arch.x86.isr

ISR driver initialisation stub.

## Overview

This is a minimal stub unit that satisfies compile-time dependencies on an ISR initialisation entry point. The `init` procedure body is empty; actual ISR handler registration and IDT gate setup are performed by `arch.x86.isr.mgr` and the individual handler units in the `isr/` and `fault/` subdirectories.

## Boot Registration

Registered with `boot.mgr` as `asuro.x86.isr`, depending on glob `driver.storage.*.mgr` (waits for all matching entries).

## Functions and Procedures

### init

```pascal
procedure init();
```

Empty stub. Called by the kernel boot sequence as part of the interrupt subsystem initialisation order. No operation is performed.

## Notes

This unit exists solely to provide a well-defined initialisation hook. All substantive ISR logic resides in `arch.x86.isr.mgr`.
