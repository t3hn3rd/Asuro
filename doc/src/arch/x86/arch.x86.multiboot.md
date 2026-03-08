# arch.x86.multiboot

Multiboot specification structures and boot-time information access.

## Overview

This unit defines the data structures described by the Multiboot specification that the bootloader (typically GRUB) passes to the kernel at startup. It exposes the multiboot information pointer (`multibootinfo`) and magic number (`multibootmagic`) as global variables that are set by the early boot assembly stub before Pascal code is entered. Other subsystems, particularly the physical memory manager and framebuffer initialisation, read from these structures to discover available RAM, modules, and display parameters.

## Constants

### KERNEL_STACKSIZE

`$4000` (16 384 bytes) — Size of the kernel stack allocated in the boot assembly.

### MULTIBOOT_BOOTLOADER_MAGIC

`$2BADB002` — Magic value placed in EAX by a Multiboot-compliant bootloader. The boot stub compares the value in EAX against this constant and stores it in `multibootmagic`.

## Types

### elf_section_header_table_t / Pelf_section_header_table_t

```pascal
elf_section_header_table_t = packed record
    num   : uint32;
    size  : uint32;
    addr  : uint32;
    shndx : uint32;
end;
```

Embedded inside `multiboot_info_t`. Describes the ELF section header table if the bootloader provided it (Multiboot flags bit 5).

| Field | Description |
|-------|-------------|
| num   | Number of section headers |
| size  | Size in bytes of each section header |
| addr  | Physical address of the section header table |
| shndx | Index of the string-table section header |

### multiboot_info_t / Pmultiboot_info_t

The primary Multiboot information structure. Selected fields:

| Field              | Description |
|--------------------|-------------|
| flags              | Bitmask indicating which fields are valid |
| mem_lower          | Amount of lower memory in kilobytes |
| mem_upper          | Amount of upper memory in kilobytes |
| boot_device        | Boot device identifier |
| cmdline            | Physical address of the kernel command line string |
| mods_count         | Number of loaded modules |
| mods_addr          | Physical address of the first module_t entry |
| elf_sec            | ELF section header information |
| mmap_length        | Byte length of the memory map buffer |
| mmap_addr          | Physical address of the memory map buffer |
| drives_legnth      | Byte length of the drives table (note: field name has a typo in the source) |
| drives_addr        | Physical address of the drives table |
| config_table       | Physical address of ROM configuration table |
| boot_loader_name   | Physical address of the bootloader name string |
| apm_table          | Physical address of the APM table |
| vbe_control_info   | Physical address of VBE control information |
| vbe_mode_info      | Physical address of VBE mode information |
| vbe_mode           | Current VBE video mode number |
| vbe_interface_seg  | VBE protected-mode interface segment |
| vbe_interface_off  | VBE protected-mode interface offset |
| vbe_interface_len  | VBE protected-mode interface length |
| framebuffer_addr   | 64-bit physical address of the framebuffer |
| framebuffer_pitch  | Bytes per framebuffer row |
| framebuffer_width  | Framebuffer width in pixels |
| framebuffer_height | Framebuffer height in pixels |
| framebuffer_bpp    | Bits per pixel |

### module_t / Pmodule_t

```pascal
module_t = packed record
    mod_start : uint32;
    mod_end   : uint32;
    name      : uint32;
    reserved  : uint32;
end;
```

Describes a single Multiboot module (e.g., an initial ramdisk).

| Field     | Description |
|-----------|-------------|
| mod_start | Physical start address of the module |
| mod_end   | Physical end address of the module |
| name      | Physical address of the module name string |
| reserved  | Must be zero |

### memory_map_t / Pmemory_map_t

```pascal
memory_map_t = packed record
    size      : uint32;
    base_addr : uint64;
    length    : uint64;
    mtype     : uint32;
end;
```

A single entry in the Multiboot memory map. Entries are variable-length; advance by `size + sizeof(size)` bytes to reach the next entry.

| Field     | Description |
|-----------|-------------|
| size      | Size of this entry, not including this field itself |
| base_addr | 64-bit base physical address of the region |
| length    | 64-bit length of the region in bytes |
| mtype     | Region type: 1 = available RAM, other values = reserved/ACPI/etc. |

## Variables

### multibootinfo

```pascal
var multibootinfo : Pmultiboot_info_t = nil;
```

Pointer to the Multiboot information structure passed by the bootloader. Set by the assembly boot stub before `kmain` is called. Must not be dereferenced until after virtual memory is initialised (the address requires the kernel virtual base offset applied).

### multibootmagic

```pascal
var multibootmagic : uint32;
```

The value found in EAX at kernel entry, saved by the boot stub. Should equal `MULTIBOOT_BOOTLOADER_MAGIC` to confirm a valid Multiboot load.

## Notes

- All addresses inside `multiboot_info_t` are physical addresses provided by the bootloader. After paging is enabled with a higher-half kernel layout, they must have `KERNEL_VIRTUAL_BASE` added before dereferencing.
- The physical memory manager (`arch.x86.memory.physical`) walks the `memory_map_t` array pointed to by `mmap_addr` and `mmap_length` to determine which 4 MiB blocks are available for allocation.
