# driver.storage.ctl.usb

USB Mass Storage Class driver stub.

## Overview

This unit registers a USB class driver with the driver manager (`driver.mgr`) to claim USB Mass Storage Class interfaces (class `$08`, subclass `$06` SCSI, protocol `$50` Bulk-Only). When the USB stack enumerates a matching interface, the `load` callback is invoked. Currently the callback only logs a detection message; no I/O infrastructure is established.

Full Bulk-Only Transport (BOT) support — including Max LUN query, endpoint setup, CBW/CSW command exchange, and `driver.storage.mgr` device registration — is planned but not yet implemented.

## Boot Registration

Registered with `boot.mgr` as `driver.storage.ctl.usb` at the `device` barrier. The barrier order places `device` after `bus`, ensuring `driver.bus.usb.core.init` has run before the storage class driver registers with the driver manager.

## Dependencies

- `boot.mgr`

- `driver.mgr`
- `memory.heap`
- `driver.storage.types`
- `io.syslog`
- `debug.tracer`
- `driver.bus.usb.core`
- `driver.bus.usb.types`
- `core.util`, `arch.x86.util`

## Constants

| Constant | Value | Description |
|---|---|---|
| `USB_CLASS_MASS_STORAGE` | `$08` | USB interface class for mass storage |
| `USB_SC_SCSI` | `$06` | SCSI transparent command set subclass |
| `USB_PROTO_BBB` | `$50` | Bulk-Only (BOT) transport protocol |

## Functions and Procedures

### init

```pascal
procedure init;
```

Constructs a `TDeviceIdentifier` matching any USB device with `bInterfaceClass = $08`, `bInterfaceSubClass = $06`, `bInterfaceProtocol = $50`, and registers the `load` callback with `driver.mgr`.

## Notes

- The `load` callback currently returns true unconditionally after logging a detection message.
- Once full BOT support is implemented, `load` should query the Max LUN, allocate endpoint structures, and call `driver.storage.mgr.register_device` for each logical unit.
