# arch.x86.fault

Fault handler registration coordinator.

## Overview

This unit is the single entry point for registering all x86 CPU exception handlers. Its `init` procedure calls the `register` procedure of every individual fault unit, which in turn registers each handler with `arch.x86.isr.mgr`. This design keeps fault registration centralised while allowing each exception type to be managed in its own unit.

## Dependencies

- `arch.x86.fault.ace`
- `arch.x86.fault.bpe`
- `arch.x86.fault.btsse`
- `arch.x86.fault.cfe`
- `arch.x86.fault.csoe`
- `arch.x86.fault.dbge`
- `arch.x86.fault.dbz`
- `arch.x86.fault.dfe`
- `arch.x86.fault.gpf`
- `arch.x86.fault.idoe`
- `arch.x86.fault.iope`
- `arch.x86.fault.mce`
- `arch.x86.fault.nce`
- `arch.x86.fault.nmie`
- `arch.x86.fault.oobe`
- `arch.x86.fault.pf`
- `arch.x86.fault.sfe`
- `arch.x86.fault.snpe`
- `arch.x86.fault.uie`

## Functions and Procedures

### init

```pascal
procedure init;
```

Calls `register()` on all nineteen individual fault handler units. Must be called after `arch.x86.isr.mgr.init` has set up the ISR dispatch table, and before interrupts are enabled.

## Notes

The following CPU exception vectors are covered by this unit's registrations:

| Vector | Unit | Exception |
|--------|------|-----------|
| 0  | arch.x86.fault.dbz   | Divide By Zero |
| 1  | arch.x86.fault.dbge  | Debug Exception |
| 2  | arch.x86.fault.nmie  | Non-Maskable Interrupt |
| 3  | arch.x86.fault.bpe   | Breakpoint |
| 4  | arch.x86.fault.idoe  | Into Detected Overflow |
| 5  | arch.x86.fault.oobe  | Out of Bounds (BOUND) |
| 6  | arch.x86.fault.iope  | Invalid Opcode |
| 7  | arch.x86.fault.nce   | No Coprocessor |
| 8  | arch.x86.fault.dfe   | Double Fault |
| 9  | arch.x86.fault.csoe  | Coprocessor Segment Overrun |
| 10 | arch.x86.fault.btsse | Bad TSS |
| 11 | arch.x86.fault.snpe  | Segment Not Present |
| 12 | arch.x86.fault.sfe   | Stack Fault |
| 13 | arch.x86.fault.gpf   | General Protection Fault |
| 14 | arch.x86.fault.pf    | Page Fault |
| 15 | arch.x86.fault.uie   | Unknown Interrupt |
| 16 | arch.x86.fault.cfe   | Coprocessor Fault |
| 17 | arch.x86.fault.ace   | Alignment Check |
| 18 | arch.x86.fault.mce   | Machine Check |
