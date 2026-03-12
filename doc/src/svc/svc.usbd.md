# svc.usbd

USB hotplug daemon that polls for USB port changes once per second.

## Overview

`svc.usbd` spawns a single `usbd` preemptive process that calls `driver.bus.usb.core.usb_check_hotplug` on each iteration and then sleeps for approximately one second using `proc.mgr.proc_sleep_ms`. This provides ongoing detection of USB device connection and disconnection events without dedicating an interrupt to the task.

The daemon runs at priority 2, giving it a quantum of 10 ticks, which is sufficient for the low-frequency polling workload.

## Dependencies

- `driver.bus.usb.core`
- `proc.mgr`
- `proc.types`
- `io.syslog`

## Boot Registration

Registered with `boot.mgr` as `svc.usbd` at the `late` barrier.

## Functions and Procedures

### init

```pascal
procedure init;
```

Creates the `usbd` process at priority 2 with `usbd_loop` as its entry point and logs a confirmation via `io.syslog`.

### usbd_loop (internal)

```pascal
procedure usbd_loop(ctx: PProcessContext);
```

Process entry point. Loops indefinitely, calling `driver.bus.usb.core.usb_check_hotplug` and then sleeping for 1000 ms via `proc.mgr.proc_sleep_ms(1000)`.

## Notes

`proc_sleep_ms(1000)` translates to approximately 1024 BDA ticks at the 1024 Hz tick rate, so the actual polling interval is close to but not exactly one second.

The loop does not check for `smTerminate`; the `usbd` process can be stopped by calling `proc.mgr.kill` with its PID.
