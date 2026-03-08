# driver.mgr

Driver registration and device management for the Asuro driver framework.

## Overview

This unit implements the central driver manager. It maintains a list of registered drivers and a list of discovered devices. When a device is registered, the manager scans all registered drivers for an identifier match and invokes the matched driver's load callback. Terminal commands are provided to inspect registered drivers and devices at runtime.

## Dependencies

- `driver.types`
- `terminal`
- `syslog`

## Constants

### idANY
Value: `$FFFFFFFF`. Wildcard value for any field of a `TDeviceIdentifier`. A driver using `idANY` in a given identifier field will match any device value in that field.

## Types

### TBusIdentifier

Enumeration of supported bus types used to classify devices during registration.

| Value | Description |
|---|---|
| `biUnknown` | Unknown or unclassified bus |
| `biPCI` | PCI bus |
| `biUSB` | USB bus |
| `bii2c` | I2C bus |
| `biPCIe` | PCI Express bus |
| `biANY` | Matches any bus type |

### TDevEx

A linked-list node for extended device identifiers. Allows drivers to specify additional identifier fields beyond the base four.

| Field | Type | Description |
|---|---|---|
| `id` | `uint32` | Extended identifier value |
| `Next` | `^TDevEx` | Pointer to next node, or `nil` |

### TDeviceIdentifier

Uniquely identifies a class of device. Used by both driver registration (what devices the driver handles) and device registration (what device was discovered).

| Field | Type | Description |
|---|---|---|
| `bus` | `TBusIdentifier` | Bus type |
| `id0..id3` | `uint32` | Primary identifier fields |
| `Extended` | `^TDevEx` | Optional linked list of additional identifiers |

### TDriverRegistration

Represents a registered driver entry.

| Field | Type | Description |
|---|---|---|
| `Identifier` | `TDeviceIdentifier` | The device pattern this driver handles |
| `Driver_Load` | `procedure(ptr: pointer)` | Callback invoked when a matching device is found |
| `Name` | `string` | Human-readable driver name |

### TDeviceRegistration

Represents a registered device entry.

| Field | Type | Description |
|---|---|---|
| `Identifier` | `TDeviceIdentifier` | The identifier of the discovered device |
| `Ptr` | `pointer` | Opaque pointer to device-specific data passed to the driver load callback |

## Functions and Procedures

### init
```pascal
procedure init;
```
Initialises the driver manager. Must be called before any registration functions.

### register_driver
```pascal
procedure register_driver(Identifier: TDeviceIdentifier; Driver_Load: TDriverLoadProc; Name: string);
```
Registers a driver with a given device identifier pattern. When a device matching the pattern is subsequently discovered, `Driver_Load` is called with the device pointer.

### register_driver_ex
```pascal
procedure register_driver_ex(Identifier: TDeviceIdentifier; Driver_Load: TDriverLoadProc; Name: string; force_load: boolean);
```
Extended registration. When `force_load` is `true`, `Driver_Load` is called immediately regardless of whether a matching device is present. Used by drivers that self-initialise without waiting for device discovery (e.g. bus scanners, PS/2 controllers).

### register_device
```pascal
procedure register_device(Identifier: TDeviceIdentifier; Ptr: pointer);
```
Registers a discovered device. Iterates all registered drivers, calls `identifiers_match` for each, and invokes the first matching driver's `Driver_Load` with `Ptr`.

### terminal_command_dev
```pascal
procedure terminal_command_dev(args: string);
```
Terminal command handler for the `dev` command. Subcommands:
- `dev drivers` — lists all registered drivers with their identifier fields
- `dev devices` — lists all registered devices
- `dev driverex` — lists drivers with extended identifier chains

## Notes

- Identifier matching treats `idANY` (`$FFFFFFFF`) in a driver's field as a wildcard that matches any value in the corresponding device field.
- The bus field is compared directly; `biANY` in the driver identifier matches any bus type.
- Extended identifiers in `TDevEx` chains are matched in order; the chain length must be equal between driver and device identifiers for a full match.
- Only the first matching driver is invoked per `register_device` call.
