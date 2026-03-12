# driver.hid.usb.mouse

USB HID boot-protocol mouse driver.

## Overview

This unit implements a USB HID mouse class driver. It targets the HID boot protocol (subclass `$01`, protocol `$02`), which uses fixed 3-byte or 4-byte input reports. After locating the interrupt IN endpoint during load, it submits an initial transfer and relies on `poll_mice` being called each frame to process completed reports and dispatch events through `driver.hid.mouse`.

## Boot Registration

Registered with `boot.mgr` as `driver.hid.usb.mouse` at the `device` barrier. The barrier order places `device` after `bus`, ensuring `driver.bus.usb.core.init` has run (creating the HC list and zeroing completion hooks) before the mouse driver registers its class driver and completion hook.

## Dependencies

- `driver.bus.usb.core`
- `driver.bus.usb.types`
- `driver.mgr`
- `driver.hid.mouse`
- `driver.hid.ps2.mouse`
- `syslog`

## Types

### TUSBMouseData
Per-device state record:

| Field | Type | Description |
|---|---|---|
| `device` | `PUSBDevice` | Pointer to the enumerated USB device |
| `endpoint` | `TUSBEndpoint` | Interrupt IN endpoint descriptor |
| `report` | `array[0..3] of uint8` | 4-byte HID report buffer |
| `x`, `y` | `sint32` | Accumulated cursor position |
| `lmb`, `rmb` | `boolean` | Previous left/right button states |
| `transfer` | `PUSBTransfer` | Handle to the pending interrupt transfer |
| `active` | `boolean` | Whether this mouse slot is in use |
| `fail_count` | `uint8` | Consecutive failure counter |

## Functions and Procedures

### init
```pascal
procedure init;
```
Registers the USB mouse class driver with `driver.mgr` for USB devices with class `$03` (HID), subclass `$01` (Boot), protocol `$02` (Mouse).

### load
```pascal
function load(ptr: pointer): boolean;
```
Driver load callback. Sends SET_PROTOCOL(Boot) and SET_IDLE(0), locates the interrupt IN endpoint, allocates a `TUSBMouseData` slot, submits the first interrupt transfer, and disables the PS/2 mouse driver.

### poll_mice
```pascal
procedure poll_mice;
```
Called each kernel frame. On `tsSuccess`, calls `process_report` then resubmits the transfer. On error, increments `fail_count` and deactivates after 3 failures.

### process_report (internal)
Extracts X delta (`mouse_delta_x`), Y delta (`mouse_delta_y`), scroll (`mouse_scroll`), and button bits (`mouse_buttons`) from the report buffer. Detects button transitions (press, release, click) and fires the appropriate `driver.hid.mouse` events. Updates cursor position via `driver.hid.mouse.setMousePos`.

### mouse_delta_x / mouse_delta_y / mouse_scroll
Helper functions that sign-extend the relevant report byte to a signed 8-bit value.

### mouse_buttons
Returns the button state bitmask from report byte 0.

### UnitTest
```pascal
procedure UnitTest;
```
Verifies delta extraction, scroll sign extension, and button bitmask parsing.

## Notes

- The boot protocol report layout is: byte 0 = button bitmask (bits 0=left, 1=right, 2=middle), byte 1 = X delta (signed), byte 2 = Y delta (signed), byte 3 = scroll (signed, optional).
- The driver disables the PS/2 mouse on successful load to prevent duplicate pointer events.
