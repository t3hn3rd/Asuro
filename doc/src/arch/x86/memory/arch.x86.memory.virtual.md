# arch.x86.memory.virtual

Virtual memory manager using 4 MiB page directory entries (PSE).

## Overview

This unit manages the kernel's virtual address space using the x86 Page Size Extension (PSE) feature, where each page directory entry (PDE) maps a 4 MiB region directly to a physical 4 MiB block. The page directory contains 1024 entries, giving a 4 GiB virtual address space. The kernel occupies the upper 1 GiB (page directory indices 768–1023, virtual addresses `$C0000000`–`$FFFFFFFF`).

During `init`, the current page directory loaded by the bootloader is adopted as the kernel page directory, and the first four kernel pages are mapped to physical blocks 0–3. New pages are allocated on demand by obtaining a physical block from `arch.x86.memory.physical` and mapping it. TLB invalidation is performed via CR3 reload or `INVLPG` as appropriate.

## Dependencies

- `core.util`
- `arch.x86.util`
- `arch.x86.memory.physical`
- `io.syslog`
- `debug.tracer`
- `memory.heap` (implementation)

## Boot Registration

Registered with `boot.mgr` as `arch.x86.memory.virtual`, depending on `arch.x86.memory.physical`.

## Types

### TPageDirEntry / PPageDirEntry

```pascal
TPageDirEntry = bitpacked record
    Present, Writable, UserMode, WriteThrough,
    NotCacheable, Accessed, Reserved, PageSize,
    GlobalPage : Boolean;
    Available  : UBit3;
    Address    : UBit20;
end;
```

A single 32-bit page directory entry in PSE mode.

| Field        | Description |
|--------------|-------------|
| Present      | Set if the mapping is valid |
| Writable     | Allows write access |
| UserMode     | Allows access from CPL 3 (ring 3 / V86) |
| WriteThrough | Enables write-through caching |
| NotCacheable | Disables caching for this region |
| Accessed     | Set by CPU on access |
| Reserved     | Must be zero |
| PageSize     | Must be set for 4 MiB PSE pages |
| GlobalPage   | Marks a global page (not flushed on CR3 reload) |
| Available    | Three bits available for OS use |
| Address      | Upper 20 bits of the 4 MiB physical block address (block index shifted left by 10) |

### TPageDirectory / PPageDirectory

```pascal
TPageDirectory = Array[0..1023] of TPageDirEntry;
```

An array of 1024 page directory entries covering the full 4 GiB address space.

## Variables

### KERNEL_PAGE_DIRECTORY

```pascal
var KERNEL_PAGE_DIRECTORY : PPageDirectory;
```

Pointer to the global kernel page directory. Set during `init` to the page directory active at kernel entry.

### PageDirectory

```pascal
var PageDirectory : PPageDirectory;
```

Pointer to the currently active page directory. Initially identical to `KERNEL_PAGE_DIRECTORY`; may differ for process-private address spaces.

## Functions and Procedures

### init

```pascal
procedure init;
```

Reads the current CR3 value to obtain the physical address of the boot page directory, adjusts it by `KERNEL_VIRTUAL_BASE` to get the virtual address, and stores it in both `PageDirectory` and `KERNEL_PAGE_DIRECTORY`. Maps kernel pages 0–3 to physical blocks 0–3.

### new_page

```pascal
function new_page(page_number : uint16) : boolean;
```

Allocates a new physical block and maps it to page directory entry `page_number`. Returns `false` if the page is already present, the entry is reserved, or the PMM has no free blocks.

### page_mappable

```pascal
function page_mappable(page_number : uint16) : boolean;
```

Returns `true` if `page_number` is neither present nor reserved in the current page directory.

### map_page

```pascal
function map_page(page_number : uint16; block : uint16) : boolean;
```

Maps page directory entry `page_number` to physical block `block` in the current `PageDirectory`. Reloads CR3 to flush the TLB.

### map_page_ex

```pascal
function map_page_ex(page_number : uint16; block : uint16; PD : PPageDirectory) : boolean;
```

Maps page directory entry `page_number` to physical block `block` in the specified page directory `PD`. Does not reload CR3. Used internally and by `arch.x86.v86.init`.

### map_page_user

```pascal
function map_page_user(page_number : uint16; block : uint16) : boolean;
```

Maps a page directory entry with the UserMode bit set, allowing CPL 3 (V86) access. Reloads CR3 after mapping.

### new_page_at_address

```pascal
function new_page_at_address(address : uint32) : boolean;
```

Convenience wrapper. Derives the page directory index from `address` (top 10 bits) and calls `new_page`.

### free_page

```pascal
procedure free_page(page_number : uint16);
```

Clears the page directory entry at `page_number`, invalidates the corresponding TLB entry via `INVLPG`, and returns the physical block to the PMM. Triggers `GPF` if the page is not currently present.

### free_page_at_address

```pascal
procedure free_page_at_address(address : uint32);
```

Convenience wrapper. Derives the page directory index from `address` and calls `free_page`.

### new_page_directory

```pascal
function new_page_directory : uint32;
```

Allocates a new blank page directory from the kernel heap and returns its virtual address.

### new_kernel_mapped_page_directory

```pascal
function new_kernel_mapped_page_directory : uint32;
```

Allocates a new page directory and copies all kernel-space PDE entries (indices `KERNEL_PAGE_NUMBER`–1023) from `KERNEL_PAGE_DIRECTORY`. Returns the virtual address of the new directory. Used to create per-process address spaces that share the kernel mapping.

### vtop

```pascal
function vtop(address : uint32) : uint32;
```

Translates a virtual address to its physical address using the kernel page directory. Extracts the PDE index from the top 10 bits of `address`, reads the physical block base from that entry, and adds the low 22-bit offset.

## Notes

- This VMM uses 4 MiB PSE pages exclusively. There is no second-level page table; each PDE maps a full 4 MiB region.
- The `Address` field in `TPageDirEntry` stores the block index shifted left by 10 (to align with the 4 MiB block address format in the PDE). `vtop` accounts for this by shifting right by 12 to recover the physical base.
- `KERNEL_PAGE_NUMBER` is `KERNEL_VIRTUAL_BASE shr 22 = 768`, meaning the first 3 GiB of virtual space is available for user/process mappings.
