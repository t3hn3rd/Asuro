# app.diskcmd

Command-line tool for inspecting and wiping physical storage devices.

## Overview

`app.diskcmd` registers the `DISK` shell command, which provides three subcommands for working with raw storage devices registered with the storage manager. It queries `driver.storage.mgr` for device information and `driver.storage.vol.mgr` for free-space accounting.

## Dependencies

- `core.ds.lists`, `memory.heap`
- `driver.storage.mgr`, `driver.storage.types`
- `core.strings`, `io.stdio`, `debug.tracer`
- `core.util`, `arch.x86.util`
- `driver.storage.vol.mgr`

## Functions and Procedures

### init

```pascal
procedure init();
```

Registers the `DISK` command with `io.stdio`.

### command_disk (internal)

```pascal
procedure command_disk(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
```

Main command dispatcher. Reads the first parameter and routes to `cmd_list`, `cmd_info`, or `cmd_wipe`.

### cmd_list (internal)

Prints a table of all registered storage devices showing index, controller type, writable status, total size, and partition count.

### cmd_info (internal)

Prints detailed information for a single device by index: device ID, controller, controller ID, sector size, total sectors, total size, start sector, free space, and partition count.

### cmd_wipe (internal)

Zeros the entire contents of a writable device. Removes all volumes from the device first via `driver.storage.vol.mgr.init_disk`, then writes zeroed 64-sector batches across all sectors. Requires the device to have write support.

## Notes

Size values are printed in human-readable form (B, KB, MB, or GB). The `wipe` subcommand is destructive and non-reversible; no confirmation prompt is shown. The device must have a `dispatchWrite` function pointer set to be eligible for wiping.
