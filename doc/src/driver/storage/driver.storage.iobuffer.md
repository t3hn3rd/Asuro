# driver.storage.iobuffer

Safe I/O buffer allocation helpers aligned to volume sector geometry.

## Overview

This unit provides a pair of helpers that allocate and free I/O buffers correctly sized for block device transfers. Callers pass a `PStorage_Volume` and a minimum byte size; the allocator rounds up to a whole number of sectors so that DMA and block I/O operations never overrun the buffer.

## Dependencies

- `memory.heap`
- `driver.storage.types`
- `debug.tracer`

## Functions and Procedures

### AllocateIOBuffer

```pascal
function AllocateIOBuffer(volume : PStorage_Volume; size : uint32) : puint32;
```

Allocates a buffer of at least `size` bytes, rounded up to a whole number of sectors based on `volume^.device^.sectorSize`. If `sectorSize` is zero, defaults to 512 bytes. Returns a pointer to the allocated buffer, or nil if `volume` is nil, `size` is zero, or allocation fails.

### FreeIOBuffer

```pascal
function FreeIOBuffer(buf : puint32) : boolean;
```

Frees a buffer previously allocated by `AllocateIOBuffer`. Returns true on success, false if `buf` is nil.

## Notes

- The sector-aligned rounding ensures safety for DMA transfers on devices with sector sizes larger than the requested data (e.g., 2048-byte ATAPI sectors).
- Callers are responsible for zeroing the buffer if required; this unit does not initialise the allocated memory.
