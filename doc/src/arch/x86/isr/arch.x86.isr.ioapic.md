# arch.x86.isr.ioapic

I/O APIC and Local APIC minimal support for PCI interrupt routing.

## Overview

On systems where PCI interrupts are routed through the I/O APIC rather than the legacy 8259 PIC, this unit provides the minimal support needed to receive those interrupts. It maps the IOAPIC and Local APIC MMIO regions, probes for the presence of an I/O APIC, enables the Local APIC if found, and offers a function to program individual IOAPIC redirection table entries for PCI IRQ lines.

ISA interrupts (timer, PS/2 keyboard) continue to arrive through the 8259 PIC via Virtual Wire mode and do not require IOAPIC programming.

## Dependencies

- `core.util`
- `arch.x86.util`
- `memory.heap`
- `io.syslog`

## Constants

| Constant        | Value         | Description |
|-----------------|---------------|-------------|
| IOAPIC_PHYS     | `$FEC00000`   | Standard physical base address of the I/O APIC |
| LAPIC_PHYS      | `$FEE00000`   | Standard physical base address of the Local APIC |
| IOREGSEL        | `$00`         | I/O APIC indirect register select offset |
| IOWIN           | `$10`         | I/O APIC indirect register window offset |
| IOAPIC_ID       | `$00`         | IOAPIC ID register index |
| IOAPIC_VER      | `$01`         | IOAPIC version register index |
| IOAPIC_REDTBL   | `$10`         | Base index of the redirection table (each entry is 2 dwords) |
| LAPIC_SVR       | `$F0`         | Local APIC Spurious Interrupt Vector Register offset |
| LAPIC_EOI_REG   | `$B0`         | Local APIC End-of-Interrupt register offset |

## Variables

### ioapic_present

```pascal
var ioapic_present : boolean;
```

Set to `true` by `init` if an I/O APIC is detected and successfully initialised. ISR handlers check this flag to determine whether a Local APIC EOI is required in addition to the 8259 EOI.

## Functions and Procedures

### init

```pascal
procedure init();
```

Maps the IOAPIC and LAPIC MMIO pages into the virtual address space using `kpalloc`, then reads the IOAPIC version register. If the version register returns `0` or `$FFFFFFFF`, no IOAPIC is present and the function exits after logging a message. Otherwise, it ensures the Local APIC is software-enabled by setting bit 8 of the Spurious Interrupt Vector Register (SVR) and sets the spurious vector to `$FF`. Sets `ioapic_present := true` on success.

### route_pci_irq

```pascal
procedure route_pci_irq(irq : uint8; vector : uint8);
```

Programs one IOAPIC redirection table entry to route a PCI IRQ to a specific IDT vector.

- `irq` — The PCI IRQ number (value from PCI config space `interrupt_line` field).
- `vector` — The IDT vector to deliver the interrupt to (typically `irq + 32`).

The redirection entry is configured as Fixed delivery mode, Physical destination (BSP APIC ID 0), active-low polarity, level-triggered, and unmasked. Does nothing if `ioapic_present` is `false`.

### lapic_eoi

```pascal
procedure lapic_eoi();
```

Sends an End-of-Interrupt signal to the Local APIC by writing zero to the LAPIC EOI register. Must be called for every interrupt delivered in Fixed mode through the IOAPIC. Does nothing if `ioapic_present` is `false`.

## Notes

- The IOAPIC and LAPIC MMIO regions are accessed via their physical addresses directly, relying on the identity mapping of the first 4 MiB that is established during VMM init. If these addresses fall outside the identity-mapped range, the `kpalloc` calls must map them explicitly.
- This unit does not perform ACPI MADT parsing; IOAPIC and LAPIC addresses are assumed to be at the standard Intel defaults (`$FEC00000` and `$FEE00000`).
