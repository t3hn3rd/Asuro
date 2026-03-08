# Asuro Namespace Refactoring Plan

## Overview

Refactor all source files under `src/` to use dotted namespace conventions (without the `asuro.` prefix — it's implicit). After refactoring, the only file at the `src/` root will be `asuro.pas` (the kernel entry point, currently `kernel.pas`). All other units move into namespaced subdirectories.

### Goals

- Clear, hierarchical namespacing for every unit
- Separation of x86-specific code under `arch/x86/` to support future architectures
- Drivers remain under `driver/` with full namespacing
- Services (timer-driven kernel processes) separated from user apps
- Structure supports future additions (e.g. `src/wasm/wasm.*`)

### Conventions

| Rule | Example |
|------|---------|
| All filenames are **lowercase** | `driver.bus.pci.pas` |
| Unit name matches filename (minus `.pas`) | `unit driver.bus.pci;` |
| Dots in the name reflect the folder hierarchy | `a.b.c.pas` lives in `src/a/b/` |
| If a unit has sub-units, it lives one level up | `driver.bus.usb.pas` in `driver/bus/`, sub-units in `driver/bus/usb/` |
| `system.pas` keeps its name (FPC compiler requirement) | `src/arch/x86/system.pas` |
| No `asuro.` prefix — the repo context is implicit | `arch.x86.gdt` not `asuro.arch.x86.gdt` |

---

## New Directory Structure

```
src/
├── asuro.pas                              # Kernel entry point (was kernel.pas)
│
├── arch/
│   └── x86/
│       ├── system.pas                     # FPC system unit (unchanged name, x86 asm)
│       ├── arch.x86.gdt.pas
│       ├── arch.x86.idt.pas
│       ├── arch.x86.irq.pas
│       ├── arch.x86.isr.pas
│       ├── arch.x86.cpu.pas
│       ├── arch.x86.faults.pas
│       ├── arch.x86.util.pas              # x86 I/O: outb/inb, CLI/STI, TSC, BSOD
│       ├── arch.x86.multiboot.pas
│       ├── arch.x86.bda.pas               # BIOS Data Area
│       ├── arch.x86.v86.pas               # Virtual 8086 monitor
│       │
│       ├── boot/
│       │   └── stub.asm                   # Multiboot boot stub (NASM)
│       │
│       ├── fault/
│       │   ├── arch.x86.fault.ace.pas
│       │   ├── arch.x86.fault.bpe.pas
│       │   ├── arch.x86.fault.btsse.pas
│       │   ├── arch.x86.fault.cfe.pas
│       │   ├── arch.x86.fault.csoe.pas
│       │   ├── arch.x86.fault.dbge.pas
│       │   ├── arch.x86.fault.dbz.pas
│       │   ├── arch.x86.fault.dfe.pas
│       │   ├── arch.x86.fault.gpf.pas
│       │   ├── arch.x86.fault.idoe.pas
│       │   ├── arch.x86.fault.iope.pas
│       │   ├── arch.x86.fault.mce.pas
│       │   ├── arch.x86.fault.nce.pas
│       │   ├── arch.x86.fault.nmie.pas
│       │   ├── arch.x86.fault.oobe.pas
│       │   ├── arch.x86.fault.pf.pas
│       │   ├── arch.x86.fault.sfe.pas
│       │   ├── arch.x86.fault.snpe.pas
│       │   └── arch.x86.fault.uie.pas
│       │
│       ├── isr/
│       │   ├── arch.x86.isr.types.pas
│       │   ├── arch.x86.isr.mgr.pas
│       │   ├── arch.x86.isr.ioapic.pas
│       │   ├── arch.x86.isr.tmr0.pas
│       │   ├── arch.x86.isr.tmr1.pas
│       │   └── arch.x86.isr.ps2keyboard.pas
│       │
│       ├── proc/
│       │   ├── arch.x86.proc.sched.pas
│       │   └── arch.x86.proc.loader.pas
│       │
│       └── memory/
│           ├── arch.x86.memory.physical.pas
│           └── arch.x86.memory.virtual.pas
│
├── boot/
│   ├── boot.splash.pas                   # Boot splash screen
│   └── splash_tga.asm                    # Splash TGA data (incbin)
│
├── core/
│   ├── core.version.pas                  # Was include/asuro.pas (build metadata)
│   ├── core.util.pas                     # Portable helpers (IntToStr, min/max, etc.)
│   ├── core.strings.pas
│   ├── core.rand.pas
│   ├── core.types.pas
│   │
│   ├── ds/
│   │   ├── core.ds.types.pas             # Was dstypes.pas
│   │   ├── core.ds.lists.pas
│   │   ├── core.ds.hashmap.pas
│   │   ├── core.ds.fifo.pas
│   │   ├── core.ds.cfifo.pas
│   │   ├── core.ds.cfifols.pas
│   │   ├── core.ds.lifo.pas
│   │   ├── core.ds.circ.pas
│   │   ├── core.ds.bheap.pas
│   │   ├── core.ds.minh.pas
│   │   ├── core.ds.maxh.pas
│   │   └── core.ds.prio.pas
│   │
│   ├── enc/
│   │   ├── core.enc.md5.pas
│   │   ├── core.enc.sha1.pas
│   │   ├── core.enc.base64.pas
│   │   └── core.enc.crc.pas
│   │
│   ├── fmt/
│   │   └── core.fmt.targa.pas
│   │
│   └── gfx/
│       ├── core.gfx.color.pas
│       ├── core.gfx.fonts.pas
│       └── core.gfx.texture.pas
│
├── io/
│   ├── io.stdio.pas
│   └── io.syslog.pas
│
├── debug/
│   └── debug.tracer.pas
│
├── memory/
│   └── memory.heap.pas                   # Was lmemorymanager.pas
│
├── proc/
│   ├── proc.mgr.pas                      # Was processmanager.pas
│   ├── proc.types.pas                    # Was proctypes.pas
│   └── proc.testprocs.pas               # Was testprocs.pas
│
├── svc/
│   ├── svc.gfxd.pas                     # Timer-driven display refresh daemon
│   └── svc.usbd.pas                     # Timer-driven USB hotplug daemon
│
├── driver/
│   ├── driver.mgr.pas                    # Was drivermanagement.pas
│   ├── driver.types.pas                  # Was driver/include/drivertypes.pas
│   ├── driver.net.pas                    # Was driver/net/l1/net.pas
│   ├── driver.video.pas                  # Was driver/video/video.pas
│   │
│   ├── bus/
│   │   ├── driver.bus.pci.pas
│   │   ├── driver.bus.usb.pas            # Was driver/bus/usb/USB.pas
│   │   └── usb/
│   │       ├── driver.bus.usb.types.pas
│   │       ├── driver.bus.usb.core.pas
│   │       ├── driver.bus.usb.hub.pas
│   │       ├── driver.bus.usb.uhci.pas
│   │       ├── driver.bus.usb.ohci.pas
│   │       ├── driver.bus.usb.ehci.pas
│   │       └── driver.bus.usb.xhci.pas
│   │
│   ├── hid/
│   │   ├── driver.hid.keyboard.pas
│   │   ├── driver.hid.mouse.pas
│   │   ├── ps2/
│   │   │   ├── driver.hid.ps2.keyboard.pas
│   │   │   └── driver.hid.ps2.mouse.pas
│   │   └── usb/
│   │       ├── driver.hid.usb.keyboard.pas
│   │       └── driver.hid.usb.mouse.pas
│   │
│   ├── interface/
│   │   └── driver.interface.serial.pas
│   │
│   ├── timer/
│   │   └── driver.timer.rtc.pas
│   │
│   ├── storage/
│   │   ├── driver.storage.mgr.pas        # Was storagemanager.pas
│   │   ├── driver.storage.types.pas      # Was storagetypes.pas
│   │   ├── driver.storage.test.pas       # Was storagetest.pas
│   │   ├── driver.storage.vfs.pas
│   │   ├── driver.storage.fdtable.pas
│   │   ├── driver.storage.filedispatch.pas
│   │   ├── driver.storage.iobuffer.pas
│   │   ├── driver.storage.iorequest.pas
│   │   │
│   │   ├── con/
│   │   │   ├── driver.storage.ctl.usb.pas     # Was usb_storage.pas
│   │   │   ├── driver.storage.ctl.ram.pas     # Was ramdrive.pas
│   │   │   │
│   │   │   ├── ahci/
│   │   │   │   ├── driver.storage.ctl.ahci.pas
│   │   │   │   └── driver.storage.ctl.ahci.types.pas
│   │   │   │
│   │   │   └── ide/
│   │   │       ├── driver.storage.ctl.ide.pas
│   │   │       ├── driver.storage.ctl.ide.types.pas
│   │   │       ├── driver.storage.ctl.ide.ata.pas
│   │   │       └── driver.storage.ctl.ide.atapi.pas
│   │   │
│   │   ├── fs/
│   │   │   ├── driver.storage.fs.mgr.pas
│   │   │   ├── driver.storage.fs.fat32.pas
│   │   │   ├── driver.storage.fs.asfs.pas
│   │   │   ├── driver.storage.fs.flatfs.pas
│   │   │   └── driver.storage.fs.iso9660.pas
│   │   │
│   │   └── vol/
│   │       ├── driver.storage.vol.mgr.pas     # Was volumemanager.pas
│   │       ├── driver.storage.vol.table.pas
│   │       ├── driver.storage.vol.mbr.pas
│   │       └── driver.storage.vol.gpt.pas
│   │
│   ├── net/
│   │   ├── driver.net.types.pas
│   │   ├── driver.net.util.pas
│   │   ├── driver.net.eth2.pas
│   │   ├── driver.net.arp.pas
│   │   ├── driver.net.ipv4.pas
│   │   ├── driver.net.icmp.pas
│   │   ├── driver.net.tcp.pas
│   │   ├── driver.net.udp.pas
│   │   └── driver.net.dhcp.pas
│   │
│   ├── netdev/
│   │   └── driver.netdev.e1000.pas
│   │
│   ├── video/
│   │   ├── driver.video.types.pas
│   │   ├── driver.video.gpu.pas
│   │   ├── driver.video.vesa.pas
│   │   ├── driver.video.vesa8.pas
│   │   ├── driver.video.vesa16.pas
│   │   ├── driver.video.vesa24.pas
│   │   ├── driver.video.vesa32.pas
│   │   ├── driver.video.doublebuffer.pas
│   │   ├── driver.video.bga.pas
│   │   ├── driver.video.lvgl.pas
│   │   ├── driver.video.windows.pas
│   │   └── driver.video.desktop.pas
│   │
│   └── exp/
│       └── driver.exp.testdriver.pas
│
├── app/
│   ├── app.mgr.pas                       # Was progmanager.pas
│   ├── app.vterminal.pas
│   ├── app.base64.pas                    # Was base64_prog.pas
│   ├── app.md5sum.pas
│   ├── app.dhclient.pas
│   ├── app.vbeinfo.pas
│   ├── app.diskcmd.pas
│   ├── app.diskutil.pas
│   ├── app.edit.pas
│   ├── app.filepicker.pas
│   ├── app.inio.pas
│   ├── app.meminfo.pas
│   ├── app.notepad.pas
│   ├── app.partcmd.pas
│   ├── app.ping.pas
│   ├── app.setres.pas
│   ├── app.testcmd.pas
│   ├── app.uidebug.pas
│   ├── app.volcmd.pas
│   │
│   └── wasm/
│       ├── app.wasm.cleanup.pas
│       ├── app.wasm.io.pas
│       ├── app.wasm.runner.pas
│       └── app.wasm.shim.pas
```

---

## Complete Rename Mapping

### Root Entry Point

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `kernel.pas` | `asuro.pas` | `kernel` | `asuro` |

### Architecture — x86 (`arch/x86/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `include/system.pas` | `arch/x86/system.pas` | `system` | `system` |
| `gdt.pas` | `arch/x86/arch.x86.gdt.pas` | `gdt` | `arch.x86.gdt` |
| `idt.pas` | `arch/x86/arch.x86.idt.pas` | `idt` | `arch.x86.idt` |
| `irq.pas` | `arch/x86/arch.x86.irq.pas` | `irq` | `arch.x86.irq` |
| `isr.pas` | `arch/x86/arch.x86.isr.pas` | `isr` | `arch.x86.isr` |
| `cpu.pas` | `arch/x86/arch.x86.cpu.pas` | `cpu` | `arch.x86.cpu` |
| `faults.pas` | `arch/x86/arch.x86.faults.pas` | `faults` | `arch.x86.faults` |
| `contextswitcher.pas` | `arch/x86/proc/arch.x86.proc.sched.pas` | `contextswitcher` | `arch.x86.proc.sched` |
| `processloader.pas` | `arch/x86/proc/arch.x86.proc.loader.pas` | `processloader` | `arch.x86.proc.loader` |
| `v86.pas` | `arch/x86/arch.x86.v86.pas` | `v86` | `arch.x86.v86` |
| `include/multiboot.pas` | `arch/x86/arch.x86.multiboot.pas` | `multiboot` | `arch.x86.multiboot` |
| `include/bios_data_area.pas` | `arch/x86/arch.x86.bda.pas` | `bios_data_area` | `arch.x86.bda` |
| `include/util.pas` *(x86 parts)* | `arch/x86/arch.x86.util.pas` | `util` *(partial)* | `arch.x86.util` |
| `stub/stub.asm` | `arch/x86/boot/stub.asm` | — | — |

### Architecture — x86 Faults (`arch/x86/fault/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `fault/ACE.pas` | `arch/x86/fault/arch.x86.fault.ace.pas` | `ACE` | `arch.x86.fault.ace` |
| `fault/BPE.pas` | `arch/x86/fault/arch.x86.fault.bpe.pas` | `BPE` | `arch.x86.fault.bpe` |
| `fault/BTSSE.pas` | `arch/x86/fault/arch.x86.fault.btsse.pas` | `BTSSE` | `arch.x86.fault.btsse` |
| `fault/CFE.pas` | `arch/x86/fault/arch.x86.fault.cfe.pas` | `CFE` | `arch.x86.fault.cfe` |
| `fault/CSOE.pas` | `arch/x86/fault/arch.x86.fault.csoe.pas` | `CSOE` | `arch.x86.fault.csoe` |
| `fault/DBGE.pas` | `arch/x86/fault/arch.x86.fault.dbge.pas` | `DBGE` | `arch.x86.fault.dbge` |
| `fault/DBZ.pas` | `arch/x86/fault/arch.x86.fault.dbz.pas` | `DBZ` | `arch.x86.fault.dbz` |
| `fault/DFE.pas` | `arch/x86/fault/arch.x86.fault.dfe.pas` | `DFE` | `arch.x86.fault.dfe` |
| `fault/GPF.pas` | `arch/x86/fault/arch.x86.fault.gpf.pas` | `GPF` | `arch.x86.fault.gpf` |
| `fault/IDOE.pas` | `arch/x86/fault/arch.x86.fault.idoe.pas` | `IDOE` | `arch.x86.fault.idoe` |
| `fault/IOPE.pas` | `arch/x86/fault/arch.x86.fault.iope.pas` | `IOPE` | `arch.x86.fault.iope` |
| `fault/MCE.pas` | `arch/x86/fault/arch.x86.fault.mce.pas` | `MCE` | `arch.x86.fault.mce` |
| `fault/NCE.pas` | `arch/x86/fault/arch.x86.fault.nce.pas` | `NCE` | `arch.x86.fault.nce` |
| `fault/NMIE.pas` | `arch/x86/fault/arch.x86.fault.nmie.pas` | `NMIE` | `arch.x86.fault.nmie` |
| `fault/OOBE.pas` | `arch/x86/fault/arch.x86.fault.oobe.pas` | `OOBE` | `arch.x86.fault.oobe` |
| `fault/PF.pas` | `arch/x86/fault/arch.x86.fault.pf.pas` | `PF` | `arch.x86.fault.pf` |
| `fault/SFE.pas` | `arch/x86/fault/arch.x86.fault.sfe.pas` | `SFE` | `arch.x86.fault.sfe` |
| `fault/SNPE.pas` | `arch/x86/fault/arch.x86.fault.snpe.pas` | `SNPE` | `arch.x86.fault.snpe` |
| `fault/UIE.pas` | `arch/x86/fault/arch.x86.fault.uie.pas` | `UIE` | `arch.x86.fault.uie` |

### Architecture — x86 ISR (`arch/x86/isr/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `isr/isr_types.pas` | `arch/x86/isr/arch.x86.isr.types.pas` | `isr_types` | `arch.x86.isr.types` |
| `isr/isrmanager.pas` | `arch/x86/isr/arch.x86.isr.mgr.pas` | `isrmanager` | `arch.x86.isr.mgr` |
| `isr/ioapic.pas` | `arch/x86/isr/arch.x86.isr.ioapic.pas` | `ioapic` | `arch.x86.isr.ioapic` |
| `driver/timers/TMR_0_ISR.pas` | `arch/x86/isr/arch.x86.isr.tmr0.pas` | `TMR_0_ISR` | `arch.x86.isr.tmr0` |
| `driver/timers/TMR_1_ISR.pas` | `arch/x86/isr/arch.x86.isr.tmr1.pas` | `TMR_1_ISR` | `arch.x86.isr.tmr1` |
| `driver/hid/ps2/ps2_keyboard_isr.pas` | `arch/x86/isr/arch.x86.isr.ps2keyboard.pas` | `ps2_keyboard_isr` | `arch.x86.isr.ps2keyboard` |

### Architecture — x86 Memory (`arch/x86/memory/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `pmemorymanager.pas` | `arch/x86/memory/arch.x86.memory.physical.pas` | `pmemorymanager` | `arch.x86.memory.physical` |
| `vmemorymanager.pas` | `arch/x86/memory/arch.x86.memory.virtual.pas` | `vmemorymanager` | `arch.x86.memory.virtual` |

### Boot (`boot/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `prog/splash.pas` | `boot/boot.splash.pas` | `splash` | `boot.splash` |
| `stub/splash_tga.asm` | `boot/splash_tga.asm` | — | — |

### Core Libraries (`core/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `include/asuro.pas` | `core/core.version.pas` | `asuro` | `core.version` |
| `include/util.pas` *(portable parts)* | `core/core.util.pas` | `util` *(partial)* | `core.util` |
| `include/strings.pas` | `core/core.strings.pas` | `strings` | `core.strings` |
| `include/rand.pas` | `core/core.rand.pas` | `rand` | `core.rand` |
| `include/types.pas` | `core/core.types.pas` | `types` | `core.types` |
| `include/targa.pas` | `core/fmt/core.fmt.targa.pas` | `targa` | `core.fmt.targa` |

### Core — Data Structures (`core/ds/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `include/data_structures/dstypes.pas` | `core/ds/core.ds.types.pas` | `dstypes` | `core.ds.types` |
| `include/lists.pas` | `core/ds/core.ds.lists.pas` | `lists` | `core.ds.lists` |
| `include/hashmap.pas` | `core/ds/core.ds.hashmap.pas` | `hashmap` | `core.ds.hashmap` |
| `include/data_structures/fifo.pas` | `core/ds/core.ds.fifo.pas` | `fifo` | `core.ds.fifo` |
| `include/data_structures/cfifo.pas` | `core/ds/core.ds.cfifo.pas` | `cfifo` | `core.ds.cfifo` |
| `include/data_structures/cfifols.pas` | `core/ds/core.ds.cfifols.pas` | `cfifols` | `core.ds.cfifols` |
| `include/data_structures/lifo.pas` | `core/ds/core.ds.lifo.pas` | `lifo` | `core.ds.lifo` |
| `include/data_structures/circ.pas` | `core/ds/core.ds.circ.pas` | `circ` | `core.ds.circ` |
| `include/data_structures/bheap.pas` | `core/ds/core.ds.bheap.pas` | `bheap` | `core.ds.bheap` |
| `include/data_structures/minh.pas` | `core/ds/core.ds.minh.pas` | `minh` | `core.ds.minh` |
| `include/data_structures/maxh.pas` | `core/ds/core.ds.maxh.pas` | `maxh` | `core.ds.maxh` |
| `include/data_structures/prio.pas` | `core/ds/core.ds.prio.pas` | `prio` | `core.ds.prio` |

### Core — Encoding / Hashing (`core/enc/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `include/md5.pas` | `core/enc/core.enc.md5.pas` | `md5` | `core.enc.md5` |
| `include/sha1.pas` | `core/enc/core.enc.sha1.pas` | `sha1` | `core.enc.sha1` |
| `include/base64.pas` | `core/enc/core.enc.base64.pas` | `base64` | `core.enc.base64` |
| `include/crc.pas` | `core/enc/core.enc.crc.pas` | `crc` | `core.enc.crc` |

### Core — Graphics (`core/gfx/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `include/color.pas` | `core/gfx/core.gfx.color.pas` | `color` | `core.gfx.color` |
| `include/fonts.pas` | `core/gfx/core.gfx.fonts.pas` | `fonts` | `core.gfx.fonts` |
| `include/texture.pas` | `core/gfx/core.gfx.texture.pas` | `texture` | `core.gfx.texture` |

### IO (`io/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `stdio.pas` | `io/io.stdio.pas` | `stdio` | `io.stdio` |
| `syslog.pas` | `io/io.syslog.pas` | `syslog` | `io.syslog` |

### Debug (`debug/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `tracer.pas` | `debug/debug.tracer.pas` | `tracer` | `debug.tracer` |

### Memory (`memory/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `lmemorymanager.pas` | `memory/memory.heap.pas` | `lmemorymanager` | `memory.heap` |

### Process Management (`proc/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `processmanager.pas` | `proc/proc.mgr.pas` | `processmanager` | `proc.mgr` |
| `include/proctypes.pas` | `proc/proc.types.pas` | `proctypes` | `proc.types` |
| `testprocs.pas` | `proc/proc.testprocs.pas` | `testprocs` | `proc.testprocs` |

### Services (`svc/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `prog/graphicsrefresh.pas` | `svc/svc.gfxd.pas` | `graphicsrefresh` | `svc.gfxd` |
| `prog/usbhotplug.pas` | `svc/svc.usbd.pas` | `usbhotplug` | `svc.usbd` |

### Driver Framework (`driver/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `drivermanagement.pas` | `driver/driver.mgr.pas` | `drivermanagement` | `driver.mgr` |
| `driver/include/drivertypes.pas` | `driver/driver.types.pas` | `drivertypes` | `driver.types` |

### Driver — Bus (`driver/bus/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `driver/bus/PCI.pas` | `driver/bus/driver.bus.pci.pas` | `PCI` | `driver.bus.pci` |
| `driver/bus/usb/USB.pas` | `driver/bus/driver.bus.usb.pas` | `USB` | `driver.bus.usb` |
| `driver/bus/usb/usbtypes.pas` | `driver/bus/usb/driver.bus.usb.types.pas` | `usbtypes` | `driver.bus.usb.types` |
| `driver/bus/usb/usbcore.pas` | `driver/bus/usb/driver.bus.usb.core.pas` | `usbcore` | `driver.bus.usb.core` |
| `driver/bus/usb/usbhub.pas` | `driver/bus/usb/driver.bus.usb.hub.pas` | `usbhub` | `driver.bus.usb.hub` |
| `driver/bus/usb/UHCI.pas` | `driver/bus/usb/driver.bus.usb.uhci.pas` | `UHCI` | `driver.bus.usb.uhci` |
| `driver/bus/usb/OHCI.pas` | `driver/bus/usb/driver.bus.usb.ohci.pas` | `OHCI` | `driver.bus.usb.ohci` |
| `driver/bus/usb/EHCI.pas` | `driver/bus/usb/driver.bus.usb.ehci.pas` | `EHCI` | `driver.bus.usb.ehci` |
| `driver/bus/usb/XHCI.pas` | `driver/bus/usb/driver.bus.usb.xhci.pas` | `XHCI` | `driver.bus.usb.xhci` |

### Driver — HID (`driver/hid/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `driver/hid/keyboard.pas` | `driver/hid/driver.hid.keyboard.pas` | `keyboard` | `driver.hid.keyboard` |
| `driver/hid/mouse.pas` | `driver/hid/driver.hid.mouse.pas` | `mouse` | `driver.hid.mouse` |
| `driver/hid/ps2/ps2_keyboard.pas` | `driver/hid/ps2/driver.hid.ps2.keyboard.pas` | `ps2_keyboard` | `driver.hid.ps2.keyboard` |
| `driver/hid/ps2/ps2_mouse.pas` | `driver/hid/ps2/driver.hid.ps2.mouse.pas` | `ps2_mouse` | `driver.hid.ps2.mouse` |
| `driver/hid/usb/usb_keyboard.pas` | `driver/hid/usb/driver.hid.usb.keyboard.pas` | `usb_keyboard` | `driver.hid.usb.keyboard` |
| `driver/hid/usb/usb_mouse.pas` | `driver/hid/usb/driver.hid.usb.mouse.pas` | `usb_mouse` | `driver.hid.usb.mouse` |

### Driver — Interface (`driver/interface/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `driver/interface/serial.pas` | `driver/interface/driver.interface.serial.pas` | `serial` | `driver.interface.serial` |

### Driver — Timer (`driver/timer/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `driver/timers/RTC.pas` | `driver/timer/driver.timer.rtc.pas` | `RTC` | `driver.timer.rtc` |

### Driver — Storage (`driver/storage/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `driver/storage/storagemanager.pas` | `driver/storage/driver.storage.mgr.pas` | `storagemanager` | `driver.storage.mgr` |
| `driver/storage/storagetypes.pas` | `driver/storage/driver.storage.types.pas` | `storagetypes` | `driver.storage.types` |
| `driver/storage/storagetest.pas` | `driver/storage/driver.storage.test.pas` | `storagetest` | `driver.storage.test` |
| `driver/storage/vfs.pas` | `driver/storage/driver.storage.vfs.pas` | `vfs` | `driver.storage.vfs` |
| `driver/storage/fdtable.pas` | `driver/storage/driver.storage.fdtable.pas` | `fdtable` | `driver.storage.fdtable` |
| `filedispatch.pas` | `driver/storage/driver.storage.filedispatch.pas` | `filedispatch` | `driver.storage.filedispatch` |
| `driver/storage/iobuffer.pas` | `driver/storage/driver.storage.iobuffer.pas` | `iobuffer` | `driver.storage.iobuffer` |
| `driver/storage/iorequest.pas` | `driver/storage/driver.storage.iorequest.pas` | `iorequest` | `driver.storage.iorequest` |

### Driver — Storage — Controllers (`driver/storage/ctl/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `driver/storage/usb_storage.pas` | `driver/storage/ctl/driver.storage.ctl.usb.pas` | `usb_storage` | `driver.storage.ctl.usb` |
| `driver/storage/ramdrive.pas` | `driver/storage/ctl/driver.storage.ctl.ram.pas` | `ramdrive` | `driver.storage.ctl.ram` |

### Driver — Storage — Controllers — AHCI (`driver/storage/ctl/ahci/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `driver/storage/AHCI/AHCI.pas` | `driver/storage/ctl/ahci/driver.storage.ctl.ahci.pas` | `AHCI` | `driver.storage.ctl.ahci` |
| `driver/storage/AHCI/AHCITypes.pas` | `driver/storage/ctl/ahci/driver.storage.ctl.ahci.types.pas` | `AHCITypes` | `driver.storage.ctl.ahci.types` |

### Driver — Storage — Controllers — IDE (`driver/storage/ctl/ide/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `driver/storage/IDE/IDE.pas` | `driver/storage/ctl/ide/driver.storage.ctl.ide.pas` | `IDE` | `driver.storage.ctl.ide` |
| `driver/storage/IDE/idetypes.pas` | `driver/storage/ctl/ide/driver.storage.ctl.ide.types.pas` | `idetypes` | `driver.storage.ctl.ide.types` |
| `driver/storage/IDE/ata.pas` | `driver/storage/ctl/ide/driver.storage.ctl.ide.ata.pas` | `ata` | `driver.storage.ctl.ide.ata` |
| `driver/storage/IDE/atapi.pas` | `driver/storage/ctl/ide/driver.storage.ctl.ide.atapi.pas` | `atapi` | `driver.storage.ctl.ide.atapi` |

### Driver — Storage — Filesystems (`driver/storage/fs/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `driver/storage/Filesystems/filesystemmanager.pas` | `driver/storage/fs/driver.storage.fs.mgr.pas` | `filesystemmanager` | `driver.storage.fs.mgr` |
| `driver/storage/Filesystems/fat32.pas` | `driver/storage/fs/driver.storage.fs.fat32.pas` | `fat32` | `driver.storage.fs.fat32` |
| `driver/storage/Filesystems/asfs.pas` | `driver/storage/fs/driver.storage.fs.asfs.pas` | `asfs` | `driver.storage.fs.asfs` |
| `driver/storage/Filesystems/flatfs.pas` | `driver/storage/fs/driver.storage.fs.flatfs.pas` | `flatfs` | `driver.storage.fs.flatfs` |
| `driver/storage/Filesystems/iso9660.pas` | `driver/storage/fs/driver.storage.fs.iso9660.pas` | `iso9660` | `driver.storage.fs.iso9660` |

### Driver — Storage — Volume (`driver/storage/vol/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `driver/storage/volumemanager.pas` | `driver/storage/vol/driver.storage.vol.mgr.pas` | `volumemanager` | `driver.storage.vol.mgr` |
| `driver/storage/partitiontable.pas` | `driver/storage/vol/driver.storage.vol.table.pas` | `partitiontable` | `driver.storage.vol.table` |
| `driver/storage/MBR.pas` | `driver/storage/vol/driver.storage.vol.mbr.pas` | `MBR` | `driver.storage.vol.mbr` |
| `driver/storage/gpt.pas` | `driver/storage/vol/driver.storage.vol.gpt.pas` | `gpt` | `driver.storage.vol.gpt` |

### Driver — Network (`driver/net/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `driver/net/l1/net.pas` | `driver/driver.net.pas` | `net` | `driver.net` |
| `driver/net/include/nettypes.pas` | `driver/net/driver.net.types.pas` | `nettypes` | `driver.net.types` |
| `driver/net/include/netutils.pas` | `driver/net/driver.net.util.pas` | `netutils` | `driver.net.util` |
| `driver/net/l2/eth2.pas` | `driver/net/driver.net.eth2.pas` | `eth2` | `driver.net.eth2` |
| `driver/net/l3/arp.pas` | `driver/net/driver.net.arp.pas` | `arp` | `driver.net.arp` |
| `driver/net/l3/ipv4.pas` | `driver/net/driver.net.ipv4.pas` | `ipv4` | `driver.net.ipv4` |
| `driver/net/l4/icmp.pas` | `driver/net/driver.net.icmp.pas` | `icmp` | `driver.net.icmp` |
| `driver/net/l4/tcp.pas` | `driver/net/driver.net.tcp.pas` | `tcp` | `driver.net.tcp` |
| `driver/net/l4/udp.pas` | `driver/net/driver.net.udp.pas` | `udp` | `driver.net.udp` |
| `driver/net/l5/dhcp.pas` | `driver/net/driver.net.dhcp.pas` | `dhcp` | `driver.net.dhcp` |

> **Note:** The old layer folders (`l1/`, `l2/`, `l3/`, `l4/`, `l5/`, `include/`) are flattened — protocol names are self-descriptive.

### Driver — Network Device (`driver/netdev/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `driver/netdev/E1000.pas` | `driver/netdev/driver.netdev.e1000.pas` | `E1000` | `driver.netdev.e1000` |

### Driver — Video (`driver/video/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `driver/video/video.pas` | `driver/driver.video.pas` | `video` | `driver.video` |
| `driver/video/videotypes.pas` | `driver/video/driver.video.types.pas` | `videotypes` | `driver.video.types` |
| `driver/video/gpu.pas` | `driver/video/driver.video.gpu.pas` | `gpu` | `driver.video.gpu` |
| `driver/video/vesa.pas` | `driver/video/driver.video.vesa.pas` | `vesa` | `driver.video.vesa` |
| `driver/video/vesa8.pas` | `driver/video/driver.video.vesa8.pas` | `vesa8` | `driver.video.vesa8` |
| `driver/video/vesa16.pas` | `driver/video/driver.video.vesa16.pas` | `vesa16` | `driver.video.vesa16` |
| `driver/video/vesa24.pas` | `driver/video/driver.video.vesa24.pas` | `vesa24` | `driver.video.vesa24` |
| `driver/video/vesa32.pas` | `driver/video/driver.video.vesa32.pas` | `vesa32` | `driver.video.vesa32` |
| `driver/video/doublebuffer.pas` | `driver/video/driver.video.doublebuffer.pas` | `doublebuffer` | `driver.video.doublebuffer` |
| `driver/video/bga.pas` | `driver/video/driver.video.bga.pas` | `bga` | `driver.video.bga` |
| `driver/video/lvgl.pas` | `driver/video/driver.video.lvgl.pas` | `lvgl` | `driver.video.lvgl` |
| `driver/video/windows.pas` | `driver/video/driver.video.windows.pas` | `windows` | `driver.video.windows` |
| `driver/video/desktop.pas` | `driver/video/driver.video.desktop.pas` | `desktop` | `driver.video.desktop` |

### Driver — Experimental (`driver/exp/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `driver/exp/testdriver.pas` | `driver/exp/driver.exp.testdriver.pas` | `testdriver` | `driver.exp.testdriver` |

### Applications (`app/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `progmanager.pas` | `app/app.mgr.pas` | `progmanager` | `app.mgr` |
| `prog/vterminal.pas` | `app/app.vterminal.pas` | `vterminal` | `app.vterminal` |
| `prog/base64_prog.pas` | `app/app.base64.pas` | `base64_prog` | `app.base64` |
| `prog/md5sum.pas` | `app/app.md5sum.pas` | `md5sum` | `app.md5sum` |
| `prog/dhclient.pas` | `app/app.dhclient.pas` | `dhclient` | `app.dhclient` |
| `prog/vbeinfo.pas` | `app/app.vbeinfo.pas` | `vbeinfo` | `app.vbeinfo` |
| `prog/diskcmd.pas` | `app/app.diskcmd.pas` | `diskcmd` | `app.diskcmd` |
| `prog/diskutil.pas` | `app/app.diskutil.pas` | `diskutil` | `app.diskutil` |
| `prog/edit.pas` | `app/app.edit.pas` | `edit` | `app.edit` |
| `prog/filepicker.pas` | `app/app.filepicker.pas` | `filepicker` | `app.filepicker` |
| `prog/inio.pas` | `app/app.inio.pas` | `inio` | `app.inio` |
| `prog/meminfo.pas` | `app/app.meminfo.pas` | `meminfo` | `app.meminfo` |
| `prog/notepad.pas` | `app/app.notepad.pas` | `notepad` | `app.notepad` |
| `prog/partcmd.pas` | `app/app.partcmd.pas` | `partcmd` | `app.partcmd` |
| `prog/ping.pas` | `app/app.ping.pas` | `ping` | `app.ping` |
| `prog/setres.pas` | `app/app.setres.pas` | `setres` | `app.setres` |
| `prog/testcmd.pas` | `app/app.testcmd.pas` | `testcmd` | `app.testcmd` |
| `prog/uidebug.pas` | `app/app.uidebug.pas` | `uidebug` | `app.uidebug` |
| `prog/volcmd.pas` | `app/app.volcmd.pas` | `volcmd` | `app.volcmd` |

### Applications — WASM (`app/wasm/`)

| Old path | New path | Old unit | New unit |
|----------|----------|----------|----------|
| `prog/wasm/wasmcleanup.pas` | `app/wasm/app.wasm.cleanup.pas` | `wasmcleanup` | `app.wasm.cleanup` |
| `prog/wasm/wasmio.pas` | `app/wasm/app.wasm.io.pas` | `wasmio` | `app.wasm.io` |
| `prog/wasm/wasmrunner.pas` | `app/wasm/app.wasm.runner.pas` | `wasmrunner` | `app.wasm.runner` |
| `prog/wasm/wasmshim.pas` | `app/wasm/app.wasm.shim.pas` | `wasmshim` | `app.wasm.shim` |

---

## Special Cases

### `system.pas`

FPC requires the `system` unit to be named exactly `system`. It cannot be renamed. It moves to `arch/x86/system.pas` and the build system must add `-Fuarch/x86` so FPC can find it.

### `util.pas` Split

The current `include/util.pas` (~55 dependents) must be split into two units:

- **`core.util`** — portable helpers: `IntToStr`, `HexToStr`, `min`/`max`, `redraw`, string/array utilities, sleep logic (calling into a clock abstraction)
- **`arch.x86.util`** — x86 I/O: `outb`/`inb`/`outw`/`inw`/`outl`/`inl`, `CLI`/`STI`, TSC reads, `BSOD` (writes VGA text-mode memory at `$B8000`), anything with `{$ASMMODE intel}` inline assembly

Units that only use portable helpers: `uses core.util`
Units that also do port I/O: `uses core.util, arch.x86.util`

### `include/asuro.pas` → `core.version`

The old `include/asuro.pas` (version/build metadata) is renamed to `core.version` to avoid collision with the main entry point `asuro.pas`. All `uses asuro` references for version info become `uses core.version`.

### `stub.asm` Entry Point

The assembly boot stub calls `kmain` (the Pascal entry point exported by `kernel.pas`). After renaming the unit to `asuro`, verify the FPC-mangled symbol name. If it changes, update the `call` instruction in `stub.asm` accordingly.

---

## Future Namespace Reservations

| Namespace | Purpose |
|-----------|---------|
| `wasm.*` | WASM virtual machine (currently external `wasuro/`) |
| `arch.arm.*` | ARM architecture port |
| `arch.riscv.*` | RISC-V architecture port |
