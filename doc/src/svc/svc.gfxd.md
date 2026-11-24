# svc.gfxd

The graphics daemon runs as a priority-5 process on i386 and x86-64. Its `init` registers a timer callback through `arch.platform.interrupts.registerTimer` and creates the process through `proc.mgr.create`.

## Render loop

When the shared monotonic clock is ready, the daemon polls at intervals of at least 1,000 microseconds. Otherwise it polls after eight timer ticks. Poll frequency and displayed frame rate can differ.

With the LVGL lock held, the process reaps orphaned windows, updates the desktop and debug overlay, and calls the LVGL handler. LVGL presents completed updates through its flush path. Unchanged polls avoid a full framebuffer copy. Holding the lock through presentation synchronizes the render path with resolution changes.

## Clock source

`core.clock.prepare` selects a supported VM reference clock or calibrates the timestamp counter against the RTC. Callers can query `ready`, read elapsed microseconds with `nowUS`, and obtain the source name or failure reason. The same clock supplies storage benchmark timing.
