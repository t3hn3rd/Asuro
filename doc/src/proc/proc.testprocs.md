# proc.testprocs

Two test processes for validating preemptive scheduling behaviour.

## Overview

`proc.testprocs` creates two minimal preemptive processes, `testproc1` and `testproc2`, that run indefinitely. Each process logs a short message to `io.syslog` once per second (approximately 1024 timer ticks at the 1024 Hz BDA tick rate), then yields to the scheduler and waits for the next interval.

The unit is included in the kernel build to demonstrate that the preemptive scheduler can context-switch between independent processes running at the same priority level.

## Dependencies

- `proc.types`
- `proc.mgr`
- `io.syslog`
- `arch.x86.bda`

## Functions and Procedures

### init

```pascal
procedure init;
```

Creates `testproc1` and `testproc2` via `proc.mgr.create` at priority 1, then logs a confirmation via `io.syslog`. Both processes start in `psReady` state and will be scheduled on the next timer interrupt.

### program1 / program2 (internal)

```pascal
procedure program1(ctx: PProcessContext);
procedure program2(ctx: PProcessContext);
```

Entry points for the two test processes. Each loops until `ctx^.PendingMsg = smTerminate`, logging a message and sleeping approximately one second via `sleep_ticks(1024)`.

### sleep_ticks (internal)

```pascal
procedure sleep_ticks(ticks: uint16);
```

Busy-wait sleep using `proc_yield` and the BDA tick counter. Yields on each iteration and measures elapsed time as `now - start`, with correct handling of `uint16` wrap-around at 65535.

## Notes

These processes are not connected to any shell command or UI; they run silently in the background and can be observed via the `PS` command or the serial log. They respond to `smTerminate` by exiting the main loop and allowing the process to finish naturally.
