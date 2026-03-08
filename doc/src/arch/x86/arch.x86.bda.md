# arch.x86.bda

BIOS Data Area (BDA) structures and system tick counter management.

## Overview

This unit maps the x86 BIOS Data Area, which is a region of conventional memory at physical address 0x400 that the BIOS populates with hardware configuration data. It also defines a software tick counter (`TCounters`) that is incremented by the timer ISR on every system tick. The BDA pointer is mapped to the virtual address `$C0000400` (physical `$400` plus the kernel virtual base), which is valid once paging is active.

## Dependencies

- `arch.x86.memory.virtual` (implementation)

## Types

### TBDA / PBDA

```pascal
TBDA = bitpacked record
    COM1            : uint16;
    COM2            : uint16;
    COM3            : uint16;
    COM4            : uint16;
    LPT1            : uint16;
    LPT2            : uint16;
    LPT3            : uint16;
    EBDA            : uint16;
    Hardware_Flags  : uint16;
    Keyboard_Flags  : uint16;
    Keyboard_Buffer : ARRAY[0..31] OF uint8;
    Display_Mode    : uint8;
    BaseIO          : uint16;
    Ticks           : uint16;
    HDD_Count       : uint8;
    Keyboard_Start  : uint16;
    Keyboard_End    : uint16;
    Keyboard_State  : uint8;
end;
```

Maps selected fields of the BIOS Data Area. Notable fields:

| Field           | Description |
|-----------------|-------------|
| COM1–COM4       | I/O port base addresses for serial COM ports |
| LPT1–LPT3      | I/O port base addresses for parallel ports |
| EBDA            | Segment address of the Extended BIOS Data Area |
| Hardware_Flags  | Hardware presence flags set by the BIOS POST |
| Keyboard_Flags  | Modifier key state (Shift, Ctrl, Alt, etc.) |
| Keyboard_Buffer | BIOS keyboard input ring buffer |
| Display_Mode    | Current display mode number |
| Ticks           | Low 16-bit system tick counter incremented by the BIOS timer ISR (INT 8); also updated by `tick_update` |
| HDD_Count       | Number of hard drives detected by the BIOS |
| Keyboard_Start  | Offset of the start of the keyboard buffer within the BDA |
| Keyboard_End    | Offset of the end of the keyboard buffer within the BDA |
| Keyboard_State  | Additional keyboard state flags |

### TMCFG / PMCFG

```pascal
TMCFG = bitpacked record
    Signature        : Array[0..3] of Char;
    Table_Length     : uint32;
    Revision         : Byte;
    Checksum         : Byte;
    OEM_ID           : Array[0..5] of Byte;
    OEM_Table_ID     : uint64;
    OEM_Revision     : uint32;
    Creator_ID       : uint32;
    Creator_Revision : uint32;
    Reserved         : uint64;
end;
```

Describes the MCFG ACPI table header, used for PCI Express base address discovery. Defined here for convenience alongside other BIOS-area structures.

### TCounters

```pascal
TCounters = record
    c16 : uint16;
    c32 : uint32;
    c64 : uint64;
end;
```

Software tick counters maintained by `tick_update`. Provides 16-bit, 32-bit, and 64-bit monotonic counters all incremented synchronously on each timer interrupt.

## Constants

### BDA

```pascal
const BDA : PBDA = PBDA($C0000400);
```

Pointer to the BIOS Data Area, mapped at the kernel virtual address corresponding to physical address 0x400.

## Variables

### Counters

```pascal
var Counters : TCounters;
```

Global software tick counters. All three fields (`c16`, `c32`, `c64`) are incremented by `tick_update` on every timer interrupt.

## Functions and Procedures

### tick_update

```pascal
procedure tick_update(data : void);
```

Timer ISR callback. Increments `BDA^.Ticks`, `Counters.c16`, `Counters.c32`, and `Counters.c64` by one. Intended to be registered as a hook on the timer 0 ISR (`arch.x86.isr.tmr0`).

## Notes

- The BDA pointer is valid only after paging is enabled and the first 4 MiB of physical memory is mapped to `KERNEL_VIRTUAL_BASE`. Accessing `BDA` before paging is active will cause a fault.
- `Ticks` in the BDA is a 16-bit field and will wrap after 65 535 ticks. Code that requires longer time spans should use `Counters.c32` or `Counters.c64`.
