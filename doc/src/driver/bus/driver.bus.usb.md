# driver.bus.usb

USB bus entry point and host controller driver registration.

## Overview

This unit is the top-level initialiser for the USB subsystem. It initialises the USB core and hub driver, then registers four host controller drivers with `driver.mgr` — one for each supported USB host controller standard. Each registration uses PCI class `$0C` (Serial Bus), subclass `$03` (USB), with the programming interface byte distinguishing the controller type.

HID class drivers (keyboard, mouse) and the USB mass storage class driver are no longer initialised by this unit — they self-register with `boot.mgr` at the `device` barrier and run after the `bus` phase completes.

## Boot Registration

Registered with `boot.mgr` as `driver.bus.usb` at the `bus` barrier (`BOOT_MGR_BARRIER_BUS`).

## Dependencies

- `boot.mgr`
- `driver.mgr`
- `driver.bus.usb.core`
- `driver.bus.usb.uhci`
- `driver.bus.usb.ohci`
- `driver.bus.usb.ehci`
- `driver.bus.usb.xhci`
- `driver.bus.usb.hub`

## Functions and Procedures

### init
```pascal
procedure init;
```
Initialises the USB subsystem in order:
1. Calls `driver.bus.usb.core.init` (resets HC list, completion hooks, device tables).
2. Calls `driver.bus.usb.hub.init` (registers USB hub class driver).
3. Registers four PCI-matched driver entries with `driver.mgr`:

| Driver | prog_if | Description |
|---|---|---|
| UHCI | `$00` | Universal Host Controller Interface (USB 1.x) |
| OHCI | `$10` | Open Host Controller Interface (USB 1.x) |
| EHCI | `$20` | Enhanced Host Controller Interface (USB 2.0) |
| xHCI | `$30` | Extensible Host Controller Interface (USB 3.x) |

All four registrations use `bus = biPCI`, `id1 = $0C`, `id2 = $03`.

## Notes

- The host controller load callbacks (`driver.bus.usb.uhci.load`, etc.) are passed directly as the `Driver_Load` parameter to `driver.mgr.register_driver`.
- HID and storage class drivers self-register with `boot.mgr` at the `device` barrier, which runs after the `bus` barrier. This ensures `core.init` has already reset the completion hook table before class drivers register their polling hooks.
- USB class drivers respond to USB device enumeration events fired by the core after host controllers discover connected devices during PCI scan (at the `bus.late` barrier).
