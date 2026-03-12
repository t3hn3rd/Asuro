# driver.hid.ps2.mouse

PS/2 mouse driver with IntelliMouse scroll wheel support.

## Overview

This unit implements a PS/2 mouse driver. It initialises the PS/2 controller, attempts IntelliMouse detection to enable 4-byte packets with a scroll wheel, installs an IRQ 12 interrupt service routine, and assembles incoming bytes into complete mouse packets. Decoded movement, button, and scroll events are dispatched through `driver.hid.mouse`.

## Dependencies

- `driver.mgr`
- `driver.hid.mouse`
- `core.interrupts`
- `debug.tracer`
- `syslog`

## Boot Registration

Registered with `boot.mgr` as `driver.hid.ps2.mouse` at the `device` barrier.

## Types

### TMousePacket
```pascal
TMousePacket = packed record
  flags   : uint8;
  delta_x : uint8;
  delta_y : uint8;
  scroll  : uint8;   { only valid in 4-byte IntelliMouse mode }
end;
```
Raw PS/2 mouse packet assembled from 3 or 4 sequential bytes.

### TMousePos
```pascal
TMousePos = record
  x, y : sint32;
end;
```
Signed cursor position, used internally for accumulation.

## Functions and Procedures

### init
```pascal
procedure init;
```
Initialises the PS/2 controller for mouse operation:
1. Disables both PS/2 ports and flushes the output buffer.
2. Enables the auxiliary (mouse) port and sets IRQ 12.
3. Resets the mouse device.
4. Attempts IntelliMouse detection by sending the sample rate sequence 200 → 100 → 80 and reading the device ID; if ID returns `$03`, enables 4-byte packets.
5. Enables mouse data reporting.
6. Installs the IRQ 12 ISR.

### mouse_isr (internal)
Reads one byte from port `$60` per invocation. Accumulates bytes until a complete 3-byte (standard) or 4-byte (IntelliMouse) packet is assembled. Decodes:
- X/Y deltas using sign bits from the flags byte.
- Overflow flags (discards packet if set).
- Left and right button state changes.
- Scroll delta (byte 4, signed 4-bit value).

Calls `driver.hid.mouse.setMousePos` and `driver.hid.mouse.fireMouseEvent` with the decoded data.

### mouse_wait
```pascal
procedure mouse_wait;
```
Short busy-wait (suitable inside ISR context) on the PS/2 status port until the input buffer is clear.

### mouse_wait_long
```pascal
procedure mouse_wait_long;
```
Extended busy-wait (up to 100,000 iterations) used only during initialisation when IRQs may not yet be active.

## Notes

- IntelliMouse detection uses the specific sample-rate sequence 200/100/80; other sequences may enable different extended modes on some hardware.
- The standard PS/2 packet flags byte bit 3 is always expected to be set; packets where it is clear are discarded as framing errors.
- This driver is automatically disabled when the USB HID mouse driver successfully loads a USB mouse.
