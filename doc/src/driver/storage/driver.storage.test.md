# driver.storage.test

Unit tests for the storage subsystem.

## Overview

This unit provides two categories of tests for the storage stack:

1. **Boot-time VFS tests** (`run_tests`): exercises path manipulation, virtual directory creation and duplication detection, directory listing, and `.`/`..` traversal. These tests require only the in-memory VFS and no actual disk I/O, so they run safely at kernel boot.

2. **Runtime disk tests** (`run_disk_tests`): destructive tests that wipe disk 0, create a 4 MB FAT32 partition, write a 512-byte file, read it back, and verify the data. These tests only run when explicitly invoked from the shell via the `DISKTEST` command.

Two shell commands are registered at `init` time:
- `STORTEST` — re-runs the VFS path tests and reports pass/fail counts.
- `DISKTEST` — runs the destructive disk I/O tests with a warning.

Output from `UnitTest` (boot-time) goes to `io.syslog` under the tag `STORTEST`. Output from shell commands goes to the process `stdout_buf`.

## Dependencies

- `core.ds.hashmap`
- `memory.heap`
- `driver.storage.vol.mbr`
- `io.stdio`
- `driver.storage.mgr`
- `driver.storage.types`
- `core.strings`
- `io.syslog`
- `debug.tracer`
- `core.util`, `arch.x86.util`
- `driver.storage.vfs`
- `driver.storage.vol.mgr`

## Boot Registration

Registered with `boot.mgr` as `driver.storage.test` at the `late` barrier.

## Functions and Procedures

### UnitTest

```pascal
procedure UnitTest;
```

Called by the kernel at boot. Runs `run_tests` against the syslog output channel and prints a summary of passed/failed assertions.

### init

```pascal
procedure init;
```

Registers the `STORTEST` and `DISKTEST` shell commands with `io.stdio`. Must be called during kernel initialisation.

## Notes

- `run_tests` exercises `makeAbsolutePathFrom`, `resolvePathFrom`, `changeDirectoryFrom`, `GetDirectoryListingFrom`, `newVirtualDirectory`, and `PathValid` including `.` and `..` traversal.
- `run_disk_tests` is destructive and will irreversibly wipe the partition table of disk 0. It is never called automatically.
- The `Assert` helper used in both procedures increments `passed` or `failed` counters and logs the test name on failure; passing tests produce no output to avoid noise.
