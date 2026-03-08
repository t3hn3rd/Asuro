# driver.bus.usb.hub

USB hub class driver for multi-level port topology.

## Overview

This unit implements the USB hub class driver. It handles hub device initialisation, power sequencing, port status polling, and hotplug detection. When a new device is detected on a hub port, it calls back into `driver.bus.usb.core` to enumerate the downstream device. This enables multi-level USB topologies.

## Dependencies

- `driver.bus.usb.types`
- `driver.bus.usb.core`
- `driver.mgr`
- `syslog`

## Constants

### Hub Feature Selectors
`HUB_FEAT_C_HUB_LOCAL_POWER`, `HUB_FEAT_C_HUB_OVER_CURRENT`.

### Port Feature Selectors
`PORT_FEAT_CONNECTION`, `PORT_FEAT_ENABLE`, `PORT_FEAT_SUSPEND`, `PORT_FEAT_OVER_CURRENT`, `PORT_FEAT_RESET`, `PORT_FEAT_POWER`, `PORT_FEAT_LOW_SPEED`, `PORT_FEAT_C_CONNECTION`, `PORT_FEAT_C_ENABLE`, `PORT_FEAT_C_SUSPEND`, `PORT_FEAT_C_OVER_CURRENT`, `PORT_FEAT_C_RESET`.

### Hub Request Codes
`HUB_REQ_GET_STATUS`, `HUB_REQ_CLEAR_FEATURE`, `HUB_REQ_SET_FEATURE`, `HUB_REQ_GET_DESCRIPTOR`, `HUB_REQ_GET_PORT_STATUS`.

### Port Status Bits
`PORT_STATUS_CONNECTION` (`$0001`), `PORT_STATUS_ENABLE` (`$0002`), `PORT_STATUS_SUSPEND` (`$0004`), `PORT_STATUS_OVER_CURRENT` (`$0008`), `PORT_STATUS_RESET` (`$0010`), `PORT_STATUS_POWER` (`$0100`), `PORT_STATUS_LOW_SPEED` (`$0200`), `PORT_STATUS_HIGH_SPEED` (`$0400`).

### Port Change Bits
`PORT_CHANGE_CONNECTION` (`$0001`), `PORT_CHANGE_ENABLE` (`$0002`), `PORT_CHANGE_SUSPEND` (`$0004`), `PORT_CHANGE_OVER_CURRENT` (`$0008`), `PORT_CHANGE_RESET` (`$0010`).

## Types

### TUSBHubPortStatus
```pascal
TUSBHubPortStatus = packed record
  wPortStatus : uint16;
  wPortChange : uint16;
end;
```
Returned by GET_PORT_STATUS requests. `wPortStatus` holds current port state bits; `wPortChange` holds change flags that must be cleared by the driver.

### TUSBHubData
Internal per-hub state record. Holds a pointer to the `TUSBDevice`, the hub descriptor, port count, power-on delay, and per-port state.

## Functions and Procedures

### init
```pascal
procedure init;
```
Registers the hub class driver with `driver.mgr` for USB devices with class `$09`.

### load
```pascal
function load(ptr: pointer): boolean;
```
Driver load callback. Reads the hub descriptor, powers on all ports, and adds the hub to the polling list.

### poll_hubs
```pascal
procedure poll_hubs;
```
Called periodically. Sends GET_PORT_STATUS to each port of each registered hub. On detecting `PORT_CHANGE_CONNECTION`, resets the port and calls `driver.bus.usb.core.enumerate_device` or `usb_remove_device` as appropriate.

### UnitTest
```pascal
procedure UnitTest;
```
Verifies port status bit constant values.

## Notes

- Hub polling is driven by the USB core's `poll_all` mechanism rather than hardware interrupts.
- `bPwrOn2PwrGood` from the hub descriptor (in units of 2 ms) is respected when powering on ports.
