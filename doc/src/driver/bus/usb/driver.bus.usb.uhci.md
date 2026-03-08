# driver.bus.usb.uhci

UHCI (Universal Host Controller Interface) USB 1.x host controller driver.

## Overview

This unit implements support for UHCI host controllers, which provide USB 1.1 full-speed and low-speed operation using I/O-port-mapped registers (not MMIO). It defines UHCI register offsets, command and status bit constants, transfer descriptor (TD) fields, and implements the `TUSBHCDriver` vtable for the USB core.

## Dependencies

- `driver.bus.usb.types`
- `driver.bus.usb.core`
- `driver.bus.pci`
- `driver.types`
- `core.memory`
- `syslog`

## Constants

### I/O Register Offsets
`UHCI_REG_USBCMD` (`$00`), `UHCI_REG_USBSTS` (`$02`), `UHCI_REG_USBINTR` (`$04`), `UHCI_REG_FRNUM` (`$06`), `UHCI_REG_FLBASEADDR` (`$08`), `UHCI_REG_SOFMOD` (`$0C`), `UHCI_REG_PORTSC1` (`$10`), `UHCI_REG_PORTSC2` (`$12`).

### USBCMD Bits
`UHCI_CMD_RS` (run/stop), `UHCI_CMD_HCRESET`, `UHCI_CMD_GRESET`, `UHCI_CMD_EGSM`, `UHCI_CMD_FGR`, `UHCI_CMD_SWDBG`, `UHCI_CMD_CF`, `UHCI_CMD_MAXP`.

### USBSTS Bits
`UHCI_STS_USBINT`, `UHCI_STS_ERROR`, `UHCI_STS_RD`, `UHCI_STS_HSE`, `UHCI_STS_HCPE`, `UHCI_STS_HCH`.

### USBINTR Bits
`UHCI_INTR_TIMEOUT`, `UHCI_INTR_RESUME`, `UHCI_INTR_IOC`, `UHCI_INTR_SP`.

### PORTSC Bits
`UHCI_PORT_CONNECT`, `UHCI_PORT_CONNECT_CHG`, `UHCI_PORT_ENABLE`, `UHCI_PORT_ENABLE_CHG`, `UHCI_PORT_LS`, `UHCI_PORT_RD`, `UHCI_PORT_LSDA`, `UHCI_PORT_RESET`, `UHCI_PORT_SUSPEND`.

### TD Control/Status and Token Bits
Transfer descriptor control word bits for active, stall, buffer-error, babble, NAK, CRC, bitstuff detection, interrupt-on-complete, isochronous, and low-speed flags. Token field PIDs: `UHCI_PID_SETUP` (`$2D`), `UHCI_PID_IN` (`$69`), `UHCI_PID_OUT` (`$E1`).

## Functions and Procedures

### load
```pascal
function load(ptr: pointer): boolean;
```
Driver load callback invoked by `driver.mgr` when a PCI UHCI device (class `$0C`, subclass `$03`, prog_if `$00`) is discovered. Reads the BAR I/O base, resets the controller, allocates and maps the frame list, and registers with `driver.bus.usb.core`.

### UnitTest
```pascal
procedure UnitTest;
```
Verifies register offsets and PID constant values.
