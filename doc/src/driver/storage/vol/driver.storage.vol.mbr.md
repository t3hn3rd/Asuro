# driver.storage.vol.mbr

Master Boot Record (MBR) data structures and partition table helpers.

## Overview

This unit defines the on-disk MBR layout and provides helpers for reading and writing partition table entries. It handles LBA-to-CHS address conversion, partition bootability flags, and population of `TPartition_table` fields in both LBA and CHS addressing formats.

The volume manager and storage manager use these types directly when reading and writing sector 0 of a disk.

## Dependencies

- `debug.tracer`

## Types

### TPartition_table / PPartition_table

One of the four 16-byte MBR partition entries (bitpacked to match on-disk layout).

| Field | Type | Description |
|---|---|---|
| `attributes` | `uint8` | Bit 7 set = bootable partition |
| `CHS_start` | `array[0..2] of uint8` | CHS address of first sector |
| `system_id` | `uint8` | Partition type byte (e.g., `$0B` = FAT32, `$EE` = GPT protective) |
| `CHS_end` | `array[0..2] of uint8` | CHS address of last sector |
| `LBA_start` | `uint32` | LBA of first sector |
| `sector_count` | `uint32` | Number of sectors in partition |

### TMaster_Boot_Record / PMaster_Boot_Record

512-byte MBR sector (bitpacked).

| Field | Description |
|---|---|
| `bootstrap` | 440 bytes of bootstrap code |
| `signature` | 4-byte disk signature |
| `rsv` | 2 reserved bytes |
| `partition` | Array of 4 `TPartition_table` entries |
| `boot_sector` | Boot signature (should be `$AA55`) |

### T24bit

`array[0..2] of uint8` — Helper type for packed 3-byte CHS values.

## Functions and Procedures

### get_bootable

```pascal
function get_bootable(partition_table : PPartition_table) : boolean;
```

Returns true if bit 7 of `attributes` is set (partition is marked bootable).

### set_bootable

```pascal
procedure set_bootable(partition_table : PPartition_table);
```

Sets bit 7 of `attributes` to mark the partition as bootable.

### setup_partition

```pascal
procedure setup_partition(partition_table : PPartition_table; address : uint32; sectorSize : uint32);
```

Populates `LBA_start`, `sector_count`, and both CHS fields of a partition entry. `address` is the starting LBA; `sectorSize` is the partition length in sectors. CHS values are computed by the internal `LBA_2_CHS` function using standard 63 sectors/track and 255 heads/cylinder geometry.

## Notes

- The internal `LBA_2_CHS` function uses fixed CHS geometry (63 sectors/track, 255 heads/cylinder). On real hardware, CHS values are largely ignored by modern BIOSes in favour of LBA addressing, but they must be present for compatibility with legacy boot loaders.
- There is a known bug in `setup_partition`: `CHS_start` is assigned twice (the second assignment overwrites the first with the end address). The `CHS_end` field is never set. This does not affect LBA-only boot scenarios.
