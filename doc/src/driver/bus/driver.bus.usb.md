# driver.bus.usb

USB bus entry point and host controller driver registration.

## Overview

This unit is the top-level initialiser for the USB subsystem. It initialises the USB core, hub, HID, and storage class drivers, then registers four host controller drivers with `driver.mgr` — one for each supported USB host controller standard. Each registration uses PCI class `$0C` (Serial Bus), subclass `$03` (USB), with the programming interface byte distinguishing the controller type.

## Dependencies

- `driver.mgr`
- `driver.bus.usb.core`
- `driver.bus.usb.uhci`
- `driver.bus.usb.ohci`
- `driver.bus.usb.ehci`
- `driver.bus.usb.xhci`
- `driver.bus.usb.hub`
- `driver.hid.usb.keyboard`
- `driver.hid.usb.mouse`

## Functions and Procedures

### init
```pascal
procedure init;
```
Initialises the USB subsystem in order:
1. Calls `driver.bus.usb.core.init`.
2. Calls `driver.bus.usb.hub.init`.
3. Registers USB HID class drivers (keyboard and mouse).
4. Registers four PCI-matched driver entries with `driver.mgr`:

| Driver | prog_if | Description |
|---|---|---|
| UHCI | `$00` | Universal Host Controller Interface (USB 1.x) |
| OHCI | `$10` | Open Host Controller Interface (USB 1.x) |
| EHCI | `$20` | Enhanced Host Controller Interface (USB 2.0) |
| xHCI | `$30` | Extensible Host Controller Interface (USB 3.x) |

All four registrations use `bus = biPCI`, `id1 = $0C`, `id2 = $03`.

## Notes

- The host controller load callbacks (`driver.bus.usb.uhci.load`, etc.) are passed directly as the `Driver_Load` parameter to `driver.mgr.register_driver`.
- USB class drivers (HID keyboard/mouse) are registered separately via their own `init` calls and respond to USB device enumeration events fired by the core.
