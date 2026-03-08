# driver.storage.ctl.ide.ata

ATA (Parallel ATA hard disk) PIO read/write driver.

## Overview

This unit implements PIO-mode data transfer for ATA hard disks on the IDE bus. It provides device identification (IDENTIFY DEVICE command), 28-bit LBA PIO read, and 28-bit LBA PIO write.

All I/O uses port-mapped I/O through the `outb`/`inw` primitives from `arch.x86.util`. A local `outb` wrapper adds a short delay after each write to accommodate slow legacy hardware.

## Dependencies

- `console`
- `driver.mgr`
- `driver.types`
- `driver.storage.ctl.ide.types`
- `memory.heap`
- `driver.storage.types`
- `core.strings`
- `terminal`
- `debug.tracer`
- `core.util`, `arch.x86.util`, `core.panic`
- `arch.x86.memory.virtual`
- `driver.storage.ctl.ide` (implementation)

## Functions and Procedures

### identify_device

```pascal
function identify_device(var device : TIDE_Device) : Boolean;
```

Issues the `ATA_CMD_IDENTIFY` command to the device and reads the 256-word IDENTIFY response into `device.info`. Selects the device, disables interrupts, sends zero counts to the sector/LBA registers, issues the command, waits for DRQ, and reads the 256 `uint16` words. Returns true on success.

### read_pio28

```pascal
function read_pio28(device : TIDE_Device; lba : uint32; count : uint8; buffer : puint16) : boolean;
```

Reads `count` sectors starting at 28-bit `lba` from `device` into `buffer` using PIO mode. Sets up the drive head register with the LBA bits 24–27, programs the sector count and LBA0–LBA2 registers, issues `ATA_CMD_READ_PIO`, and reads 256 words per sector via `inw`. Returns true on success.

### write_pio28

```pascal
function write_pio28(device : TIDE_Device; lba : uint32; count : uint8; buffer : puint16) : boolean;
```

Writes `count` sectors starting at 28-bit `lba` from `buffer` to `device` using PIO mode. Programs registers analogously to `read_pio28`, issues `ATA_CMD_WRITE_PIO`, writes 256 words per sector via `outw`, and issues `ATA_CMD_CACHE_FLUSH` after the final sector. Returns true on success.

## Notes

- The `lba` parameter must fit within 28 bits; addresses `>= $10000000` are rejected by the internal `validate_28bit_address` check.
- LBA bits 24–27 are packed into the low nibble of the drive select register alongside the master/slave bit.
- The local `outb` wrapper calls `psleep(1)` after each write. This is required to give slow IDE controllers time to process commands but significantly reduces throughput; it is appropriate for early-stage testing only.
- This driver is used exclusively by `driver.storage.ctl.ide` and is not integrated with the Phase 2 `TDriverDispatch` interface.
