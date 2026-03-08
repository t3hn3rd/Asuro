# app.partcmd

Command-line tool for MBR partition table management.

## Overview

`app.partcmd` registers the `PART` shell command, which provides four subcommands for managing the MBR partition table of a storage device. It supports listing, adding, removing, and formatting partitions. Partition sizes can be specified with unit suffixes (B, KB, MB, GB). Auto-initialization of a missing MBR is performed transparently when adding the first partition.

## Dependencies

- `driver.storage.fs.mgr`
- `core.ds.lists`, `memory.heap`
- `driver.storage.vol.mbr`, `driver.storage.vol.mgr`
- `io.stdio`, `driver.storage.mgr`, `driver.storage.types`
- `core.strings`, `debug.tracer`

## Functions and Procedures

### init

```pascal
procedure init();
```

Registers the `PART` command with `io.stdio`.

### command_part (internal)

```pascal
procedure command_part(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
```

Main dispatcher routing to one of four subcommand procedures.

### cmd_list (internal)

Reads the MBR from the specified disk and prints the four partition slots showing system ID, LBA start, size, and boot flag. Warns if the boot marker is not `$AA55`.

### cmd_add (internal)

Adds a new partition to the first available slot. If no valid MBR exists the disk is auto-initialized. An optional size argument is parsed by `parsesize`; if omitted all remaining free sectors are used. The new partition receives system ID `0` (unformatted).

### cmd_rm (internal)

Clears a partition slot (0-3) on the specified disk, updating the on-disk MBR.

### cmd_format (internal)

Formats the volume corresponding to a partition slot using a named filesystem. Looks up the filesystem by name via `driver.storage.fs.mgr.find_filesystem_by_name`, creates a volume record if one does not already exist, calls the filesystem's `createCallback`, and re-probes the volume to confirm the new signature.

### parsesize (internal)

```pascal
function parsesize(s: pchar; sectorSize: uint32): uint32;
```

Converts a human-readable size string (e.g. `500MB`, `2GB`, `1024KB`, `4096B`, or plain integer treated as bytes) into a sector count. Returns `0` on invalid input.

## Notes

The MBR supports exactly four primary partition slots (slots 0-3). Logical/extended partitions are not supported. The `format` subcommand overwrites any existing filesystem on the target slot without a separate confirmation prompt.
