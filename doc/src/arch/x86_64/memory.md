# Physical memory, virtual memory and platform adapters

The native physical allocator indexes usable 4 KiB frames up to the physical address width reported by the processor. Sorted frame ranges share two compact bitmaps, so holes between RAM ranges require no bitmap space. The range descriptors and bitmaps must fit in usable bootstrap RAM below 4 GiB. DMA32 runs stay within a contiguous physical range below 4 GiB. It places both bitmaps in a contiguous page-aligned range below 4 GiB. Placement and frame reservation use the same Multiboot object ranges. Free pages between modules remain available, and even a partial-page overlap with a module or a reserved firmware range excludes the whole frame. The native PMM regression checks a four-page gap immediately below a high boot module and rejects a five-page request for that gap. A synthetic native regression allocates, reserves and frees sparse frames across 64 GiB and at 64 TiB. The virtual allocator creates high virtual arenas. Page tables are allocated below 4 GiB, while backing frames can come from higher RAM. Failed allocations release both newly created tables and backing frames.

The shared heap returns 16-byte-aligned allocations. Kernel pointers, byte counts used for allocations and saved stack addresses use native widths. Multiboot fields, filesystem records and device descriptors retain the widths specified by their formats. A 6 GiB VirtualBox run exercised mapping, writing, reading and releasing memory above 4 GiB.

Shared callers import `arch.platform.cpu`, `memory`, `interrupts`, `process` or `diagnostics` under the `arch.platform` namespace. The target profile selects the implementation at build time. A driver must translate a virtual buffer before supplying a physical DMA address and check the controller's addressing capability. OHCI has a 32-bit DMA limit. AHCI can use upper address bits when its controller supports them. Native MMIO below 4 GiB uses the bootstrap identity map. The mapper splits affected 2 MiB leaves into 4 KiB entries and marks only the requested pages uncached. Higher and boundary-crossing ranges use uncached 4 KiB mappings that preserve the offset within the first page. OHCI and DMA32 AHCI use low controller structures and stage transfers backed by high RAM.

## FAT32 high-memory differential

Build the native `test:complex` ISO, then run the two commands below on Windows with Python, VirtualBox and a WSL distribution named `Ubuntu` containing `mkfs.fat` and Linux VFAT mount support.

```powershell
python tools/test-storage-differential.py
python tools/test-storage-differential.py --serial
```

Each command boots four fresh 6 GiB VMs from the same ISO. Each VM has a disposable FAT32 partition labelled `ASURODIFF` and a fixture identifier in its MBR. The guest checks both before starting the write workload. Use `--controller ahci` or `--controller ohci` for one pair. The runner prints the location of its per-case serial logs and offline results under the build directory. A failing case makes the command exit with status 1.

Each worker verifies all 33 physical pages of its high virtual buffer are in the selected address range. The workers use different deterministic byte patterns and separate files in the same directory. Each appends 4095, 4096, 4097 and 131073 bytes through VFS, closes, reopens and checks each extent, with guards around unaligned buffers. The guest watchdog reports the worker, offset, transfer length and operation phase on a timeout. A separate aligned sector read bypasses FAT caching. On OHCI it checks that the USB mass-storage driver submitted 512 bytes through its low staging buffer. After power-off the host independently mounts a read-only clone and checks each file against the expected 143361 bytes.

On 2026-11-27, all four serialized cases passed. All four concurrent cases failed on the same ISO. One worker's first 4095-byte read returned zero after a successful write and close. The other worker's file matched in full. Offline inspection found the affected file empty or missing. The failure reproduced with both controllers and both physical placements. In traced AHCI runs with both physical placements, FAT32EnsureDirEntry selected slot 1 of root directory sector 0x1002 for both files. Both creates wrote a full sector from a private snapshot. When WORKA.BIN closed, its saved slot already held WORKB.BIN, and FAT32CloseFile updated that entry with the first file's size and starting cluster. The host found WORKA.BIN missing in both runs.

After the FAT32 metadata locking fix on 2026-11-28, all four concurrent cases passed. On AHCI and OHCI, with both low and high physical backing, each guest reopened and verified both files. The host independently verified all 143361 bytes of each file after shutdown.

### Ext2 coverage

Run `python tools/test-storage-differential.py --filesystem ext2` to repeat the concurrent workload on an ext2 partition created with WSL Ubuntu's `mkfs.ext2`. The fixture uses 4 KiB blocks, 128-byte inodes and the filetype and sparse_super features. The runner checks the filesystem reported by the guest and independently mounts the result as ext2, read-only. FAT32 remains the default.

On 2026-11-28 all four concurrent ext2 cases passed on x86-64, covering AHCI and OHCI with both low and high physical backing. Both files matched all 143361 expected bytes after shutdown in every case.
