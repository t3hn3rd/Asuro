# driver.bus.usb.ehci

EHCI (Enhanced Host Controller Interface) USB 2.0 host controller driver.

## Overview

This unit implements support for EHCI host controllers, which provide USB 2.0 high-speed operation. It defines the EHCI capability and operational register offsets and bit constants, initialises the hardware, and implements the `TUSBHCDriver` vtable for the USB core.

## Dependencies

- `driver.bus.usb.types`
- `driver.bus.usb.core`
- `driver.bus.pci`
- `driver.types`
- `core.paging`
- `syslog`

## Constants

### Capability Register Offsets (`EHCI_CAP_*`)
Offsets from the EHCI MMIO base address into the capability register block: `EHCI_CAP_CAPLENGTH`, `EHCI_CAP_HCIVERSION`, `EHCI_CAP_HCSPARAMS`, `EHCI_CAP_HCCPARAMS`.

### Operational Register Offsets (`EHCI_OP_*`)
Offsets from `CAP_BASE + CAPLENGTH` into the operational register block: `EHCI_OP_USBCMD`, `EHCI_OP_USBSTS`, `EHCI_OP_USBINTR`, `EHCI_OP_FRINDEX`, `EHCI_OP_PERIODICLISTBASE`, `EHCI_OP_ASYNCLISTADDR`, `EHCI_OP_CONFIGFLAG`, `EHCI_OP_PORTSC`.

### USBCMD Bits
`EHCI_CMD_RUN`, `EHCI_CMD_HCRESET`, `EHCI_CMD_PSE` (periodic schedule enable), `EHCI_CMD_ASE` (asynchronous schedule enable), `EHCI_CMD_IAAD` (interrupt on async advance doorbell).

### USBSTS Bits
`EHCI_STS_HALTED`, `EHCI_STS_RECLAMATION`, `EHCI_STS_PSS`, `EHCI_STS_ASS`.

### PORTSC Bits
`EHCI_PORT_CONNECT`, `EHCI_PORT_CONNECT_CHG`, `EHCI_PORT_ENABLE`, `EHCI_PORT_RESET`, `EHCI_PORT_POWER`, `EHCI_PORT_OWNER`.

## Functions and Procedures

### load
```pascal
function load(ptr: pointer): boolean;
```
Driver load callback invoked by `driver.mgr` when a PCI EHCI device (class `$0C`, subclass `$03`, prog_if `$20`) is discovered. Maps the MMIO region, resets the controller, builds queue head structures, registers with `driver.bus.usb.core`, and triggers a port scan.

### UnitTest
```pascal
procedure UnitTest;
```
Verifies register offset calculations and bitfield constants.
