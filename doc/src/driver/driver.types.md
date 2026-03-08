# driver.types

Shared PCI constants and data structures used across all driver subsystems.

## Overview

This unit defines common PCI-related constants and record types shared across the Asuro driver framework. It includes I/O port addresses for PCI configuration space access, PCI command register bit masks, MSI (Message Signalled Interrupts) control bits, and the `TPCI_Device` record representing a discovered PCI endpoint device.

## Constants

### PCI_CONFIG_ADDRESS_PORT
Value: `$0CF8`. The x86 I/O port used to select a PCI configuration register.

### PCI_CONFIG_DATA_PORT
Value: `$0CFC`. The x86 I/O port used to read or write the selected PCI configuration register.

### PCI_COMMAND_IO_SPACE
Value: `$0001`. Enables I/O space access in the PCI command register.

### PCI_COMMAND_MEM_SPACE
Value: `$0002`. Enables memory-mapped I/O access.

### PCI_COMMAND_BUS_MASTER
Value: `$0004`. Enables bus mastering (required for DMA).

### PCI_COMMAND_SPECIAL_CYC
Value: `$0008`. Enables special cycle generation.

### PCI_COMMAND_MEM_WRITE
Value: `$0010`. Enables memory write and invalidate.

### PCI_COMMAND_VGA_PALETTE
Value: `$0020`. Enables VGA palette snooping.

### PCI_COMMAND_PARITY
Value: `$0040`. Enables parity error response.

### PCI_COMMAND_WAIT
Value: `$0080`. Enables address/data stepping.

### PCI_COMMAND_SERR
Value: `$0100`. Enables the SERR driver.

### PCI_COMMAND_FAST_BACK
Value: `$0200`. Enables fast back-to-back transactions.

### PCI_COMMAND_INT_DISABLE
Value: `$0400`. Disables INTx interrupts.

### PCI_COMMAND_SERR_ENABLE
Value: `$8000`. Enables SERR signalling.

### PCI_CAP_ID_MSI
Value: `$05`. Capability ID for MSI in the PCI capabilities list.

### MSI_CONTROL_ENABLE
Value: `1 shl 0`. Bit 0 of the MSI Control register — enables MSI.

### MSI_CONTROL_64BIT
Value: `1 shl 7`. Bit 7 of the MSI Control register — indicates 64-bit address support.

### MSI_CONTROL_PVMASK
Value: `1 shl 8`. Bit 8 of the MSI Control register — per-vector masking capability (optional).

## Types

### TPCI_Device / PPCI_Device

A `bitpacked record` representing the full PCI configuration space header for a type-0 (endpoint) device. Fields map directly to the PCI 2.x standard header layout.

| Field | Type | Description |
|---|---|---|
| `bus` | `uint8` | PCI bus number |
| `slot` | `uint8` | PCI slot (device) number |
| `func` | `uint8` | PCI function number |
| `device_id` | `uint16` | Device ID assigned by the vendor |
| `vendor_id` | `uint16` | Vendor ID (PCI-SIG assigned) |
| `status` | `uint16` | PCI status register |
| `command` | `uint16` | PCI command register |
| `class_code` | `uint8` | Device class (e.g. $0C = Serial Bus) |
| `subclass_class` | `uint8` | Device subclass |
| `prog_if` | `uint8` | Programming interface byte |
| `revision_id` | `uint8` | Device revision |
| `BIST` | `uint8` | Built-in self-test register |
| `header_type` | `uint8` | Header type; bit 7 indicates multi-function device |
| `latency_timer` | `uint8` | PCI latency timer |
| `cache_size` | `uint8` | Cache line size |
| `address0..address5` | `uint32` | Base Address Registers (BAR0-BAR5) |
| `CIS_pointer` | `uint32` | CardBus CIS pointer |
| `subsystem_id` | `uint16` | Subsystem ID |
| `subsystem_vid` | `uint16` | Subsystem vendor ID |
| `exp_rom_addr` | `uint32` | Expansion ROM base address |
| `capabilities` | `uint8` | Offset to first capability in capability list |
| `max_latency` | `uint8` | Maximum latency |
| `min_grant` | `uint8` | Minimum grant |
| `interrupt_pin` | `uint8` | Interrupt pin used (INTA-INTD) |
| `interrupt_line` | `uint8` | IRQ line assigned by system firmware |

### TDeviceArray

```pascal
TDeviceArray = array[0..31] of TPCI_Device;
```

A fixed-size array of up to 32 PCI devices, returned by `getDeviceInfo` in `driver.bus.pci`.
