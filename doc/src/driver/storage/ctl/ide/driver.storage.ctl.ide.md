# driver.storage.ctl.ide

IDE (ATA/ATAPI) controller driver — bus enumeration and device loading.

## Overview

This unit is the top-level IDE controller driver. It registers with the PCI driver manager to claim PCI mass storage devices (class `$01`, subclass `$01`) and probes all four IDE device slots (primary master, primary slave, secondary master, secondary slave) when a matching PCI device is found.

For each slot, `load_device` determines whether the device is ATA or ATAPI, calls the appropriate identify procedure from `driver.storage.ctl.ide.ata` or `driver.storage.ctl.ide.atapi`, and allocates a `TStorage_Device`. ATA devices are marked writable; ATAPI devices are read-only.

The unit is marked as incomplete in the source. Device registration with the storage manager (`driver.storage.mgr.register_device`) is commented out. The dispatch function pointers (`dispatchRead`, `dispatchWrite`) required by the Phase 2 I/O path are not wired up. As a result, IDE devices detected by this driver are not accessible through the standard `storage_read` / `storage_write` API in current builds.

## Dependencies

- `driver.storage.ctl.ide.ata`
- `driver.storage.ctl.ide.atapi`
- `console`
- `driver.mgr`
- `driver.types`
- `driver.storage.ctl.ide.types`
- `arch.x86.isr.mgr`
- `memory.heap`
- `driver.storage.types`
- `core.strings`
- `terminal`
- `debug.tracer`
- `core.util`, `arch.x86.util`
- `arch.x86.memory.virtual`

## Variables

| Name | Description |
|---|---|
| `primaryDevices[0..1]` | IDE devices on the primary channel (master and slave) |
| `secondaryDevices[0..1]` | IDE devices on the secondary channel (master and slave) |

Each entry is a `TIDE_Device` pre-initialised with the appropriate base port and channel/slot flags.

## Functions and Procedures

### init

```pascal
procedure init();
```

Constructs a `TDeviceIdentifier` for PCI class `$01` / subclass `$01` (IDE controller) and registers the `load` callback with `driver.mgr`.

### load

```pascal
function load(ptr: void) : boolean;
```

Called by `driver.mgr` when a matching PCI device is found. Registers ISR handlers for IRQ 14 and 15, then calls `load_device` for all four IDE slots. Logs the count of detected devices to the console.

### get_status

```pascal
function get_status(var device : TIDE_Device) : TIDE_Status;
```

Reads the ATA status register for `device` and updates `device.status`. If the error bit is set, reads the error register and logs the specific error bits to the console.

### wait_for_device

```pascal
function wait_for_device(device : TIDE_Device; ioop : boolean) : boolean;
```

Polls the status register up to 50,000 times until the device is not busy and (if `ioop` is true) DRQ is set. Returns false on timeout.

### no_interrupt / enable_interrupt

```pascal
procedure no_interrupt(isPrimary : boolean);
procedure enable_interrupt(isPrimary : boolean);
```

Sets or clears the nIEN (interrupt disable) bit in the device control register for the primary (`$3F6`) or secondary (`$376`) channel.

### reset_device

```pascal
procedure reset_device(device : TIDE_Device);
```

Performs a software reset on the IDE channel by asserting and then clearing the SRST bit in the control register, with a short delay.

### select_device

```pascal
procedure select_device(device : TIDE_Device);
```

Selects the master (`$A0`) or slave (`$B0`) device on the channel by writing to the drive/head register.

## Notes

- This driver uses polling I/O (PIO) and does not implement DMA. All data transfer is done by `driver.storage.ctl.ide.ata` and `driver.storage.ctl.ide.atapi` through port I/O.
- The commented-out write test and read-back code in `load_device` is leftover debug code and has no functional effect.
- Device registration is commented out; integrating this driver with the storage manager requires uncommenting that code and implementing `dispatchRead`/`dispatchWrite` callbacks.
