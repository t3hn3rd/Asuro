# svc.gfxd

Graphics render daemon that continuously drives the LVGL, desktop, and framebuffer flush pipeline.

## Overview

`svc.gfxd` spawns a dedicated `gfxd` process and registers a lightweight timer hook to keep the render pipeline active. The render process runs indefinitely, executing the full graphics update sequence on every frame interval.

The daemon exists for two reasons. First, it decouples rendering from the scheduler's idle loop, ensuring that LVGL timers, desktop compositing, and the framebuffer flush all run as a normal scheduled process with interrupts enabled. Second, under NEM/Hyper-V virtualization backends, the render loop's workload (which includes a 7.3 MB SSE framebuffer copy in `driver.video.Flush`) keeps the vCPU active and prevents the hypervisor from descheduling it in ways that would starve the PIT of timer interrupts.

A timer hook (`tick`) increments `CURRENT_TICK` on every timer interrupt. The render loop compares `CURRENT_TICK` to `LAST_UPDATE` and only executes the render pipeline when at least `TICKS_PER_FRAME` ticks have elapsed, providing a target frame rate without busy-waiting.

## Dependencies

- `driver.video.desktop`
- `driver.video.lvgl`
- `driver.video`
- `driver.video.windows`
- `app.uidebug`
- `proc.mgr`
- `proc.types`
- `io.syslog`
- `arch.x86.isr.tmr0`

## Constants

### TICKS_PER_FRAME
`32` — Minimum timer ticks between render pipeline executions. Adjust to balance refresh rate against CPU usage.

## Functions and Procedures

### init

```pascal
procedure init;
```

Registers `tick` as a timer-0 ISR hook via `arch.x86.isr.tmr0.hook`, then creates the `gfxd` process at priority 5 with `render_loop` as its entry point.

### render_loop (internal)

```pascal
procedure render_loop(ctx: PProcessContext);
```

Process entry point. Loops forever, checking whether `TICKS_PER_FRAME` ticks have elapsed since the last update (with wrap-around handling). When a frame is due, calls:

1. `driver.video.windows.reapOrphanedWindows` — removes closed window objects.
2. `driver.video.desktop.update` — composites the desktop.
3. `app.uidebug.update` — updates the FPS/diagnostic overlay if enabled.
4. `lvgl_handler` — processes LVGL events and redraws dirty widgets.
5. `driver.video.Flush` — copies the back buffer to the front buffer.

### tick (internal)

```pascal
procedure tick;
```

ISR hook registered with `arch.x86.isr.tmr0`. Increments `CURRENT_TICK` on every timer interrupt. Called from interrupt context with no locking; the 32-bit increment is effectively atomic on x86.

## Notes

The `gfxd` process runs at priority 5, giving it a quantum of 25 ticks (`5 * BASE_QUANTUM`). This is higher than the default priority-1 command processes, ensuring the display remains responsive even under moderate process load.

The tick counter variable `CURRENT_TICK` is shared between the ISR hook and the render loop without explicit synchronization. On 32-bit x86 this is safe because aligned 32-bit reads and writes are atomic; the worst outcome of a race is a one-tick difference in the frame interval.
