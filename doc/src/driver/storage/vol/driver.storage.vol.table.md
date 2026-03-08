# driver.storage.vol.table

MBR partition table parsing and management stub.

## Overview

This unit is an early placeholder for partition table management. It declares a `TpartitionTable` record and three procedure stubs but contains no functional implementation. The functionality it was intended to provide has been absorbed into `driver.storage.vol.mgr` and `driver.storage.vol.mbr`.

The unit depends on `storagemanagement` (legacy module) and `driver.timer.rtc`, neither of which is present in current builds.

## Dependencies

- `io.syslog`
- `core.ds.lists`
- `memory.heap`
- `driver.timer.rtc`
- `storagemanagement` (legacy)
- `core.strings`
- `io.stdio`
- `debug.tracer`
- `core.util`, `arch.x86.util`

## Variables

| Name | Value | Description |
|---|---|---|
| `location` | `$1BE` | MBR offset of the partition table (446 decimal) |

## Types

### TpartitionTable / PpartitionTable

Empty record — no fields defined. Placeholder for a future partition table abstraction.

## Functions and Procedures

### create_new

```pascal
procedure create_new(device : PStorage_Device);
```

Stub — empty implementation.

### get_table

```pascal
function get_table() : PpartitionTable;
```

Stub — declared but not implemented (missing `begin`/`end` body in source).

### add_volume

```pascal
procedure add_volume(volume : TStorage_Volume);
```

Stub — declared but not implemented.

## Notes

- This unit is not used in current Asuro builds. It should be considered deprecated.
- The source file contains a compilation error: `get_table` and `add_volume` are listed in the `implementation` section without procedure bodies.
