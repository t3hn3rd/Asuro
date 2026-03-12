# driver.bus.usb.xhci

xHCI (Extensible Host Controller Interface) USB 3.x host controller driver.

## Overview

This unit implements support for xHCI host controllers, which provide USB 3.x SuperSpeed operation as well as backward compatibility with USB 2.0 and USB 1.x devices. It defines xHCI capability and operational register offsets, command/event/transfer ring TRB structures, and implements the `TUSBHCDriver` vtable for the USB core.

## Dependencies

- `driver.bus.usb.types`
- `driver.bus.usb.core`
- `driver.bus.pci`
- `driver.types`
- `core.paging`
- `core.memory`
- `syslog`

## Constants

### Capability Register Offsets
`XHCI_CAP_CAPLENGTH`, `XHCI_CAP_HCIVERSION`, `XHCI_CAP_HCSPARAMS1` (max ports/slots/interrupters), `XHCI_CAP_HCSPARAMS2`, `XHCI_CAP_HCSPARAMS3`, `XHCI_CAP_HCCPARAMS1`, `XHCI_CAP_DBOFF` (doorbell array offset), `XHCI_CAP_RTSOFF` (runtime register set offset).

### Operational Register Offsets
`XHCI_OP_USBCMD`, `XHCI_OP_USBSTS`, `XHCI_OP_PAGESIZE`, `XHCI_OP_DNCTRL`, `XHCI_OP_CRCR` (command ring control), `XHCI_OP_DCBAAP` (device context base address array), `XHCI_OP_CONFIG`, `XHCI_OP_PORTSC`.

### USBCMD Bits
`XHCI_CMD_RUN`, `XHCI_CMD_HCRESET`, `XHCI_CMD_INTE`, `XHCI_CMD_HSEE`.

### USBSTS Bits
`XHCI_STS_HCH` (halted), `XHCI_STS_HSE`, `XHCI_STS_EINT`, `XHCI_STS_PCD`, `XHCI_STS_CNR` (controller not ready).

### PORTSC Bits
`XHCI_PORT_CCS` (current connect status), `XHCI_PORT_PED`, `XHCI_PORT_OCA`, `XHCI_PORT_PR` (port reset), `XHCI_PORT_PLS`, `XHCI_PORT_PP`, `XHCI_PORT_CSC`, `XHCI_PORT_PEC`, `XHCI_PORT_WRC`, `XHCI_PORT_OCC`, `XHCI_PORT_PRC`, `XHCI_PORT_PLC`, `XHCI_PORT_CEC`.

## Functions and Procedures

### load
```pascal
function load(ptr: pointer): boolean;
```
Driver load callback invoked by `driver.mgr` when a PCI xHCI device (class `$0C`, subclass `$03`, prog_if `$30`) is discovered. Maps the MMIO region, resets the controller, allocates device context and command/event/transfer ring structures, starts the controller, and registers with `driver.bus.usb.core`.

### UnitTest
```pascal
procedure UnitTest;
```
Verifies register offset calculations and ring structure sizes.

## Notes

- xHCI uses a ring-based TRB (Transfer Request Block) architecture for all command, event, and transfer communication, replacing the linked-list queue heads used by UHCI/OHCI/EHCI.
- Each USB slot and endpoint has its own transfer ring; a command ring communicates with the host controller firmware; an event ring carries completion notifications back to software.
- The ISR's port status change handler intentionally excludes the PRC (Port Reset Complete) and WRC (Warm Reset Complete) change bits when clearing PORTSC change flags. This prevents the ISR from clearing PRC before the `xhci_port_reset` busy-wait loop can observe that the reset has completed.
