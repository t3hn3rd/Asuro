# driver.net.dev.e1000

Intel e1000 family Gigabit Ethernet NIC driver.

## Overview

This unit implements a driver for the Intel e1000 and compatible Gigabit Ethernet controllers. It initialises the NIC via MMIO, reads the MAC address from EEPROM, configures receive and transmit descriptor rings, and registers the device with `driver.net` as the active network interface.

The driver handles the following PCI device IDs (all vendor `$8086`):

| Device ID | Description |
|---|---|
| `$100E` | Intel 82540EM (e1000, common in QEMU) |
| `$153A` | Intel I217-LM |
| `$10EA` | Intel 82577LM |

## Dependencies

- `driver.net`
- `driver.net.types`
- `driver.bus.pci`
- `driver.types`
- `core.paging`
- `core.memory`
- `syslog`

## Constants

### MMIO Register Offsets
`E1000_REG_CTRL` (`$0000`), `E1000_REG_STATUS` (`$0008`), `E1000_REG_EEPROM` (`$0014`), `E1000_REG_IMASK` (`$00D0`), `E1000_REG_RCTRL` (`$0100`), `E1000_REG_RXDESCLO` (`$2800`), `E1000_REG_RXDESCHI` (`$2804`), `E1000_REG_RXDESCLEN` (`$2808`), `E1000_REG_RXDESCHEAD` (`$2810`), `E1000_REG_RXDESCTAIL` (`$2818`), `E1000_REG_TXDESCLO` (`$3800`), `E1000_REG_TXDESCHI` (`$3804`), `E1000_REG_TXDESCLEN` (`$3808`), `E1000_REG_TXDESCHEAD` (`$3810`), `E1000_REG_TXDESCTAIL` (`$3818`), `E1000_REG_TCTRL` (`$0400`).

### RCTL Bits
`E1000_RCTL_EN`, `E1000_RCTL_SBP`, `E1000_RCTL_UPE` (unicast promiscuous), `E1000_RCTL_MPE` (multicast promiscuous), `E1000_RCTL_LBM`, `E1000_RCTL_BAM` (broadcast accept), `E1000_RCTL_BSIZE_2048`, `E1000_RCTL_SECRC` (strip Ethernet CRC).

## Functions and Procedures

### load
```pascal
function load(ptr: pointer): boolean;
```
Driver load callback. Maps the BAR0 MMIO region, resets the controller, reads the MAC address from EEPROM, configures the receive and transmit descriptor rings, enables the receiver, and calls `driver.net.registerNetworkCard` with the send callback and MAC address.

### send (internal callback)
Writes a frame into the next available transmit descriptor, updates the tail pointer, and waits for the transmit-complete status bit.

### recv (called from interrupt or polling)
Walks the receive descriptor ring, passes each completed frame to `driver.net.recv`, and replenishes the ring.

## Notes

- The EEPROM read procedure uses the EEPROM register's start/done bit protocol; a bitwise read loop is used for NICs without auto-read support.
- QEMU's default e1000 emulation (`$100E`) does not require an interrupt handler if the driver polls the receive tail pointer.
