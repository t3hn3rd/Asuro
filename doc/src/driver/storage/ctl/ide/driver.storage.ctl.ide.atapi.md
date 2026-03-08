# driver.storage.ctl.ide.atapi

ATAPI (CD-ROM/DVD-ROM via IDE) PIO driver — currently non-functional.

## Overview

This unit implements PIO-mode communication with ATAPI devices connected to the IDE bus. It provides device identification (IDENTIFY PACKET DEVICE), 28-bit LBA sector reads using the ATAPI PACKET command, capacity queries, and an IRQ handler stub.

The source file carries an explicit warning that this driver is **currently not functional**. The IRQ handler (`ide_irq`) only prints a message to the console; it does not clear interrupt status or signal any completion mechanism. As a result, any interrupt-driven path through this driver will stall.

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
- `core.util`, `arch.x86.util`
- `arch.x86.memory.virtual`
- `driver.storage.ctl.ide.ata` (implementation)
- `driver.storage.ctl.ide` (implementation)

## Functions and Procedures

### identify_device

```pascal
function identify_device(var device : TIDE_Device) : Boolean;
```

Issues the `ATA_CMD_IDENTIFY_PACKET` command and reads the 256-word response. Sets `device.info`, `device.blockSize`, and `device.isATAPI := true`. Returns true on success.

### read_pio28

```pascal
function read_pio28(device : TIDE_Device; lba : uint32; count : uint8; buffer : puint16) : boolean;
```

Reads `count` sectors from the ATAPI device using a 12-byte SCSI READ(12) packet command over the ATAPI PACKET protocol. Transfers data in 2048-byte sector chunks via PIO word reads.

### write_pio28

```pascal
function write_pio28(device : TIDE_Device; lba : uint32; count : uint8; buffer : puint16) : boolean;
```

Declared for interface symmetry. ATAPI write is not supported by standard CD-ROM media; this function always returns false.

### get_device_size

```pascal
function get_device_size(var device : TIDE_Device) : uint32;
```

Queries the device capacity using a READ CAPACITY SCSI command packet. Returns the total number of sectors, or 0 on failure.

### ide_irq

```pascal
procedure ide_irq();
```

IDE IRQ handler stub. Prints a message to the console. Does not interact with the IDE status register or any completion mechanism. Registered for IRQ 14 and IRQ 15 by `driver.storage.ctl.ide.load`.

## Notes

- The ATAPI sector size is 2048 bytes; `driver.storage.ctl.ide` sets `storageDevice^.sectorSize := device.blockSize` using the value populated by `identify_device`.
- The `print_status` internal procedure reads all status register bits and prints them to the console; it is used during debugging only.
- Integration with the Phase 2 `TDriverDispatch` interface requires implementing `dispatchRead` to call `read_pio28` and complete the request via `driver.storage.mgr.complete_io`.
