# driver.storage.ctl.ahci.types

AHCI controller hardware types and Asuro device descriptors.

## Overview

This unit defines all memory-mapped register structures, FIS (Frame Information Structure) types, command header/table layouts, and Asuro-level device and controller records used by the AHCI driver. It contains no I/O logic — only type declarations and a single helper function for mapping device signatures.

The AHCI HBA (Host Bus Adapter) exposes its registers as a memory-mapped I/O region. The structures defined here map directly onto that region. Accessing a `THBA_Memory` or `THBA_Port` pointer directly reads/writes hardware registers.

## Dependencies

- `io.syslog`
- `driver.mgr`
- `driver.types`
- `driver.storage.ctl.ide.types`
- `core.ds.lists`
- `memory.heap`
- `driver.bus.pci`
- `core.util`, `arch.x86.util`
- `arch.x86.memory.virtual`

## Constants

| Constant | Value | Description |
|---|---|---|
| `AHCI_CONTROLLER_MODE` | `$80000000` | AHCI enable bit in Global Host Control |
| `CMD_LIST_ALIGN` | `1024` | Required alignment for command list buffers |
| `CMD_TBL_ALIGN` | `128` | Required alignment for command table buffers |
| `NUM_CMD_ENTRIES` | `32` | Maximum command slots per port |
| `SATA_SIG_ATA` | `$00000101` | Port signature for a SATA hard disk |
| `SATA_SIG_ATAPI` | `$EB140101` | Port signature for a SATA optical drive |
| `SATA_SIG_SEMB` | `$C33C0101` | Port signature for an enclosure management bridge |
| `SATA_SIG_PM` | `$96690101` | Port signature for a port multiplier |

## Types

### THBA_Port / PHBA_Port

Memory-mapped register set for one AHCI port (bitpacked, maps directly onto hardware).

| Field | Description |
|---|---|
| `cmdl_basel` / `cmdl_baseu` | Physical address of command list (lower/upper 32 bits) |
| `fis_basel` / `fis_baseu` | Physical address of received FIS buffer |
| `int_status` | Interrupt status register |
| `int_enable` | Interrupt enable register |
| `cmd` | Port command and status register |
| `tfd` | Task file data (shadow of ATA status/error registers) |
| `signature` | Device signature read at port reset |
| `sata_status` | SCR0 — SStatus (link and device detection) |
| `sata_ctrl` | SCR2 — SControl (COMRESET, speed limits) |
| `sata_error` | SCR1 — SError |
| `sata_active` | Outstanding command slots (NCQ) |
| `cmd_issue` | Write a bit here to issue a command slot |

### THBA_Memory / PHBA_Memory

Full AHCI HBA memory-mapped register space (bitpacked).

| Field | Description |
|---|---|
| `capabilites` | Host capabilities |
| `global_ctrl` | Global host control (bit 31 = AHCI enable, bit 0 = HBA reset) |
| `int_status` | Pending interrupt bitmap for all ports |
| `ports_implimented` | Bitmask of implemented ports |
| `version` | AHCI specification version |
| `ports[0..31]` | Per-port register sets |

### THBA_FIS / PHBA_FIS

Received FIS buffer structure. Contains slots for DMA Setup FIS, PIO Setup FIS, D2H Register FIS, Set Device Bits FIS, and Unknown FIS received from the device.

### TFISType

Enumeration of FIS type codes.

| Value | Code | Description |
|---|---|---|
| `FIS_TYPE_REG_H2D` | `$27` | Register FIS — host to device |
| `FIS_TYPE_REG_D2H` | `$34` | Register FIS — device to host |
| `FIS_TYPE_DMA_ACT` | `$39` | DMA Activate FIS |
| `FIS_TYPE_DMA_SETUP` | `$41` | DMA Setup FIS |
| `FIS_TYPE_DATA` | `$46` | Data FIS |
| `FIS_TYPE_BIST` | `$58` | BIST Activate FIS |
| `FIS_TYPE_PIO_SETUP` | `$5F` | PIO Setup FIS |
| `FIS_TYPE_DEV_BITS` | `$A1` | Set Device Bits FIS |

### THBA_FIS_REG_H2D / PHBA_FIS_REG_H2D

Host-to-device register FIS. Used to send ATA commands. Contains FIS type, port multiplier port, command/control flag (`c`), command byte, feature bytes, six LBA bytes, device register, count bytes, and control byte.

### THBA_CMD_HEADER / PHBA_CMD_HEADER

Command list entry (32 bytes). Each of the 32 command slots in a port's command list is one of these.

| Field | Description |
|---|---|
| `cmd_fis_length` | Length of command FIS in dwords |
| `atapi` | Set for ATAPI commands |
| `wrt` | Set for write (host-to-device data) commands |
| `prdtl` | Number of PRDT entries |
| `prdbc` | Byte count transferred (filled by HBA on completion) |
| `cmd_table_base` | Physical address of command table |

### THBA_PRD / TPRDT

Physical Region Descriptor Table entry. Describes one scatter-gather data buffer for a DMA transfer. `dba` is the physical base address, `dbc` is the byte count minus 1.

### THBA_CMD_TABLE / PHBA_CMD_TABLE

Command table in memory. Contains a 64-byte command FIS area, a 16-byte ATAPI command area, reserved bytes, and up to 32 PRDT entries.

### TDeviceType

`(SATA, ATAPI, SEMB, PM)` — SATA device type as determined from the port signature register.

### TIOCompletion

```pascal
TIOCompletion = procedure(success : boolean; userdata : puint32);
```

Callback fired from IRQ context when a command slot completes. Must be short and non-blocking.

### TPendingOp

Per-command-slot pending operation record. Stores the in-use flag, completion callback, and user data pointer.

### TAHCI_Device / PAHCI_Device

Asuro-level AHCI device descriptor (plain record, not bitpacked, to allow safe procedure-pointer storage).

| Field | Description |
|---|---|
| `port` | Pointer to the hardware `THBA_Port` registers |
| `device_type` | `SATA`, `ATAPI`, etc. |
| `ata_info` | 256-word IDENTIFY response |
| `command_list` | Pointer to command list memory |
| `fis` | Pointer to received FIS buffer |
| `command_table` | Pointer to command table memory |
| `pending[0..31]` | Per-slot pending operation records |

### TAHCI_Controller / PAHCI_Controller

Asuro-level AHCI controller descriptor.

| Field | Description |
|---|---|
| `pci_device` | PCI device record from enumeration |
| `mio` | Pointer to `THBA_Memory` (HBA MMIO base) |
| `ata_info` | Controller IDENTIFY response |
| `devices[0..31]` | Per-port device records |

## Functions and Procedures

### get_device_type

```pascal
function get_device_type(sig : uint32) : TDeviceType;
```

Maps a port signature register value to a `TDeviceType` enumeration value.
