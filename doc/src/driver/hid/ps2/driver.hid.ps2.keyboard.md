# driver.hid.ps2.keyboard

PS/2 keyboard driver with scan code set 1 translation.

## Overview

This unit implements a PS/2 keyboard driver. It populates scan code translation matrices for normal and shifted key states, installs an IRQ 1 interrupt service routine, and translates raw scan codes into ASCII characters which are then dispatched through `driver.hid.keyboard.reportKeyEvent`. The driver is force-loaded by the driver manager during system initialisation without requiring a PCI device match.

## Dependencies

- `driver.mgr`
- `driver.hid.keyboard`
- `core.interrupts`
- `debug.tracer`
- `syslog`

## Functions and Procedures

### lang_USA
```pascal
procedure lang_USA;
```
Populates `key_matrix[1..256]` and `key_matrix_shift[1..256]` with US QWERTY layout characters using PS/2 scan code set 1 index values. Must be called before the ISR is installed.

### init
```pascal
procedure init;
```
Calls `lang_USA`, installs the keyboard ISR on IRQ 1, and registers the driver with `driver.mgr` using `force_load := true`.

### keyboard_isr
Internal ISR. Reads a byte from the PS/2 data port (`$60`). Translates the byte using the appropriate matrix (normal or shifted based on `driver.hid.keyboard.is_shift`), constructs a `TKeyInfo`, and calls `driver.hid.keyboard.reportKeyEvent`.

## Notes

- Scan codes `$E0` (extended) and `$E1` (pause/break) prefixes are detected and handled separately from single-byte codes.
- Release codes (scan code OR `$80`) set `is_down_code := false` on the `TKeyInfo`.
- This driver is automatically disabled when the USB HID keyboard driver successfully loads a USB keyboard, to prevent duplicate key events.
