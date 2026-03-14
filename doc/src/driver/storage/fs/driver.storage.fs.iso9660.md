# driver.storage.fs.iso9660

Read-only ISO 9660 (CDFS) filesystem driver.

## Overview

This unit implements an ISO 9660 filesystem driver for reading files and directories from CD-ROM, DVD-ROM, and bootable ISO images. The driver is read-only; no write, create, or delete operations are provided.

ISO 9660 identification relies on reading the Primary Volume Descriptor (PVD) at sector 16 and checking the `'CD001'` standard identifier. The driver registers an `identifyCallback` and async read hooks with `driver.storage.fs.mgr`.

Joliet and Rock Ridge extensions are not currently supported; filenames are restricted to plain ISO 9660 8.3 uppercase format with a version suffix (e.g., `README.TXT;1`).

Both file reads and directory reads are implemented as fully asynchronous operations using callback-based state machines. The completion callback fires from ISR or driver context when the operation finishes.

## Dependencies

- `driver.storage.fs.mgr`
- `core.ds.lists`
- `memory.heap`
- `driver.storage.mgr`
- `driver.storage.types`
- `core.strings`
- `io.syslog`
- `debug.tracer`
- `core.util`, `arch.x86.util`
- `driver.storage.vol.mgr`
- `proc.mgr`, `proc.types` (implementation)

## Boot Registration

Registered with `boot.mgr` as `driver.storage.fs.iso9660`, depending on `driver.storage.fs.mgr`.

## Types

### TPVD / PPVD

ISO 9660 Primary Volume Descriptor (packed subset).

| Field | Description |
|---|---|
| `vdType` | Descriptor type (1 = Primary) |
| `stdIdent` | Standard identifier (`'CD001'`) |
| `volumeSpaceSizeLSB` | Total number of logical blocks (little-endian) |
| `logicalBlockSizeLSB` | Logical block size in bytes (little-endian) |
| `rootDirRecord` | 34-byte inline root directory record |

### TDirRecord / PDirRecord

ISO 9660 directory record fixed-length prefix. The variable-length file identifier follows immediately in memory.

| Field | Description |
|---|---|
| `recLen` | Total length of this record in bytes |
| `extentLBA_LSB` | LBA of file data extent (little-endian) |
| `dataLen_LSB` | Data length in bytes (little-endian) |
| `fileFlags` | Bit 1 set = directory |
| `fileIdLen` | Length of file identifier that follows |

## Constants

### PVD_SECTOR

`16` — Sector number of the Primary Volume Descriptor on all ISO 9660 media.

## Functions and Procedures

### init

```pascal
procedure init();
```

Populates the `filesystem` descriptor with the identify callback and async I/O hooks, then registers with the filesystem manager.

### readFile_async

```pascal
procedure readFile_async(volume : PStorage_Volume; directory : pchar; fileName : pchar;
                         buffer : puint32; bytecount : puint32;
                         callback : TIOCallback; callbackData : pointer);
```

Asynchronously reads the entire contents of a file. The driver reads the PVD, walks the directory tree to locate the file, reads its extent, and fires `callback` when complete. On success, `buffer^` points to a heap-allocated buffer containing the file data and `bytecount^` holds its size. The caller owns the buffer and must free it.

### readDir_async

```pascal
procedure readDir_async(volume : PStorage_Volume; directory : pchar;
                        resultList : PPLinkedListBase; status : puint32;
                        callback : TIOCallback; callbackData : pointer);
```

Asynchronously reads a directory listing. Walks the ISO 9660 directory tree for `directory`, populates `resultList^` with `TDirectory_Entry` records, and fires `callback` on completion. The result list is heap-allocated and caller-owned.

## Notes

- The sector size for ISO 9660 media is typically 2048 bytes; `readSectors` defaults to 2048 if the device reports a zero sector size.
- The `identifyCallback` reads sector 16 and verifies the `'CD001'` signature. It does not check the descriptor version.
- Version suffixes (e.g., `;1`) in ISO 9660 filenames are stripped during directory traversal so that callers can use bare names.
- Only the synchronous `identifyCallback` and async read hooks are registered; synchronous read callbacks are nil. The VFS layer handles this correctly by using the async hooks with a spin-wait when the sync variant is absent.
