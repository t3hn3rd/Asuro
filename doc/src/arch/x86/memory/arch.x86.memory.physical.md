# arch.x86.memory.physical

Physical memory manager using a bitmap-based allocator.

## Overview

This unit manages physical memory allocation for the kernel. Physical memory is divided into 1024 blocks of 4 MiB each, covering the full 32-bit 4 GiB address space. Two 1024-bit bitmaps track which blocks are present in physical RAM (`PhysPresent`) and which are currently allocated (`PhysAlloc`). A third bitmap (`PhysScanned`) prevents multiple memory map entries from conflicting on the same block.

During initialisation, the Multiboot memory map is walked to populate `PhysPresent`. The first four blocks (0 MiB–16 MiB) are pre-allocated to protect the kernel, BIOS, and boot structures. A roving hint (`NextFreeHint`) accelerates allocation by remembering the position of the last freed or allocated block.

## Dependencies

- `arch.x86.multiboot`
- `io.syslog`
- `debug.tracer`
- `core.util`
- `arch.x86.util`

## Boot Registration

Registered with `boot.mgr` as `arch.x86.memory.physical`, depending on `arch.x86.idt`.

## Constants

| Constant     | Value | Description |
|--------------|-------|-------------|
| BLOCK_COUNT  | 1024  | Total number of 4 MiB physical blocks |
| DWORD_COUNT  | 32    | Number of 32-bit words in each bitmap (1024 bits / 32) |
| RESERVED_LO  | 0     | First reserved block (inclusive) |
| RESERVED_HI  | 3     | Last reserved block (inclusive) — protects kernel and BIOS (blocks 0–3 = 0 MiB–16 MiB) |

## Functions and Procedures

### init

```pascal
procedure init;
```

Initialises the physical memory manager. Walks the Multiboot memory map to build `PhysPresent`, pre-allocates blocks 0–3, sets `NextFreeHint` to block 4, and logs the number of available blocks.

### alloc_block

```pascal
function alloc_block(block : uint16; caller : uint32) : boolean;
```

Allocates a specific physical block by index. Returns `true` on success. Triggers `GPF` if the block is out of range or not present in physical RAM. Returns `false` (without triggering GPF) if the block is already allocated.

- `block` — Zero-based block index (0–1023).
- `caller` — Identifier of the requesting subsystem, stored in `PhysOwner` for diagnostics.

### force_alloc_block

```pascal
procedure force_alloc_block(block : uint16; caller : uint32);
```

Unconditionally marks a block as allocated regardless of whether it is present in the `PhysPresent` bitmap. Used during `init` to reserve kernel and BIOS blocks.

### new_block

```pascal
function new_block(caller : uint32) : uint16;
```

Finds and allocates the next free physical block using a roving scan starting from `NextFreeHint`. Wraps around once if the end of the bitmap is reached. Returns the block index on success, or 0 if no free block is available (out-of-memory condition). Logs an error message on OOM.

### free_block

```pascal
procedure free_block(block : uint16; caller : uint32);
```

Releases a previously allocated block. Triggers `GPF` for invalid inputs: out-of-range index, attempt to free a reserved block (0–3), freeing a block not present in physical RAM, double-free, or freeing a block owned by a different caller. Updates `NextFreeHint` if the freed block is earlier than the current hint.

### pmm_free_blocks

```pascal
function pmm_free_blocks : uint32;
```

Returns the current count of free (present and unallocated) physical blocks.

### pmm_total_blocks

```pascal
function pmm_total_blocks : uint32;
```

Returns the total number of blocks present in physical RAM (set during `init` from the Multiboot memory map).

## Notes

- Block N covers physical address range `[N * 4 MiB, (N+1) * 4 MiB)`.
- The PMM does not support sub-block granularity. Fine-grained allocation within a block is the responsibility of the heap allocator (`memory.heap`), which operates within VMM-mapped pages.
- `new_block` returns 0 on OOM. Callers must check for this sentinel and handle the out-of-memory condition; block 0 is always reserved and can never be legitimately returned.
- The ownership check in `free_block` uses the `caller` parameter passed at free time against the value stored at alloc time; callers must pass a consistent identifier.
