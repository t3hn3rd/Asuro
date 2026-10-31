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


## Raw read benchmark

`STORBENCH` is implemented and registered by `driver.storage.bench`. It performs
read-only raw-device I/O; it does not invoke the destructive `DISKTEST` path.

```text
STORBENCH [disk] [MiB]
STORBENCH list
STORBENCH run [disk] [MiB] [KiB/request] [depth] [seq|random] [start_lba]
STORBENCH compare [disk] [MiB]
STORBENCH help
```

Manual (`run`) defaults are disk 0, 128 MiB, 1024 KiB/request, sequential reads, and a depth of
`min(4, hardware depth)` (at least one). Examples:

```text
STORBENCH 0 128 64 4
STORBENCH 0 128 4 16 random
STORBENCH 0 256 1024 1 seq 2048
STORBENCH compare 0 128
```

The comparison runs sequential reads at 4, 64, and 1024 KiB/request, each at depths
1, 4, 16, and 32. The MiB argument applies to each of the twelve cases. Queue depth
may exceed hardware depth to expose software queuing and request merging.

Limits are 1..16384 MiB, 1..1024 KiB/request, and depth 1..32. Request size must be
an exact number of device sectors. Buffers are allocated once per case, with a
separate slice for every outstanding request and a maximum total size of 32 MiB.
The transfer range is clamped to the device. Without an explicit LBA, reads start
at sector 2048 when the full requested range fits there; otherwise they start at
zero. Random mode uses a fixed xorshift seed and samples that range with replacement,
so total bytes read are bounded but unique coverage is not guaranteed.

Reports include successful bytes, elapsed microseconds, MiB/s, IOPS, accepted and
completed request counts, peak outstanding requests, average/p95/max completion
latency, and per-run storage-counter deltas. Latencies are measured from submission
to callback. The p95 is an upper bound from logarithmic microsecond buckets, not an exact
microsecond percentile. Runs shorter than 10 ms are excluded from suite speed comparisons.
No console output occurs inside the measured loop. Any failure stops new work;
already accepted DMA is drained before buffers are freed, and failed requests
contribute no bytes or successful IOPS.

Timing prefers the Hyper-V-compatible VM reference counter (100 ns ticks), detected
through its Hv#1 interface and reference-counter privilege. It needs no calibration.
Other platforms use an invariant TSC calibrated against two complete RTC seconds,
with up to three attempts to tolerate transient RTC updates or scheduling delays.
Calibration requires agreement within 1%; failures include the specific reason.
Unlike delivered timer interrupts, this clock advances while interrupts are masked.
Queue submission restores interrupts between requests. Filesystem caches are
bypassed, but drive and virtual-machine/host caches may still affect results.
Virtual or sparse disks can report throughput above physical-media speed.
Device counter deltas may include concurrent I/O from other processes;
benchmark-owned byte, request, and latency counters do not.

`driver.storage.bench.UnitTest` runs memory-only parser, arithmetic, range,
queue-depth, completion-order, and error-accounting tests at boot. It never reads
or writes a real disk. The clock tests also verify that an advertised VM reference
counter advances with interrupts masked; they never calibrate the RTC at boot.


### Automatic suite and table output

`STORBENCH` without arguments, or `STORBENCH auto [disk] [MiB]`, runs six
read-only profiles. Auto defaults to disk 0 and **32 MiB per profile** (up to
192 MiB total before device-size clamping). One or two numeric arguments select the auto suite: `STORBENCH 2 512` tests
disk 2 with 512 MiB per profile. `STORBENCH list` lists disk indices, capacities,
controllers, sector sizes, and hardware queue depths. Three or more numeric
arguments retain the legacy manual syntax; `run` selects manual mode explicitly.

| Profile | Request size | Queue depth |
| --- | --- | --- |
| Seq large | 1024 KiB | 1 |
| Seq queued | 1024 KiB | queued |
| Seq medium | 64 KiB | queued |
| Random small | 4 KiB | 1 |
| Random queued | 4 KiB | queued |
| Random medium | 64 KiB | queued |

Queued depth is the device hardware depth clamped to 4..16, allowing software
queue testing even on serial devices. A request smaller than a device sector is
increased to one sector. Each profile samples the same byte-span size, with the
existing fixed random seed and range clamping rules.

Auto and compare modes print an aligned ASCII table with request KiB, queue
depth, MiB/s, IOPS, average latency, p95 latency upper bound, and status. Rows are
printed outside the measured loop. Successful runs shorter than 10 ms show `-` metrics and
`SHORT`, and are excluded from best-result and queue-gain summaries. Errors show
`FAILED`, stop the suite after accepted DMA has drained, and leave remaining
profiles unrun. The summary includes successful profiles, bytes actually read,
measured time, best sequential throughput, peak random IOPS, and (in auto mode)
queued/QD1 throughput ratios. These ratios describe the measured cases, including
any controller-cache effects; they are not a hardware rating.

```text
STORBENCH
STORBENCH list
STORBENCH 2 512
STORBENCH auto 0 64
STORBENCH compare 0 32
```

Profiles reuse the same raw device range. Host/drive caches are not flushed, so
later profiles may read warm data. These results are observed raw read throughput,
not a claim of uncached physical-media performance.
