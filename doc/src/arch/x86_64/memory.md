# Physical memory, virtual memory and platform adapters

The native physical allocator tracks 4 KiB frames in dynamically placed bitmaps and manages up to 64 GiB. It reserves the kernel, boot metadata, modules and allocator metadata. The virtual allocator creates high virtual arenas. Page tables are allocated below 4 GiB, while backing frames can come from higher RAM. Failed allocations release both newly created tables and backing frames.

The shared heap returns 16-byte-aligned allocations. Kernel pointers, byte counts used for allocations and saved stack addresses use native widths. Multiboot fields, filesystem records and device descriptors retain the widths specified by their formats. A 6 GiB VirtualBox run exercised mapping, writing, reading and releasing memory above 4 GiB.

Shared callers import `arch.platform.cpu`, `memory`, `interrupts`, `process` or `diagnostics` under the `arch.platform` namespace. The target profile selects the implementation at build time. A driver must translate a virtual buffer before supplying a physical DMA address and check the controller's addressing capability. OHCI has a 32-bit DMA limit. AHCI can use upper address bits when its controller supports them. Native MMIO currently uses the low 4 GiB mapping.
