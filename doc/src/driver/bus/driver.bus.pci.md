# driver.bus.pci

PCI bus scanner and device enumeration.

## Overview

This unit scans the PCI configuration space to discover all devices present in the system. For each discovered device, it reads the full type-0 configuration header, constructs a `TDeviceIdentifier`, and calls `driver.mgr.register_device` so that matching drivers are loaded. It also provides utilities to query already-discovered devices by class/subclass/prog_if and to enable a device for memory-mapped I/O and DMA.

The scanner self-registers with `driver.mgr` using `register_driver_ex` with `force_load := true`, so it runs automatically during driver initialisation without requiring a PCI device match.

## Dependencies

- `driver.types`
- `driver.mgr`
- `syslog`
- `debug.tracer`
- `core.paging` (for MMIO mapping)

## Functions and Procedures

### init
```pascal
procedure init;
```
Registers the PCI bus scanner driver with `driver.mgr` (force-loaded). Triggers `scanBus(0)` to begin enumeration from bus 0.

### scanBus
```pascal
procedure scanBus(bus: uint8);
```
Iterates all 32 device slots on the specified bus. For each present device, reads the header type. Single-function devices call `loadDeviceConfig`; multi-function devices (bit 7 of header type set) iterate all 8 functions. Bridges (header type 1) call `loadBusConfig` to recurse into the secondary bus.

### loadDeviceConfig
```pascal
procedure loadDeviceConfig(bus, slot, func: uint8);
```
Reads the full PCI type-0 configuration header for the given bus/slot/function via I/O ports `$CF8`/`$CFC`. Builds a `TDeviceIdentifier` with:
- `id0` = `device_id`
- `id1` = `class_code`
- `id2` = `subclass`
- `id3` = `prog_if`
- `id4` (extended) = `vendor_id`

Calls `driver.mgr.register_device` with the identifier and a pointer to the populated `TPCI_Device` record.

### loadBusConfig
```pascal
procedure loadBusConfig(bus, slot, func: uint8);
```
Reads the PCI-to-PCI bridge header (type 1) and recursively calls `scanBus` on the secondary bus number.

### getDeviceInfo
```pascal
function getDeviceInfo(class_code, subclass, prog_if: uint8): TDeviceArray;
```
Returns an array of up to 32 `TPCI_Device` records matching the given class, subclass, and programming interface. Used by host controller drivers to locate their hardware.

### enableDevice
```pascal
procedure enableDevice(device: PPCI_Device);
```
Sets the `PCI_COMMAND_MEM_SPACE` and `PCI_COMMAND_BUS_MASTER` bits in the device's command register and clears `PCI_COMMAND_INT_DISABLE`. Required before a device can perform MMIO or DMA.

## Notes

- PCI configuration space is accessed through the legacy mechanism: write a 32-bit address to port `$CF8` encoding bus/device/function/register, then read or write port `$CFC`.
- The scanner performs a breadth-first traversal by recursing into bridge secondary buses.
- Vendor ID `$FFFF` indicates an unpopulated slot and is skipped.
