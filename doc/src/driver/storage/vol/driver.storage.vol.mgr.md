# driver.storage.vol.mgr

Partition and volume management.

## Overview

The volume manager owns the global volume list and all partition operations. It is the layer between raw device I/O (storage manager) and the filesystem drivers. When a device is registered, `driver.storage.mgr` calls `discover_volumes` to parse the partition table and create `TStorage_Volume` instances for each valid partition.

Volume discovery supports three paths:
1. **ATAPI/optical**: bypasses partition table parsing and calls each registered filesystem's `detectCallback` directly (handles ISO 9660 media with hybrid MBR).
2. **GPT**: if any MBR partition entry has system ID `$EE`, reads the GPT header at LBA 1, validates it, and creates volumes from the GPT partition array.
3. **MBR (classic)**: reads the MBR and creates volumes for each non-empty partition entry.

After volumes are created, `probe_volume` assigns a filesystem driver to each one. If no filesystem is identified, the volume's `filesystem` field remains nil.

## Dependencies

- `io.syslog`
- `driver.storage.fs.mgr`
- `core.ds.lists`
- `memory.heap`
- `driver.storage.vol.mbr`
- `driver.storage.vol.gpt`
- `driver.storage.mgr`
- `driver.storage.types`
- `core.strings`
- `io.stdio`
- `debug.tracer`
- `core.util`, `arch.x86.util`

## Boot Registration

Registered with `boot.mgr` as `driver.storage.vol.mgr`, depending on glob `driver.storage.mgr*` (waits for all matching entries).

## Variables

| Name | Type | Description |
|---|---|---|
| `volumes` | `PDList` | Global list of all registered `PStorage_Volume` pointers |

## Functions and Procedures

### init

```pascal
procedure init();
```

Allocates the global volume list. Must be called before volume manager functions are used.

### get_volume_list

```pascal
function get_volume_list() : PDList;
```

Returns the global volume list.

### get_volume_count

```pascal
function get_volume_count() : uint32;
```

Returns the number of registered volumes.

### get_volume

```pascal
function get_volume(index : uint32) : PStorage_Volume;
```

Returns the volume at `index`, or nil if out of range.

### register_volume

```pascal
procedure register_volume(device : PStorage_Device; volume : PStorage_Volume);
```

Adds `volume` to both the global list and the device's per-device volume list.

### create_volume_from_partition

```pascal
procedure create_volume_from_partition(device : PStorage_Device; sectorStart : uint32; sectorCount : uint32);
```

Allocates a `TStorage_Volume`, populates it from the device and partition geometry, calls `probe_volume` to identify the filesystem, and registers it.

### get_partition

```pascal
function get_partition(device : PStorage_Device; index : uint32) : TPartition_table;
```

Returns the MBR partition entry at `index` (0..3) from the device's cached MBR. Returns a zeroed record if the device is nil, the index is out of range, or no MBR is cached.

### add_partition

```pascal
procedure add_partition(device : PStorage_Device; slot : uint32; partition : TPartition_table);
```

Writes `partition` to MBR slot `slot` (0..3) and creates the corresponding volume in memory. Does nothing if the device is nil, the slot is out of range, or the device is read-only.

### remove_partition

```pascal
procedure remove_partition(device : PStorage_Device; slot : uint32);
```

Zeros MBR slot `slot` and removes the corresponding volume from the global and device lists.

### init_disk

```pascal
procedure init_disk(device : PStorage_Device);
```

Removes all volumes for the device, writes a clean MBR (only the `$AA55` signature, all partition entries zeroed). Used as the first step of the destructive disk test.

### discover_volumes

```pascal
procedure discover_volumes(device : PStorage_Device);
```

Detects and registers all partitions on `device`. Handles ATAPI, GPT, and MBR cases as described in the Overview. If no volume is identified by any filesystem after partition detection, calls each filesystem's `detectCallback` on the raw device as a fallback.

### find_free_space

```pascal
function find_free_space(device : PStorage_Device; needed : uint32) : uint32;
```

Scans the device's partition table to find a contiguous free region of at least `needed` sectors. Returns the starting LBA of the free region, or 0 if none found.

### find_free_slot

```pascal
function find_free_slot(device : PStorage_Device) : sint32;
```

Returns the index (0..3) of the first empty MBR partition slot, or -1 if all slots are occupied.

### get_free_sector_count

```pascal
function get_free_sector_count(device : PStorage_Device) : uint32;
```

Returns the number of sectors on the device not covered by any MBR partition entry.

### add_partition_async

```pascal
procedure add_partition_async(device : PStorage_Device; slot : uint32; partition : TPartition_table;
                              callback : TIOCallback; callbackData : pointer);
```

Non-blocking version of `add_partition`. Fires `callback` when the MBR write completes.

### remove_partition_async

```pascal
procedure remove_partition_async(device : PStorage_Device; slot : uint32;
                                 callback : TIOCallback; callbackData : pointer);
```

Non-blocking version of `remove_partition`.

### init_disk_async

```pascal
procedure init_disk_async(device : PStorage_Device;
                          callback : TIOCallback; callbackData : pointer);
```

Non-blocking version of `init_disk`.

### format_volume

```pascal
function format_volume(device : PStorage_Device; volIndex : uint32; filesystemName : pchar; config : puint32) : boolean;
```

Finds the filesystem driver named `filesystemName` and calls its `createCallback` on the volume at `volIndex`. Returns true if the driver was found and the callback was invoked.

### format_volume_async

```pascal
function format_volume_async(device : PStorage_Device; volIndex : uint32; filesystemName : pchar; config : puint32; callback : TIOCallback; callbackData : pointer) : boolean;
```

Non-blocking version of `format_volume`. Uses `createAsyncCallback` if available, falls back to the synchronous callback.

### delete_volume

```pascal
procedure delete_volume(volume : PStorage_Volume);
```

Removes a volume from the global and device lists and frees its memory.

## Notes

- The global volume list stores `PStorage_Volume` pointers (not value copies); the device's per-device list stores the same pointers.
- `discover_volumes` calls `probe_volume` via `create_volume_from_partition` for each partition. If the fallback `detectCallback` path creates additional volumes, those are also probed.
- GPT partition entries with `StartLBA_Hi` or `EndLBA_Hi` non-zero are skipped because the kernel runs in 32-bit protected mode and cannot address LBAs beyond 32 bits.
