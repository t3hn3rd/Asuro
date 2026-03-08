# driver.storage.fs.fat32

FAT32 filesystem driver.

## Overview

This unit implements a FAT32 filesystem driver for Asuro, providing volume formatting, detection, and file I/O. FAT32 is the primary read-write filesystem used on fixed disks in Asuro. The driver registers itself with `driver.storage.fs.mgr` at `init` time.

Both synchronous and asynchronous volume formatting are supported. The async format path uses a state-machine context (`TFmtContext`) that progresses through the steps: write boot sector, zero FAT, write FAT entries, create root directory, create system directory, and mark done. Each step issues one I/O operation and advances the state machine in the completion callback.

## Dependencies

- `driver.storage.fs.mgr`
- `core.ds.lists`
- `memory.heap`
- `proc.mgr`, `proc.types`
- `driver.timer.rtc`
- `io.stdio`
- `driver.storage.mgr`
- `driver.storage.types`
- `core.strings`
- `io.syslog`
- `debug.tracer`
- `core.util`, `arch.x86.util`
- `driver.storage.vol.mgr`

## Types

### TBootRecord / PBootRecord

FAT32 BPB (BIOS Parameter Block) and extended boot record. Packed to match the on-disk layout.

Key fields:

| Field | Description |
|---|---|
| `sectorSize` | Bytes per sector (typically 512) |
| `spc` | Sectors per cluster |
| `rsvSectors` | Reserved sectors before FAT |
| `numFats` | Number of FAT copies |
| `FATSize` | Sectors per FAT |
| `rootCluster` | First cluster of root directory |
| `identString` | Should contain `'FAT32   '` |

### TDirectory / PDirectory

FAT32 32-byte directory entry (short name format).

| Field | Description |
|---|---|
| `fileName` | 8-character base name |
| `fileExtension` | 3-character extension |
| `attributes` | Entry attributes byte |
| `clusterHigh` / `clusterLow` | High and low words of first cluster |
| `byteSize` | File size in bytes |

### TFilesystemInfo

FAT32 FSInfo sector structure. Contains free sector count and next free sector hint.

### TFmtContext / PFmtContext

State machine context for async volume formatting. Tracks the current step, volume geometry, buffer pointers, and the user callback to fire on completion.

| Field | Description |
|---|---|
| `Step` | Current format step (`TFmtStep`) |
| `Volume` | Volume being formatted |
| `FATStart` / `DataStart` | Calculated FAT and data region start sectors |
| `FATSize` | Number of FAT sectors |
| `BatchPos` / `BatchSize` | Progress through multi-sector write batches |
| `Buffer` / `ZeroBuffer` | Working buffers (freed on completion) |
| `Callback` / `CallbackData` | User completion callback |

## Functions and Procedures

### init

```pascal
procedure init;
```

Populates the `filesystem` descriptor and registers it with the filesystem manager.

### create_volume

```pascal
procedure create_volume(volume : PStorage_Volume; sectors : uint32; start : uint32; config : puint32);
```

Synchronously formats the partition as FAT32: writes the boot record, zeroes both FAT copies, sets up the root cluster chain entry, and creates the root and system directories.

### create_volume_async

```pascal
procedure create_volume_async(volume : PStorage_Volume; sectors : uint32; start : uint32; config : puint32; callback : TIOCallback; callbackData : pointer);
```

Begins an asynchronous format. Allocates a `TFmtContext`, writes the boot sector, and returns immediately. Each subsequent I/O completion advances the state machine until `fmtDone`, at which point `callback` is fired.

### detect_volumes

```pascal
procedure detect_volumes(disk : PStorage_Device);
```

Not used for FAT32 on partitioned disks (partition table parsing is handled by the volume manager). May be called for unpartitioned FAT32 media.

## Notes

- FAT32 identification is performed by `identifyCallback` (not shown in the interface), which reads the boot sector and checks `identString` for `'FAT32'`.
- The `spc` (sectors per cluster) value is calculated during format based on partition size to keep cluster count within FAT32 valid bounds.
- Timestamps for directory entries are obtained from `driver.timer.rtc`.
- The async format path allocates `TFmtContext` on the heap; it is freed in the final state-machine step after firing the callback.
