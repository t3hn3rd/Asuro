# driver.storage.ctl.ahci

AHCI (Advanced Host Controller Interface) SATA storage driver.

## Overview

This unit is the primary storage controller driver for Asuro. It discovers AHCI controllers via PCI enumeration (class `$01`, subclass `$06`, programming interface `$01`), maps the HBA memory-mapped registers, enumerates active ports, identifies attached SATA and ATAPI devices, and registers them with `driver.storage.mgr`.

The driver implements the Phase 2 `TDriverDispatch` interface: `ahci_dispatch_read` and `ahci_dispatch_write` (and `ahci_dispatch_atapi_read` for optical drives) are assigned to each registered `TStorage_Device`. When the storage manager dequeues a request, it calls the appropriate dispatch procedure, which issues an async DMA command to the HBA. The IRQ handler (`ahci_isr`) is registered for the AHCI interrupt vector and fires `complete_io` on the storage manager when a command slot clears.

Both SATA hard disks and ATAPI optical drives are supported through this driver.

## Dependencies

- `driver.storage.ctl.ahci.types`
- `driver.mgr`
- `driver.types`
- `driver.storage.ctl.ide.types`
- `arch.x86.isr.ioapic`
- `arch.x86.isr.mgr`
- `core.ds.lists`
- `memory.heap`
- `driver.bus.pci`
- `driver.storage.mgr`
- `driver.storage.types`
- `io.syslog`
- `core.util`, `arch.x86.util`
- `arch.x86.memory.virtual`

## Variables

| Name | Type | Description |
|---|---|---|
| `ahciControllers` | `PDList` | List of all discovered `TAHCI_Controller` instances |
| `page_base` | `puint32` | Base of the memory page used for command/FIS structures |

## Functions and Procedures

### init

```pascal
procedure init();
```

Registers the AHCI driver with `driver.mgr` for PCI class `$01`, subclass `$06`, interface `$01`.

### load

```pascal
function load(ptr : void) : boolean;
```

Called by `driver.mgr` when a matching PCI controller is found. Allocates a `TAHCI_Controller`, maps the HBA MMIO via `arch.x86.memory.virtual`, takes BIOS ownership of the controller, enables AHCI mode, registers the ISR, and calls `check_ports` to enumerate devices.

### check_ports

```pascal
procedure check_ports(controller : PAHCI_Controller);
```

Iterates all implemented ports (bits set in `ports_implemented`). For ports with a device present (DET=3 in SStatus, IPM=1), reads the signature and calls `identify_device` to complete initialisation and register the device.

### identify_device

```pascal
procedure identify_device(controller : PAHCI_Controller; portIndex : uint32; isATAPI : boolean);
```

Performs a full port reset, allocates and maps command list, FIS buffer, and command table memory, issues an IDENTIFY (or IDENTIFY PACKET DEVICE for ATAPI) command, and registers the device with `driver.storage.mgr` with the appropriate dispatch function pointers.

### ahci_isr

```pascal
procedure ahci_isr();
```

AHCI interrupt service routine. Reads the HBA interrupt status, clears pending interrupts per port, identifies which command slot completed, and calls the corresponding `TPendingOp.completion` callback. The completion callback in turn calls `driver.storage.mgr.complete_io`.

### find_cmd_slot

```pascal
function find_cmd_slot(device : PAHCI_Device) : uint32;
```

Returns the index of a free command slot by scanning the port's `cmd_issue` and `sata_active` registers. Returns `$FFFFFFFF` if no slot is free.

### send_read_dma_async

```pascal
function send_read_dma_async(device : PAHCI_Device; lba : uint64; count : uint32; buffer : puint32; completion : TIOCompletion; userdata : puint32) : boolean;
```

Builds a DMA Read Extended (48-bit LBA) FIS, sets up the PRDT entry for `buffer`, records the completion callback in the slot's `TPendingOp`, and issues the command via `cmd_issue`. Returns true if a free slot was found and the command was issued.

### send_write_dma_async

```pascal
function send_write_dma_async(device : PAHCI_Device; lba : uint64; count : uint32; buffer : puint32; completion : TIOCompletion; userdata : puint32) : boolean;
```

Analogous to `send_read_dma_async` but issues a DMA Write Extended FIS with the write bit set in the command header.

### read_atapi_async

```pascal
function read_atapi_async(device : PAHCI_Device; lba : uint64; count : uint32; buffer : puint32; completion : TIOCompletion; userdata : puint32) : boolean;
```

Builds an ATAPI READ(12) packet command, sets the ATAPI bit in the command header, and issues the command via `cmd_issue`.

### ahci_dispatch_read

```pascal
procedure ahci_dispatch_read(device : PStorage_Device; request : PIORequest);
```

`TDriverDispatch` implementation for SATA reads. Wraps `send_read_dma_async` with a `TIOCompletion` callback that calls `driver.storage.mgr.complete_io` with the request.

### ahci_dispatch_write

```pascal
procedure ahci_dispatch_write(device : PStorage_Device; request : PIORequest);
```

`TDriverDispatch` implementation for SATA writes. Wraps `send_write_dma_async`.

### ahci_dispatch_atapi_read

```pascal
procedure ahci_dispatch_atapi_read(device : PStorage_Device; request : PIORequest);
```

`TDriverDispatch` implementation for ATAPI reads. Wraps `read_atapi_async`.

### send_read_capacity

```pascal
function send_read_capacity(device : PAHCI_Device; sectorCount : puint32; blockSize : puint32) : boolean;
```

Issues a SCSI READ CAPACITY(10) command to query the device's sector count and block size. Fills `sectorCount^` and `blockSize^` on success. Used during ATAPI device initialisation.

## Notes

- Command/FIS memory is allocated from a single page using `arch.x86.memory.virtual`. Physical addresses are used for HBA DMA descriptors; virtual-to-physical translation is performed at setup time.
- The port reset sequence (`reset_port`) issues a COMRESET via `PxSCTL.DET = 1`, waits for the link to re-establish (`PxSSTS.DET = 3`), then clears the `PxSERR` register.
- `stop_port` and `start_port` manage the port command (`PxCMD`) ST and FRE bits in the correct order as required by the AHCI specification.
- The AHCI ISR identifies completions by comparing the pre-issue and post-issue `cmd_issue` bitmasks. Each bit that transitioned from 1 to 0 corresponds to a completed slot.
- ATAPI devices use 2048-byte sectors; the `sectorSize` field on the registered `TStorage_Device` is set from the READ CAPACITY response.
