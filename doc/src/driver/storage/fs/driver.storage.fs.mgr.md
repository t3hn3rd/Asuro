# driver.storage.fs.mgr

Filesystem driver registry and volume probing.

## Overview

The filesystem manager maintains a linked list of registered `TFilesystem` descriptors. Filesystem drivers (FAT32, FlatFS, ISO 9660, etc.) call `register_filesystem` during their `init` procedure to make themselves available. When the volume manager discovers a new partition, it calls `probe_volume` to determine which filesystem the partition contains.

`probe_volume` iterates all registered drivers and calls each one's `identifyCallback`. The first driver that returns true is assigned as the volume's filesystem. If no driver recognises the volume, `filesystem` remains nil.

## Dependencies

- `core.ds.lists`
- `memory.heap`
- `driver.storage.types`
- `core.strings`
- `debug.tracer`
- `core.util`, `arch.x86.util`

## Boot Registration

Registered with `boot.mgr` as `driver.storage.fs.mgr`, depending on `driver.storage.vol.mgr`.

## Variables

| Name | Type | Description |
|---|---|---|
| `filesystems` | `PLinkedListBase` | Linked list of registered `TFilesystem` records |

## Functions and Procedures

### init

```pascal
procedure init();
```

Allocates the filesystem linked list. Must be called before any filesystem driver registers itself.

### register_filesystem

```pascal
procedure register_filesystem(filesystem : PFilesystem);
```

Copies the `TFilesystem` descriptor into the linked list. The caller may pass a pointer to a static record; the list stores a value copy.

### get_filesystem_count

```pascal
function get_filesystem_count() : uint32;
```

Returns the number of registered filesystem drivers.

### get_filesystem

```pascal
function get_filesystem(index : uint32) : PFilesystem;
```

Returns the filesystem descriptor at `index`, or nil if out of range.

### find_filesystem_by_name

```pascal
function find_filesystem_by_name(name : pchar) : PFilesystem;
```

Searches for a filesystem by its `sName` field. Returns nil if not found.

### find_filesystem_by_id

```pascal
function find_filesystem_by_id(system_id : uint8) : PFilesystem;
```

Searches for a filesystem by its MBR partition type byte. Returns nil if not found.

### probe_volume

```pascal
procedure probe_volume(volume : PStorage_Volume);
```

Iterates all registered filesystems and calls each one's `identifyCallback(volume)`. Assigns `volume^.filesystem` to the first driver that returns true. If no driver matches, `filesystem` remains unchanged (typically nil).
