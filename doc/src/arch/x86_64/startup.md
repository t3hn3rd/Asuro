# Native x86-64 startup

The x86-64 profile selects `ppcx64`, ELF64 objects, its own linker script and `arch.x86_64.boot` as the Pascal entry unit. The ISO starts at a 32-bit Multiboot stub. That stub checks CPU support, constructs the initial page tables and enters long mode before calling Pascal. The architecture-specific `system.pas` supplies compiler services, with scalar definitions shared under `arch/common`.

| Stage | Owner | Work completed before handoff |
| --- | --- | --- |
| Early diagnostics | `arch.x86_64.debug`, `arch.x86_64.isr` | Initialize COM1, install exception handling and make early failures observable. |
| Kernel foundations | `arch.x86_64.boot.kmain` | Check the Multiboot handoff and native widths, initialize physical and virtual memory, the shared heap, interrupts and scheduling. |
| First scheduled task | `finish_boot` | Register shared devices and native callbacks. Check dependencies before PCI discovery, volume mounting, USB host enumeration and desktop startup. |
| Interactive desktop | `app.mgr`, `svc.gfxd` | Register applications and start the graphics process after initializing the desktop. |

The boot stub sets COM1 to 115200 baud for diagnostics. On entry to Pascal, the shared serial driver configures COM2 through COM4 for 38400 baud, 8 data bits, no parity and one stop bit. The native test runner reads back the line format and baud divisor of each secondary UART present.

The service graph uses the already initialized serial log as a dependency. Filesystem drivers and the storage manager are ready before PCI discovery publishes devices. See the [boot manager](../../boot/boot.mgr.md) and [build and boot commands](../../../planning/x86_64.md#build-and-boot).
