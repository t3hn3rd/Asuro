# driver.storage.fs.flatfs

FlatFS — a simple flat filesystem driver for Asuro.

## Overview

FlatFS is a minimal, flat-layout filesystem designed for early Asuro development. It does not support nested directory trees in the traditional sense; all entries (files and directories) are stored as path-string records in a single flat file table starting at sector 1 of the volume. Directory hierarchy is implied by the path stored in each entry's name field.

The on-disk layout is:
- **Sector 0**: `TDisk_Info` header (magic `$0B00B1E5`, version, sector count, file count)
- **Sectors 1..N**: File entry table of up to 1000 `TFile_Entry` records
- **Beyond the table**: File data regions, allocated by a first-fit scan

FlatFS registers itself with `driver.storage.fs.mgr` during `init`. Volume detection reads sector 2 (the FlatFS format historically placed the header there), checks the magic signature, and registers the volume if found. The `identifyCallback` reads sector 0 of a given volume and checks the same magic.

## Dependencies

- `driver.storage.fs.mgr`
- `core.ds.lists`
- `memory.heap`
- `io.stdio`
- `driver.storage.mgr`
- `driver.storage.types`
- `core.strings`
- `io.syslog`
- `debug.tracer`
- `core.util`, `arch.x86.util`
- `driver.storage.vol.mgr`

## Boot Registration

Registered with `boot.mgr` as `driver.storage.fs.flatfs`, depending on `driver.storage.fs.mgr`.

## Types

### TDisk_Info / PDisk_Info

On-disk volume header stored in sector 0.

| Field | Description |
|---|---|
| `jmp2boot` | 24-bit boot jump stub (unused) |
| `OEMName` | 8-character OEM identifier (`'ASURO'`) |
| `version` | Format version (currently 1) |
| `sectorCount` | Total sector count of the volume |
| `fileCount` | Maximum number of file entries (default 1000) |
| `signature` | Magic value `$0B00B1E5` |

### TFile_Entry / PFile_Entry

One entry in the flat file table.

| Field | Description |
|---|---|
| `attribues` | `$00` = free, `$01` = file, `$10` = directory |
| `name` | Full path string, up to 54 characters |
| `size` | Size in sectors |
| `start` | Starting sector of the file's data region |

## Functions and Procedures

### init

```pascal
procedure init();
```

Populates the `filesystem` descriptor with callback pointers and registers it with the filesystem manager. Sets `system_id` to `$02`.

### create_volume

```pascal
procedure create_volume(volume : PStorage_Volume; sectors : uint32; start : uint32; config : puint32);
```

Formats the volume: writes the `TDisk_Info` header, initialises the file entry table with three default directory entries (`/system`, `/programs`, `/user`), and creates several test files under `/logs`.

### detect_volumes

```pascal
procedure detect_volumes(disk : PStorage_Device);
```

Reads sector 2 from the raw device and checks for the FlatFS magic. If found, allocates a `TStorage_Volume` and registers it via `driver.storage.vol.mgr.register_volume`.

### read_directory

```pascal
function read_directory(volume : PStorage_Volume; directory : pchar; status : PuInt32) : PLinkedListBase;
```

Scans the file entry table and returns a string linked list of all entry names that are direct children of `directory` (i.e., names prefixed with `directory` and containing no further `/`).

### write_directory

```pascal
procedure write_directory(volume : PStorage_Volume; directory : pchar; status : PuInt32);
```

Finds the first free entry in the file table and writes a directory entry with the given path name.

### write_file

```pascal
procedure write_file(volume : PStorage_Volume; fileName : pchar; data : PuInt32; size : uint32; status : PuInt32);
```

Writes file data to disk. If the file already exists and the new size is larger, finds new free space. Creates a new entry if the file does not exist.

### read_file

```pascal
procedure read_file(volume : PStorage_Volume; fileName : pchar; data : PuInt32; status : PuInt32);
```

Locates the file in the entry table and reads its data sectors into a newly allocated buffer assigned to `data`.

## Notes

- FlatFS was designed as an early prototype. It has known limitations: no true directory nesting, a fixed 1000-entry table, a hardcoded default sector size of 512 bytes, and no cluster chain mechanism.
- The `readDirCallback` registered with the filesystem manager is `readDirectoryEntries`, a later rewrite of `read_directory` that returns a `PLinkedListBase` of `TDirectory_Entry` records compatible with the VFS layer.
- `write_file` and `write_directory` are not currently wired to the `TFilesystem` callback table; the unit exposes them as standalone procedures for internal use during volume creation.
- The free space search uses a quicksort on file entries by start sector followed by a gap scan; the implementation has known bugs with edge cases at the end of the entry list.
