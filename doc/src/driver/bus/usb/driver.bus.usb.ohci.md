# driver.bus.usb.ohci

OHCI (Open Host Controller Interface) USB 1.x host controller driver.

## Overview

This unit implements support for OHCI host controllers, which provide USB 1.1 full-speed and low-speed operation. It defines OHCI MMIO register offsets and control bit constants, initialises the hardware, and implements the `TUSBHCDriver` vtable for the USB core.

## Dependencies

- `driver.bus.usb.types`
- `driver.bus.usb.core`
- `driver.bus.pci`
- `driver.types`
- `core.paging`
- `syslog`

## Constants

### MMIO Register Offsets (`OHCI_REG_*`)
Offsets from the OHCI MMIO base: `OHCI_REG_REVISION`, `OHCI_REG_CONTROL`, `OHCI_REG_CMDSTATUS`, `OHCI_REG_INTRSTATUS`, `OHCI_REG_INTRENABLE`, `OHCI_REG_INTRDISABLE`, `OHCI_REG_HCCA`, `OHCI_REG_PERIODICCURRENTED`, `OHCI_REG_CONTROLHEADED`, `OHCI_REG_CONTROLCURRENTED`, `OHCI_REG_BULKHEADED`, `OHCI_REG_BULKCURRENTED`, `OHCI_REG_DONEHEAD`, `OHCI_REG_FMINTERVAL`, `OHCI_REG_FMREMAINING`, `OHCI_REG_FMNUMBER`, `OHCI_REG_PERIODICSTART`, `OHCI_REG_LSTHRESHOLD`, `OHCI_REG_RHDESCRIPTORA`, `OHCI_REG_RHDESCRIPTORB`, `OHCI_REG_RHSTATUS`, `OHCI_REG_RHPORTSTATUS`.

### HcControl Bits
`OHCI_CTRL_CBSR`, `OHCI_CTRL_PLE`, `OHCI_CTRL_IE`, `OHCI_CTRL_CLE`, `OHCI_CTRL_BLE`, `OHCI_CTRL_HCFS_RESET`, `OHCI_CTRL_HCFS_RESUME`, `OHCI_CTRL_HCFS_OPERATIONAL`, `OHCI_CTRL_HCFS_SUSPEND`.

### Interrupt Bits
`OHCI_INTR_SO`, `OHCI_INTR_WDH`, `OHCI_INTR_SF`, `OHCI_INTR_RD`, `OHCI_INTR_UE`, `OHCI_INTR_FNO`, `OHCI_INTR_RHSC`, `OHCI_INTR_OC`, `OHCI_INTR_MIE`.

### Root Hub Descriptor Bits
`OHCI_RHA_NDP` (number of downstream ports mask), `OHCI_RHA_PSM`, `OHCI_RHA_NPS`, `OHCI_RHA_OCPM`.

## Functions and Procedures

### load
```pascal
function load(ptr: pointer): boolean;
```
Driver load callback invoked by `driver.mgr` when a PCI OHCI device (class `$0C`, subclass `$03`, prog_if `$10`) is discovered. Maps the MMIO region, resets the controller, allocates the HCCA block, configures endpoint descriptors, and registers with `driver.bus.usb.core`.

### UnitTest
```pascal
procedure UnitTest;
```
Verifies register offset values and control bit constants.
