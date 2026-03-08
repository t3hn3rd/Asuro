# driver.storage.fs.asfs

ASFS — Asuro File System driver (early prototype, incomplete).

## Overview

ASFS is a custom filesystem format designed specifically for Asuro. The on-disk layout uses a single-sector filesystem record header followed by a file table where each entry stores a filename, timestamps, attributes, disk location, and sector count.

This unit is an early prototype. The `detect_volumes` procedure is a stub. Only `create_volume` contains functional code. Most filesystem callbacks (`readDirCallback`, `createDirCallback`, `writeCallback`) are commented out and not wired into the `TFilesystem` descriptor registered with the filesystem manager.

The unit depends on `storagemanagement` (legacy module name) and `driver.io.serial`, neither of which is present in current builds, so this driver cannot be compiled as-is without resolving those dependencies.

## Dependencies

- `io.syslog`
- `core.ds.lists`
- `memory.heap`
- `driver.timer.rtc`
- `driver.io.serial`
- `storagemanagement` (legacy)
- `driver.storage.mgr`
- `core.strings`
- `io.stdio`
- `debug.tracer`
- `core.util`, `arch.x86.util`

## Types

### TFilesystemRecord / PFilesystemRecord

On-disk ASFS volume header (bitpacked).

| Field | Description |
|---|---|
| `magicNumber` | Format magic: `$A2F2` |
| `sectorSize` | Bytes per sector |
| `sectorsPerTable` | Number of sectors in the file table |
| `totalSectors` | Total sector count of the volume |
| `volumeLabel` | 16-byte volume label |
| `endOfData` | Sector index of the first free data sector |

### TFileEntry / PFileEntry

One ASFS file table entry (bitpacked).

| Field | Description |
|---|---|
| `filename` | 16-byte filename |
| `lastWriteDate` | Last write timestamp: year (2000+x), month, day, hour |
| `lastReadDate` | Last read timestamp |
| `attributes` | `0` = null, `1` = file, `2` = folder, `3` = this folder, `4` = parent folder, `5` = table continuation, `6` = volume root |
| `extension` | 7-byte file extension |
| `location` | Starting sector on disk |
| `numSectors` | File size in sectors |

## Functions and Procedures

### init

```pascal
procedure init;
```

Populates the static filesystem descriptor and registers it with the filesystem manager via `storagemanagement.register_filesystem`. Sets `createCallback` and `detectCallback`; read/write callbacks remain unregistered.

### create_volume

```pascal
procedure create_volume(disk : PStorage_Device; sectors : uint32; start : uint32; config : puint32);
```

Formats an ASFS volume: writes the `TFilesystemRecord` header to `start`, then writes an initial file table sector with a volume root entry (`.`) and a parent entry (`..`).

### detect_volumes

```pascal
procedure detect_volumes(disk : PStorage_Device);
```

Stub — currently empty. Volume detection is not implemented.

## Notes

- ASFS is not used in current Asuro builds. FAT32 and FlatFS are the active filesystems.
- The `create_volume` procedure contains syntactic issues (missing `begin` before the procedure body `begin`, use of `PFilesystemRecord := ...` as a cast statement) that prevent compilation without fixes.
- The `storagemanagement` dependency refers to a legacy module that has been superseded by `driver.storage.mgr`; this unit would need to be updated to build.
