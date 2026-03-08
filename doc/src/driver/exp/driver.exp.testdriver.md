# driver.exp.testdriver

Experimental test driver for driver.mgr registration pipeline validation.

## Overview

This is a minimal dummy driver used to verify the `driver.mgr` registration and device-matching pipeline. It registers for PCI host bridge devices (class `$06`, subclass `$00`, prog_if `$00`) and logs a message when loaded. It has no functional effect on hardware.

## Dependencies

- `driver.mgr`
- `driver.types`
- `syslog`

## Functions and Procedures

### init
```pascal
procedure init;
```
Registers the test driver with `driver.mgr` using a `TDeviceIdentifier` with `bus = biPCI`, `id1 = $06` (bridge class), `id2 = $00`, `id3 = $00`.

### load
```pascal
function load(ptr: pointer): boolean;
```
Driver load callback invoked by `driver.mgr` when a matching PCI device is discovered. Writes `'LOADED'` to the system log. Always returns `true`.

## Notes

- This driver is intended for development and testing only. It should not be included in production builds as it occupies the host bridge driver slot without providing any useful functionality.
