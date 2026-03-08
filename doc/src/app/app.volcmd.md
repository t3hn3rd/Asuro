# app.volcmd

Command-line tool for inspecting registered storage volumes.

## Overview

`app.volcmd` registers the `VOL` shell command, which provides two subcommands for viewing the logical volumes known to `driver.storage.vol.mgr`. It shows the relationship between volumes and their underlying physical devices, filesystem assignments, and space usage.

## Dependencies

- `core.ds.lists`, `memory.heap`
- `driver.storage.mgr`, `driver.storage.types`
- `core.strings`, `io.stdio`, `debug.tracer`
- `driver.storage.vol.mgr`

## Functions and Procedures

### init

```pascal
procedure init();
```

Registers the `VOL` command with `io.stdio`.

### command_vol (internal)

```pascal
procedure command_vol(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
```

Main dispatcher routing to `cmd_list` or `cmd_info`.

### cmd_list (internal)

Prints a summary table of all registered volumes: index, device ID and controller type, total size, and assigned filesystem name (or `none`).

### cmd_info (internal)

Prints detailed information for a single volume by index: sector start, sector count, sector size, total size, free size, boot drive flag, filesystem name, and parent device ID and controller type.

## Notes

Volume indices are assigned by the volume manager at registration time and may not correspond to partition slot numbers. Free space reported in `cmd_info` reflects the `freeSectors` field of the volume record, which must be updated by the filesystem driver to remain accurate.
