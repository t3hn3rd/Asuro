# asuro

Kernel main entry point implementing the full Asuro boot sequence.

## Overview

`asuro` contains `kmain`, the first Pascal-level function called by the bootloader after the assembly stub hands off control. It performs the complete linear boot sequence: hardware initialization, memory management setup, driver loading, filesystem mounting, process manager initialization, desktop launch, and final transition into the timer-driven idle loop.

`kmain` accepts the Multiboot2 info pointer and magic value directly from the bootloader. It validates the magic number immediately; a mismatch triggers a kernel panic before any further initialization proceeds.

The boot sequence is instrumented with `boot.splash` progress updates from 5% through 100%, giving visual feedback during the lengthy driver and unit-test phases. All logging is routed through `io.syslog` from the very first line after serial initialization.

After all subsystems are initialized the function calls `yield`, which enables interrupts and halts the CPU in a loop. All subsequent work is driven by the timer ISR and the preemptive scheduler.

## Dependencies

- `arch.x86.gdt`, `arch.x86.idt`, `arch.x86.irq`, `arch.x86.isr`, `arch.x86.isr.mgr`, `arch.x86.isr.tmr0`
- `arch.x86.fault`, `arch.x86.cpu`, `arch.x86.memory.physical`, `arch.x86.memory.virtual`
- `arch.x86.v86`, `arch.x86.proc.sched`, `arch.x86.panic`, `arch.x86.bda`
- `memory.heap`, `io.stdio`, `io.syslog`, `debug.tracer`
- `driver.io.serial`, `driver.timer.rtc`
- `driver.video`, `driver.video.gpu`, `driver.video.vesa`, `driver.video.doublebuffer`, `driver.video.bga`
- `driver.video.lvgl`, `driver.video.desktop`, `driver.video.windows`
- `driver.hid.ps2.keyboard`, `driver.hid.ps2.mouse`
- `driver.bus.pci`, `driver.bus.usb` (and sub-units: ehci, ohci, uhci, xhci, hub, core, types)
- `driver.hid.usb.keyboard`, `driver.hid.usb.mouse`
- `driver.storage.mgr`, `driver.storage.vol.mgr`, `driver.storage.fs.mgr`
- `driver.storage.fs.fat32`, `driver.storage.fs.flatfs`, `driver.storage.fs.iso9660`
- `driver.storage.ctl.ahci`, `driver.storage.ctl.usb`, `driver.storage.vfs`, `driver.storage.test`
- `driver.net`, `driver.net.dev.e1000`
- `driver.mgr`, `driver.exp.testdriver`
- `proc.mgr`, `proc.testprocs`
- `app.mgr`, `app.vterminal`, `app.partcmd`, `app.volcmd`, `app.uidebug`
- `boot.splash`
- `core.panic`, `core.rand`, `core.strings`, `core.util`
- `core.enc.base64`, `core.enc.md5`, `core.enc.fnv1a`, `core.enc.djb2`
- `core.ds.*` (fifo, cfifo, cfifols, circ, lifo, lists, hashmap, bloom, minh, maxh, prio)
- `core.gfx.color`, `core.gfx.fonts`
- `svc.gfxd`, `svc.usbd`
- `wasm`, `wasm.vm.io`, `wasm.test`, `wasm.test.framework`

## Functions and Procedures

### kmain

```pascal
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall;
```

Exported as `kmain` (public alias). Executes the full boot sequence in the order listed below.

### terminal_command_bsod (internal)

```pascal
procedure terminal_command_bsod(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
```

Registered as the `BSOD` shell command. Requires exactly two parameters (error title and info string); passes them to `core.panic.panic`. Writes a usage error to stderr if the parameter count is wrong.

### yield (internal)

```pascal
procedure yield;
```

Enables interrupts with `STI` then enters an infinite `HLT` loop. Called as the last statement in `kmain` to idle the CPU; all subsequent execution is driven by timer and device interrupts.

## Boot Sequence

The steps performed by `kmain` in order:

1. `System.init` — FPC RTL initialization.
2. `driver.io.serial.init` — serial port for early logging.
3. `io.syslog.init` — kernel log system.
4. Multiboot magic validation — panics if not `MULTIBOOT_BOOTLOADER_MAGIC`.
5. `arch.x86.gdt.init` — GDT load; validates CS = `$08` or panics.
6. `arch.x86.idt.init`, `arch.x86.irq.init`, `arch.x86.isr.mgr.init`, `arch.x86.fault.init`, `driver.timer.rtc.init` — interrupt infrastructure.
7. `arch.x86.memory.physical.init`, `arch.x86.memory.virtual.init`, `memory.heap.init` — memory management.
8. `arch.x86.v86.init` — Virtual 8086 monitor.
9. `io.stdio.init` — command registry; registers `BSOD` command.
10. `arch.x86.cpu.init` — CPUID detection.
11. `debug.tracer.init` — call trace ring buffer.
12. `driver.mgr.init`, GPU/video/VESA/double-buffer/BGA initialization — display subsystem.
13. `lvgl_init` — LVGL initialized with front buffer dimensions.
14. `arch.x86.panic.init` — LVGL-based BSOD panic screen.
15. `boot.splash.init` — boot splash screen.
16. `driver.storage.vfs.init`, `driver.storage.test.init` — VFS.
17. WASURO VM initialization (`wasm.vm.io`, `wasm.wasm_init`).
18. Storage manager, volume manager, filesystem manager initialization.
19. `STI` + timer hook (`arch.x86.isr.tmr0.hook`) — interrupts enabled.
20. Filesystem drivers: FAT32, FlatFS, ISO 9660.
21. `proc.mgr.init` — process manager (first call, before device drivers).
22. Device drivers: PS/2 keyboard, PS/2 mouse, test driver, e1000 NIC, AHCI.
23. Bus drivers: USB, PCI.
24. `driver.storage.vfs.auto_mount_volumes` — auto-mount discovered volumes.
25. `driver.net.init` — network stack.
26. `app.mgr.init` — application and command registration.
27. `proc.mgr.init` — second call (re-initializes process table for post-driver state).
28. `core.rand.srand` — RNG seeded from RTC date/time.
29. Unit test suite — runs tests for strings, USB layers, data structures, WASM, and VFS.
30. `boot.splash.teardown`, `driver.video.desktop.init` — desktop environment launched.
31. `app.vterminal.init` — visual terminal registered with desktop.
32. `svc.gfxd.init`, `svc.usbd.init` — graphics and USB daemon processes spawned.
33. `arch.x86.proc.sched.init` — preemptive context switching enabled (replaces ISR_32).
34. `yield` — CPU enters idle HLT loop.

## Notes

`proc.mgr.init` is called twice: once before device drivers (so that `submit_io` has a valid `CurrentProcess` pointer) and again after `app.mgr.init` to reset the process table to a clean post-initialization state.

The `debug.tracer.freeze` call at the top of `kmain` disables tracing before the call stack is established; `debug.tracer.init` re-enables it later with the initial `'kmain'` trace entry.

The WASURO I/O write-char hook is pointed at `io.syslog.logchar` so WASM VM diagnostic output is routed through the kernel log before the process manager is up.
