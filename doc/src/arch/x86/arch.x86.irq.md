# arch.x86.irq

PIC (8259A) initialisation and IRQ remapping.

## Overview

This unit reinitialises and remaps the two 8259A Programmable Interrupt Controllers. By default, the BIOS leaves the master PIC with IRQs 0–7 mapped to CPU interrupt vectors 0x08–0x0F, which conflicts with x86 exception vectors. This unit sends the standard initialisation command sequence to both PICs and remaps IRQs 0–7 to vectors 0x20–0x27 (master) and IRQs 8–15 to vectors 0x28–0x2F (slave), placing all hardware IRQs safely above the reserved exception range.

## Dependencies

- `core.util`
- `arch.x86.util`
- `io.syslog`

## Boot Registration

Registered with `boot.mgr` as `arch.x86.irq`, depending on `arch.x86.idt`.

## Functions and Procedures

### init

```pascal
procedure init();
```

Reinitialises both 8259A PICs using the ICW (Initialisation Command Word) sequence:

1. Sends ICW1 (`$11`) to both master (port `$20`) and slave (port `$A0`) command ports — edge-triggered, cascade mode, ICW4 required.
2. Sends ICW2: master base vector `$20` (IRQ 0 maps to INT 32), slave base vector `$28` (IRQ 8 maps to INT 40).
3. Sends ICW3: master cascade on IRQ line 2 (`$04`), slave cascade identity (`$02`).
4. Sends ICW4 (`$01`) to both PICs — 8086/88 mode.
5. Clears both interrupt masks (`$00`) so all IRQ lines are unmasked.

An `io_wait` call is inserted between each port write to give the PIC hardware time to process each command byte.

## Notes

- After `init`, IRQ 0 (PIT timer) is at vector 0x20, IRQ 1 (PS/2 keyboard) at 0x21, and so on through IRQ 15 at vector 0x2F.
- On systems with an I/O APIC, the 8259 PICs operate in Virtual Wire mode, and additional configuration is performed by `arch.x86.isr.ioapic`.
- This unit does not install any ISR handlers; handler registration is the responsibility of `arch.x86.isr.mgr` and the individual ISR units.
