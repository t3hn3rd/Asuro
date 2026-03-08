# app.mgr

Central initialization manager for all baked-in terminal programs and kernel-level command providers.

## Overview

`app.mgr` is the single entry point that registers all built-in shell commands and initializes every bundled application module at boot time. It is called once from `kmain` during the application initialization phase. The unit separates command registration (wiring handler function pointers directly into `io.stdio`) from application-level initialization (which may allocate state, register with the desktop, or set up WASM integration).

## Dependencies

- `debug.tracer`, `io.stdio`, `proc.mgr`
- `app.base64`, `app.md5sum`, `app.dhclient`, `app.vbeinfo`, `app.testcmd`, `app.ping`, `app.meminfo`, `app.setres`
- `driver.storage.ctl.ram`, `driver.mgr`
- `driver.net.proto.ipv4`, `driver.net.proto.arp`, `driver.net.proto.tcp`
- `driver.storage.filedispatch`
- `app.wasm.runner`
- `core.version`, `arch.x86.cpu`
- `app.diskcmd`, `driver.bus.usb.core`, `app.diskutil`, `app.notepad`, `app.partcmd`, `app.volcmd`

## Functions and Procedures

### init

```pascal
procedure init();
```

Registers all kernel-level terminal commands and calls `init()` on every bundled application unit. Commands registered directly from driver and subsystem modules:

| Command | Description |
|---|---|
| `CPU` | CPU information |
| `DEV` | Driver management interface |
| `PS` | List running processes |
| `KILL` | Force-kill a process by PID |
| `TERMINATE` | Gracefully terminate a process by PID |
| `ARP` | Get ARP table |
| `IFCONFIG` | Configure network settings |
| `TCPCONNECT` | Connect to a TCP host and send a test message |
| `TCPLISTEN` | Listen on a TCP port and log received data |
| `TCPHTTP` | Send HTTP GET to a host IP |
| `USB` | USB subsystem information |

Application modules initialized (each registers its own command internally): `app.diskcmd`, `app.partcmd`, `app.volcmd`, `app.diskutil`, `app.notepad`, `app.md5sum`, `app.base64`, `app.dhclient`, `app.vbeinfo`, `app.testcmd`, `app.ping`, `app.meminfo`.

Finally initializes the RAM storage controller, file dispatch subsystem, WASM runner, and display resolution command.

## Notes

Initialization order is significant: `driver.storage.ctl.ram.init()` and `driver.storage.filedispatch.init()` must precede `app.wasm.runner.init()` because the WASM runner registers a file-type handler with the dispatch subsystem.
