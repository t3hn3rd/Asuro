# driver.hid.usb.keyboard

USB HID boot-protocol keyboard driver.

## Overview

This unit implements a USB HID keyboard class driver. It targets the HID boot protocol (subclass `$01`, protocol `$01`), which uses fixed 8-byte input reports without requiring HID report descriptor parsing. During load, it configures the device for boot protocol and idle mode, locates the interrupt IN endpoint, and submits an initial interrupt transfer. The kernel polling loop calls `poll_keyboards` each frame to process completed reports.

## Dependencies

- `driver.bus.usb.core`
- `driver.bus.usb.types`
- `driver.mgr`
- `driver.hid.keyboard`
- `driver.hid.ps2.keyboard`
- `syslog`

## Types

### TUSBKeyboardData
Per-device state record:

| Field | Type | Description |
|---|---|---|
| `device` | `PUSBDevice` | Pointer to the enumerated USB device |
| `endpoint` | `TUSBEndpoint` | Interrupt IN endpoint descriptor |
| `report` | `array[0..7] of uint8` | Current 8-byte HID boot report buffer |
| `prev_report` | `array[0..7] of uint8` | Previous report for change detection |
| `transfer` | `PUSBTransfer` | Handle to the pending interrupt transfer |
| `active` | `boolean` | Whether this keyboard slot is in use |
| `fail_count` | `uint8` | Consecutive transfer failure counter |

## Constants

### HID_TO_ASCII / HID_TO_ASCII_SHIFT
Two lookup tables of 104 entries mapping HID usage IDs (keycodes 0–103) to ASCII characters, for unshifted and shifted states respectively.

## Functions and Procedures

### init
```pascal
procedure init;
```
Registers the USB keyboard class driver with `driver.mgr` for USB devices with class `$03` (HID), subclass `$01` (Boot), protocol `$01` (Keyboard).

### load
```pascal
function load(ptr: pointer): boolean;
```
Driver load callback. Sends SET_PROTOCOL(Boot) and SET_IDLE(0) control requests, finds the first interrupt IN endpoint, allocates a `TUSBKeyboardData` slot, submits the first interrupt transfer, and disables the PS/2 keyboard driver to prevent duplicate input.

### poll_keyboards
```pascal
procedure poll_keyboards;
```
Called each kernel frame. For each active keyboard slot, checks the pending transfer status:
- `tsSuccess`: compares report to previous report, translates changed keycodes via `HID_TO_ASCII`/`HID_TO_ASCII_SHIFT`, fires events through `driver.hid.keyboard.reportKeyEvent`, saves current report as previous, and resubmits the transfer.
- Error status: increments `fail_count`; deactivates the slot after 3 consecutive failures and attempts to clear the endpoint halt.

### UnitTest
```pascal
procedure UnitTest;
```
Verifies HID-to-ASCII table coverage and key tracking logic.

## Notes

- The 8-byte boot report layout is: byte 0 = modifier bitmask (Ctrl/Shift/Alt/GUI), byte 1 = reserved, bytes 2–7 = up to 6 simultaneous key usage IDs.
- A usage ID of `$00` in bytes 2–7 indicates no key; `$01` indicates rollover error.
- Modifier keys (Shift, Ctrl, Alt) are extracted from byte 0 bit fields and passed to `driver.hid.keyboard.reportKeyEvent` in the `TKeyInfo` modifier fields.
