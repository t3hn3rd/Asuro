# Asuro OS

Asuro is a 32-bit x86 operating system kernel written in Free Pascal and x86 assembly.

## Documentation Structure

- **Kernel Entry** -- The `asuro.pas` main unit and boot sequence.
- **Architecture (x86)** -- CPU initialization, descriptor tables, interrupt handling, fault handlers, memory management, and process scheduling for the i386 target.
- **Boot** -- Splash screen and early boot visuals.
- **Core** -- Foundational libraries including data structures, encoding algorithms, string handling, graphics primitives, and the kernel panic subsystem.
- **Memory** -- Heap allocator (`kalloc`/`kfree`) and page-level allocation.
- **Processes** -- Process lifecycle, round-robin scheduling, and inter-process messaging.
- **I/O** -- Standard I/O (shell command dispatch) and the system log fan-out.
- **Debug** -- Execution tracer with ring-buffer call stack recording.
- **Drivers** -- Hardware abstraction covering PCI/USB buses, HID devices, networking (E1000, TCP/IP stack), storage (IDE, AHCI, VFS, file systems), video (VESA, LVGL, double-buffering), serial I/O, and timers.
- **Services** -- Background daemons for graphics rendering and USB hotplug.
- **Applications** -- Userland commands and utilities: terminal, text editor, disk tools, network tools, and a WebAssembly runtime.
- **Compatibility** -- Shim layers for legacy code.
- **LVGL Headers** -- Configuration and patches for the LVGL v9.2.2 GUI library.
- **Planning** -- Design documents and architectural notes for subsystems under development.
- **Toolchain** -- Build pipeline documentation covering compilation, linking, and ISO generation.

## Building

The kernel is built inside Docker using a containerized FreePascal 3.2.2 toolchain:

```bash
docker compose build builder
docker compose run builder
```

The documentation site will be available at `http://docs.asuro.xyz`.
