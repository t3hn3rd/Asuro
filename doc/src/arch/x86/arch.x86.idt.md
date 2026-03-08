# arch.x86.idt

Interrupt Descriptor Table (IDT) data structures, gate registration, and loading.

## Overview

This unit defines the 256-entry IDT used by the x86 interrupt system. It provides constants for the four privilege-level gate flag bytes, a procedure to install individual interrupt gates, and an `init` routine that clears the table and loads it into the CPU via LIDT. Each call to `set_gate` immediately reloads the IDT so that the new handler is active as soon as the procedure returns.

## Dependencies

- `core.util`
- `arch.x86.util`
- `io.syslog`

## Constants

### ISR_RING_0

`$8E` — Gate flags for a ring-0 interrupt gate (present, DPL 0, 32-bit interrupt gate type).

### ISR_RING_1

`$AE` — Gate flags for a ring-1 interrupt gate (present, DPL 1, 32-bit interrupt gate type).

### ISR_RING_2

`$CE` — Gate flags for a ring-2 interrupt gate (present, DPL 2, 32-bit interrupt gate type).

### ISR_RING_3

`$EE` — Gate flags for a ring-3 interrupt gate (present, DPL 3, 32-bit interrupt gate type).

## Types

### TIDT_Entry / PIDT_Entry

```pascal
TIDT_Entry = packed record
    base_low  : uint16;
    selector  : uint16;
    always_0  : uint8;
    flags     : uint8;
    base_high : uint16;
end;
```

An 8-byte x86 interrupt gate descriptor in the hardware layout.

| Field     | Description |
|-----------|-------------|
| base_low  | Lower 16 bits of the handler entry-point address |
| selector  | Code segment selector for the handler |
| always_0  | Reserved byte, must be zero |
| flags     | Gate type and privilege flags (use `ISR_RING_*` constants) |
| base_high | Upper 16 bits of the handler entry-point address |

### TIDT_Pointer / PIDT_Pointer

```pascal
TIDT_Pointer = packed record
    limit : uint16;
    base  : uint32;
end;
```

The 6-byte operand passed to LIDT. `limit` is always `(sizeof(TIDT_Entry) * 256) - 1`; `base` is the linear address of `IDT_Entries`.

## Variables

### IDT_Entries

```pascal
var IDT_Entries : Array [0..255] of TIDT_Entry;
```

Static array of 256 interrupt gate descriptors.

### IDT_Pointer

```pascal
var IDT_Pointer : TIDT_Pointer;
```

The LIDT operand, initialised during `init`.

## Functions and Procedures

### init

```pascal
procedure init();
```

Sets up `IDT_Pointer`, zeroes the entire `IDT_Entries` array using `core.util.memset`, and loads the IDT via LIDT. Must be called before any interrupt gates are installed.

### set_gate

```pascal
procedure set_gate(Number : uint8; Base : uint32; Selector : uint16; Flags : uint8);
```

Installs an interrupt gate at index `Number`. Splits `Base` into `base_low` and `base_high`, sets the code segment `Selector` (typically `$08` for the ring-0 code segment), writes the `Flags` byte, and zeroes `always_0`. Calls LIDT immediately after writing so the gate is live.

Parameters:
- `Number` — IDT vector number (0–255).
- `Base` — Linear address of the ISR entry point.
- `Selector` — GDT code segment selector used when the handler is invoked.
- `Flags` — Gate type and DPL flags; use one of the `ISR_RING_*` constants.

## Notes

- The IDT is reloaded after every `set_gate` call. This is safe but slightly inefficient when installing many gates in sequence.
- Vectors 0–31 are reserved for CPU exceptions; vectors 32–255 are available for hardware IRQs and software interrupts.
