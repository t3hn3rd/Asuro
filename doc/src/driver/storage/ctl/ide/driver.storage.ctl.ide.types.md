# driver.storage.ctl.ide.types

IDE/ATA device types, register constants, and command codes.

## Overview

This unit defines all constants, port addresses, register offsets, command bytes, and data structures used by the IDE ATA and ATAPI drivers. It has no implementation logic — only type and constant declarations.

## Dependencies

None (interface only).

## Constants

### ATA Status Register Bits (ATA_SR_*)

| Constant | Value | Description |
|---|---|---|
| `ATA_SR_BUSY` | `$80` | Device busy |
| `ATA_SR_DRDY` | `$40` | Drive ready |
| `ATA_SR_DF` | `$20` | Drive write fault |
| `ATA_SR_DSC` | `$10` | Drive seek complete |
| `ATA_SR_DRQ` | `$08` | Data request ready |
| `ATA_SR_CORR` | `$04` | Corrected data |
| `ATA_SR_IDX` | `$02` | Index |
| `ATA_SR_ERR` | `$01` | Error |

### ATA Error Register Bits (ATA_ER_*)

| Constant | Value | Description |
|---|---|---|
| `ATA_ER_BBK` | `$80` | Bad sector |
| `ATA_ER_UNC` | `$40` | Uncorrectable data |
| `ATA_ER_MC` | `$20` | No media |
| `ATA_ER_IDNF` | `$10` | ID mark not found |
| `ATA_ER_MCR` | `$08` | No media (media change request) |
| `ATA_ER_ABRT` | `$04` | Command aborted |
| `ATA_ER_TK0NF` | `$02` | Track 0 not found |
| `ATA_ER_AMNF` | `$01` | No address mark |

### ATA Commands (ATA_CMD_*)

| Constant | Value | Description |
|---|---|---|
| `ATA_CMD_READ_PIO` | `$20` | Read sectors (PIO, 28-bit LBA) |
| `ATA_CMD_READ_PIO_EXT` | `$24` | Read sectors (PIO, 48-bit LBA) |
| `ATA_CMD_READ_DMA` | `$C8` | Read DMA (28-bit LBA) |
| `ATA_CMD_READ_DMA_EXT` | `$25` | Read DMA (48-bit LBA) |
| `ATA_CMD_WRITE_PIO` | `$30` | Write sectors (PIO, 28-bit LBA) |
| `ATA_CMD_WRITE_PIO_EXT` | `$34` | Write sectors (PIO, 48-bit LBA) |
| `ATA_CMD_WRITE_DMA` | `$CA` | Write DMA (28-bit LBA) |
| `ATA_CMD_WRITE_DMA_EXT` | `$35` | Write DMA (48-bit LBA) |
| `ATA_CMD_CACHE_FLUSH` | `$E7` | Flush write cache |
| `ATA_CMD_CACHE_FLUSH_EXT` | `$EA` | Flush write cache (48-bit) |
| `ATA_CMD_PACKET` | `$A0` | ATAPI packet command |
| `ATA_CMD_IDENTIFY_PACKET` | `$A1` | IDENTIFY PACKET DEVICE |
| `ATA_CMD_IDENTIFY` | `$EC` | IDENTIFY DEVICE |
| `ATAPI_CMD_READ` | `$A8` | ATAPI READ(12) SCSI command |
| `ATAPI_CMD_EJECT` | `$1B` | ATAPI EJECT media |

### ATA Register Offsets (ATA_REG_*)

Offsets added to the channel base port (`ATA_PRIMARY_BASE` or `ATA_SECONDARY_BASE`).

| Constant | Offset | Description |
|---|---|---|
| `ATA_REG_DATA` | `$00` | Data register (16-bit) |
| `ATA_REG_ERROR` / `ATA_REG_FEATURES` | `$01` | Error (read) / Features (write) |
| `ATA_REG_SECCOUNT` | `$02` | Sector count |
| `ATA_REG_LBA0..LBA2` | `$03..$05` | LBA address bytes 0–2 |
| `ATA_REG_HDDEVSEL` | `$06` | Drive / head select |
| `ATA_REG_COMMAND` / `ATA_REG_STATUS` | `$07` | Command (write) / Status (read) |
| `ATA_REG_CONTROL` / `ATA_REG_ALTSTATUS` | `$0C` | Device control / Alternate status |

### Channel Base Addresses

| Constant | Value | Description |
|---|---|---|
| `ATA_PRIMARY_BASE` | `$1F0` | Primary channel data port base |
| `ATA_PRIMARY_BASE1` | `$3F6` | Primary channel control port |
| `ATA_SECONDARY_BASE` | `$170` | Secondary channel data port base |
| `ATA_SECONDARY_BASE1` | `$376` | Secondary channel control port |
| `ATA_INTERRUPT_PRIMARY` | `$3F6` | Primary channel interrupt control register |
| `ATA_INTERRUPT_SECONDARY` | `$376` | Secondary channel interrupt control register |

### Device Select Values

| Constant | Value | Description |
|---|---|---|
| `ATA_DEVICE_MASTER` | `$A0` | Select master device |
| `ATA_DEVICE_SLAVE` | `$B0` | Select slave device |

## Types

### TPortMode

`(P_READ, P_WRITE)` — Port direction indicator.

### TIdentResponse / PIdentResponse

`array[0..255] of uint16` — Buffer for the 256-word IDENTIFY DEVICE response.

### TIDE_Channel_Registers

Stores base, control, bus master IDE, and interrupt enable values for one IDE channel.

### TIDE_Status

Bitpacked record mapping the ATA status register byte to individual boolean fields: `Busy`, `Ready`, `Fault`, `Seek`, `DRQ`, `CORR`, `IDDEX`, `ERROR`.

### TIDE_Device

Runtime representation of one IDE device slot.

| Field | Description |
|---|---|
| `exists` | True if a device was detected and identified |
| `isPrimary` | True for primary channel, false for secondary |
| `isMaster` | True for master, false for slave |
| `isATAPI` | True for ATAPI (optical) device |
| `status` | Last read status register value |
| `base` | Channel base I/O port |
| `blockSize` | Sector/block size in bytes |
| `info` | Pointer to IDENTIFY response buffer |

### TIDE_PACKET

ATAPI command packet descriptor with command byte, LBA, count, and data buffer pointer.
