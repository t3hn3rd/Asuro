# arch.x86.gdt

Global Descriptor Table (GDT) data structures, gate management, and loading.

## Overview

This unit defines the GDT data structures and provides procedures to set individual segment descriptors, flush the GDT into the CPU via LGDT, and reload it after modification. During `init`, five standard descriptors are installed: a null segment, a ring-0 code segment, a ring-0 data segment, a ring-3 code segment, and a ring-3 data segment. The GDT can hold up to 1024 entries; the GDT pointer limit is updated automatically as new gates are added.

## Dependencies

- `io.syslog`

## Types

### TGDT_Entry / PGDT_Entry

```pascal
TGDT_Entry = packed record
    limit_low   : uint16;
    base_low    : uint16;
    base_middle : uint8;
    access      : uint8;
    granularity : uint8;
    base_high   : uint8;
end;
```

An 8-byte x86 segment descriptor in the standard hardware layout.

| Field        | Description |
|--------------|-------------|
| limit_low    | Lower 16 bits of the segment limit |
| base_low     | Lower 16 bits of the segment base address |
| base_middle  | Bits 16–23 of the segment base address |
| access       | Access byte: present, DPL, type flags |
| granularity  | Upper 4 bits of limit plus granularity/size flags |
| base_high    | Bits 24–31 of the segment base address |

### TGDT_Pointer

```pascal
TGDT_Pointer = packed record
    limit : uint16;
    base  : uint32;
end;
```

The 6-byte structure passed to the LGDT instruction. `limit` is the byte size of the GDT minus one; `base` is the linear address of the first GDT entry.

## Variables

### gdt_entries

```pascal
var gdt_entries : array[0..1023] of TGDT_Entry;
```

Static array holding up to 1024 GDT descriptors.

### gdt_pointer

```pascal
var gdt_pointer : TGDT_Pointer;
```

The LGDT operand. `base` is set to the address of `gdt_entries`; `limit` grows as gates are added.

## Functions and Procedures

### init

```pascal
procedure init();
```

Initialises the GDT with five standard entries and calls `flush` to load it:

| Gate | Offset | Access | Description |
|------|--------|--------|-------------|
| 0 | 0x00 | 0x00 | Null descriptor |
| 1 | 0x08 | 0x9A | Ring-0 code (execute/read, 4 GB flat) |
| 2 | 0x10 | 0x92 | Ring-0 data (read/write, 4 GB flat) |
| 3 | 0x18 | 0xFA | Ring-3 code (execute/read, 4 GB flat) |
| 4 | 0x20 | 0xF2 | Ring-3 data (read/write, 4 GB flat) |

### set_gate

```pascal
procedure set_gate(Gate_Number : uint32; Base : uint32; Limit : uint32; Access : uint8; Granularity : uint8);
```

Writes a single GDT descriptor at index `Gate_Number`. Splits `Base` and `Limit` across the appropriate fields of the `TGDT_Entry` record. Automatically updates `gdt_pointer.limit` if the new gate extends beyond the current table boundary.

### flush

```pascal
procedure flush;
```

Loads the GDT via LGDT and reloads all data segment registers (DS, ES, FS, GS, SS) with selector 0x10 (ring-0 data). A far jump to selector 0x08 (ring-0 code) flushes the instruction pipeline and reloads CS.

### reload

```pascal
procedure reload;
```

Reissues LGDT without touching segment registers. Used after adding descriptors such as a TSS when the existing segment mappings remain valid.

## Notes

- The far jump in `flush_gdt` is hand-assembled using `db`/`dw` directives because the Free Pascal inline assembler does not support far-jump syntax directly.
- Gates are numbered from 0; the segment selector for gate N is N * 8 with the lower 3 bits encoding the requested privilege level.
- The table supports up to 1024 descriptors (8 KiB), which is the hardware maximum for a 32-bit protected-mode GDT.
