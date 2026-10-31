# USB mass storage

`driver.storage.ctl.usb` implements SCSI transparent commands over USB Mass
Storage Bulk-Only Transport (interface class/subclass/protocol `08/06/50`).

It probes INQUIRY, TEST UNIT READY and READ CAPACITY(10), registers LUN 0 with
the storage manager, and exposes READ(10), WRITE(10), REQUEST SENSE and
SYNCHRONIZE CACHE(10). Existing partition discovery and filesystem mounting
apply to the resulting USB disk. Writes complete only after cache synchronization.

## Execution and ownership

An attachment task probes and registers each disk after scheduling starts; boot
initialization never waits on a worker that cannot run yet.

Storage dispatch only publishes a request. One persistent `usb.storage` worker
performs I/O in task context, with one command active per device and a reusable,
page-aligned 4 KiB bounce buffer. Caller buffers are never submitted for DMA.
Commands are split at the bounce-buffer boundary; all LBA/count and buffer-end
arithmetic is checked before submission. CBW/CSW wire sizes, tags, status,
residue, and actual transfer lengths are validated.

OHCI batches bulk data into spans of at most 4 KiB per transfer descriptor,
using the endpoint's hardware toggle carry across packets. A 4 KiB full-speed
read uses one data descriptor instead of 64. Short packets still halt the chain
and report the actual byte count; interrupt endpoint packet sizing is unchanged.

The worker performs reset recovery (class reset, clear bulk-IN halt, clear
bulk-OUT halt) after malformed status or phase errors. Failed SCSI commands
request sense and return storage errors, including write protection.

On disconnect the disk is marked removed immediately. Accepted requests are
completed with errors, and idle volumes are invalidated/unmounted by the worker;
busy volumes are retried. Storage-manager records remain stable tombstones.
Class-driver buffers and context are freed after pending hardware work drains.

Host controllers currently have no cancellation API. A timed-out transfer is
therefore quarantined with its private device snapshot and DMA memory. No further
commands are issued to that device. If hardware never completes, those allocations
remain retained until reboot; freeing them would permit DMA into reused memory.
The timeout uses the PIT's actual frequency and a bounded polling fallback.

## Supported scope

- LUN 0 on a single-interface device with one bulk-IN and one bulk-OUT endpoint.
- Direct-access disks with power-of-two sectors from 512 through 4096 bytes.
- Capacity representable by the existing 32-bit storage-sector API; the
  READ CAPACITY(16) sentinel is rejected.
- OHCI, EHCI and xHCI bulk transfers. OHCI/EHCI report actual data lengths and
  terminate bulk reads on short packets.

UAS, additional LUNs, composite/alternate-setting interfaces, UHCI storage,
optical devices, and media replacement without USB reconnect are not supported.
The current xHCI driver lacks endpoint-ring reset support: a halted bulk endpoint
fails the device closed rather than attempting an unsafe ring reuse.

## Validation

`UnitTest` is called by the boot test suite and is available as `USBMSCTEST`.
Tests use a memory-only mock host controller: wire layout, byte order, capacity
limits, reads, writes, sense errors, short transfers, status stalls, reset ordering,
and request bounds. They perform no disk I/O.

For hardware/VM checks, boot with a disposable USB disk, confirm `USBMSC` discovery
and filesystem mounting, test file read/write/read-back, then unplug while idle
and during I/O. Do not run destructive disk tests against a disk containing data.

Protocol: [USB-IF Bulk-Only Transport 1.0](https://www.usb.org/sites/default/files/usbmassbulk_10.pdf).
